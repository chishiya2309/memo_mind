import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/memo_mind_database.dart';
import '../../deck_management/data/local_deck_repository_io.dart';
import '../../deck_management/domain/deck_models.dart';
import '../../home/domain/home_dashboard_data.dart';
import '../domain/review_models.dart';
import '../domain/review_repository.dart';
import '../domain/sm2_scheduler.dart';

class LocalReviewRepository implements ReviewRepository {
  LocalReviewRepository({
    MemoMindDatabase? database,
    DateTime Function()? clock,
  }) : _database = database ?? MemoMindDatabase.instance,
       _clock = clock ?? DateTime.now;
  final MemoMindDatabase _database;
  final DateTime Function() _clock;
  static const _uuid = Uuid();
  static const _scheduler = Sm2Scheduler();

  @override
  Future<List<ReviewDeck>> getDecks() async {
    final db = await _database.database;
    return _decks(db, _clock());
  }

  Future<List<ReviewDeck>> _decks(DatabaseExecutor db, DateTime now) async {
    final rows = await db.rawQuery(
      '''
      SELECT d.deck_id, d.title, COUNT(c.card_id) AS active_count,
        COALESCE(SUM(CASE WHEN c.due_date <= ? THEN 1 ELSE 0 END),0) AS due_count,
        COALESCE(SUM(CASE WHEN c.repetitions > 0 THEN 1 ELSE 0 END),0) AS learned_count
      FROM decks d LEFT JOIN cards c ON c.deck_id = d.deck_id AND c.status = 'active'
      WHERE d.status='active'
      GROUP BY d.deck_id ORDER BY d.updated_at DESC, d.deck_id
    ''',
      [now.millisecondsSinceEpoch],
    );
    return rows
        .map(
          (r) => ReviewDeck(
            id: r['deck_id'] as String,
            title: r['title'] as String,
            activeCount: r['active_count'] as int,
            dueCount: r['due_count'] as int,
            learnedCount: r['learned_count'] as int,
          ),
        )
        .toList();
  }

  @override
  Future<HomeDashboardData> getDashboard() async {
    final db = await _database.database;
    final now = _clock();
    final decks = await _decks(db, now);
    final local = now.toLocal();
    final start = DateTime(local.year, local.month, local.day);
    final reviewed =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(DISTINCT card_id) FROM review_events WHERE reviewed_at >= ? AND reviewed_at <= ?',
            [start.millisecondsSinceEpoch, now.millisecondsSinceEpoch],
          ),
        ) ??
        0;
    final due = decks.fold<int>(0, (sum, d) => sum + d.dueCount);
    final activeSession = await getActiveSession();
    return HomeDashboardData(
      now: now,
      review: ReviewPlan(
        totalToday: reviewed + due,
        reviewedToday: reviewed,
        deckCount: decks.where((d) => d.dueCount > 0).length,
        estimatedMinutes: (due / 3).ceil(),
      ),
      totalDeckCount: decks.length,
      hasActiveReviewSession: activeSession != null,
      recentDecks: decks
          .map(
            (d) => DeckPreview(
              id: d.id,
              title: d.title,
              dueCount: d.dueCount,
              estimatedMinutes: (d.dueCount / 3).ceil(),
              learnedPercent: d.activeCount == 0
                  ? 0
                  : (d.learnedCount * 100 / d.activeCount).round(),
              tone: DeckTone.indigo,
            ),
          )
          .toList(),
    );
  }

  ReviewSession _session(Map<String, Object?> row) => ReviewSession(
    id: row['session_id'] as String,
    deckId: row['deck_id'] as String?,
    dueOnly: row['due_only'] == 1,
    queue: (jsonDecode(row['queue'] as String) as List).cast<String>(),
    learningQueue: (jsonDecode(row['learning_queue'] as String) as List)
        .cast<String>(),
    initialCount: row['initial_count'] as int,
    status: row['status'] as String,
  );

  Future<Map<String, Object?>?> _card(DatabaseExecutor db, String id) async {
    final rows = await db.rawQuery(
      '''SELECT c.* FROM cards c JOIN decks d ON d.deck_id=c.deck_id
      WHERE c.card_id=? AND c.status='active' AND d.status='active' ''',
      [id],
    );
    if (rows.isEmpty) return null;
    try {
      final card = LocalDeckRepository.cardFromRow(rows.single);
      card.content.validate();
      return rows.single;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  // Refresh queues inside the transaction so removed/suspended cards are skipped.
  Future<ReviewSnapshot> _load(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      'review_sessions',
      where: 'session_id=?',
      whereArgs: [id],
    );
    if (rows.isEmpty) throw StateError('Không tìm thấy phiên ôn.');
    var session = _session(rows.single);
    CardEntity? current;
    if (session.isActive) {
      final queue = <String>[];
      final learning = <String>[];
      for (final pair in [
        (session.queue, queue),
        (session.learningQueue, learning),
      ]) {
        for (final cardId in pair.$1) {
          final row = await _card(db, cardId);
          if (row != null) {
            pair.$2.add(cardId);
            current ??= LocalDeckRepository.cardFromRow(row);
          }
        }
      }
      final status = queue.isEmpty && learning.isEmpty ? 'completed' : 'active';
      await db.update(
        'review_sessions',
        {
          'queue': jsonEncode(queue),
          'learning_queue': jsonEncode(learning),
          'status': status,
        },
        where: 'session_id=?',
        whereArgs: [id],
      );
      session = ReviewSession(
        id: id,
        deckId: session.deckId,
        dueOnly: session.dueOnly,
        queue: queue,
        learningQueue: learning,
        initialCount: session.initialCount,
        status: status,
      );
    }
    final events = await db.query(
      'review_events',
      where: 'session_id=?',
      whereArgs: [id],
      orderBy: 'sequence',
    );
    return ReviewSnapshot(
      session,
      current,
      List.unmodifiable(
        events.map(
          (r) => ReviewEvent(
            eventId: r['event_id'] as String,
            sessionId: id,
            cardId: r['card_id'] as String,
            deviceId: r['device_id'] as String,
            sequence: r['sequence'] as int,
            reviewedAt: DateTime.fromMillisecondsSinceEpoch(
              r['reviewed_at'] as int,
              isUtc: true,
            ),
            rating: ReviewRating.values.byName(r['rating'] as String),
          ),
        ),
      ),
    );
  }

  @override
  Future<ReviewSnapshot> loadSession(String sessionId) async {
    final db = await _database.database;
    return db.transaction((txn) => _load(txn, sessionId));
  }

  @override
  Future<ReviewSnapshot?> getActiveSession() async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'review_sessions',
        where: "status='active'",
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final snapshot = await _load(txn, rows.single['session_id'] as String);
      return snapshot.session.isActive ? snapshot : null;
    });
  }

  @override
  Future<ReviewSnapshot?> startSession({
    bool dueOnly = true,
    String? deckId,
    String? cardId,
  }) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final active = await txn.query(
        'review_sessions',
        where: "status='active'",
        limit: 1,
      );
      if (active.isNotEmpty) {
        final snapshot = await _load(
          txn,
          active.single['session_id'] as String,
        );
        if (snapshot.session.isActive) return snapshot;
      }
      final now = _clock().toUtc();
      final rows = await txn.rawQuery(
        '''SELECT c.* FROM cards c JOIN decks d ON d.deck_id=c.deck_id
        WHERE c.status='active' AND d.status='active' ${dueOnly ? 'AND c.due_date <= ?' : ''}
        ${deckId != null ? 'AND c.deck_id=?' : ''} ${cardId != null ? 'AND c.card_id=?' : ''}
        ORDER BY c.due_date, c.created_at, c.card_id''',
        [if (dueOnly) now.millisecondsSinceEpoch, ?deckId, ?cardId],
      );
      final ids = <String>[];
      for (final row in rows) {
        if (await _card(txn, row['card_id'] as String) != null) {
          ids.add(row['card_id'] as String);
        }
      }
      if (ids.isEmpty) return null;
      final id = _uuid.v4();
      await txn.insert('review_sessions', {
        'session_id': id,
        'deck_id': deckId,
        'due_only': dueOnly ? 1 : 0,
        'queue': jsonEncode(ids),
        'learning_queue': '[]',
        'initial_count': ids.length,
        'status': 'active',
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      });
      return _load(txn, id);
    });
  }

  @override
  Future<ReviewSnapshot> rate({
    required String sessionId,
    required String cardId,
    required String eventId,
    required DateTime reviewedAt,
    required ReviewRating rating,
  }) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final existing = await txn.query(
        'review_events',
        where: 'event_id=?',
        whereArgs: [eventId],
      );
      if (existing.isNotEmpty) {
        final event = existing.single;
        if (event['session_id'] != sessionId ||
            event['card_id'] != cardId ||
            event['rating'] != rating.name ||
            event['reviewed_at'] != reviewedAt.millisecondsSinceEpoch) {
          throw StateError('Mã đánh giá đã được dùng cho thao tác khác.');
        }
        return _load(txn, sessionId);
      }
      final snapshot = await _load(txn, sessionId);
      final session = snapshot.session;
      if (!session.isActive || session.currentCardId != cardId) {
        throw StateError('Thẻ hiện tại đã thay đổi. Vui lòng tải lại phiên.');
      }
      final row = (await _card(txn, cardId))!;
      final schedule = _scheduler.schedule(
        ScheduleState.fromRow(row, reviewedAt),
        rating,
        reviewedAt,
      );
      await txn.insert('app_settings', {
        'key': 'device_id',
        'value': _uuid.v4(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final device = (await txn.query(
        'app_settings',
        where: 'key=?',
        whereArgs: ['device_id'],
      )).single['value'];
      await txn.insert('review_events', {
        'event_id': eventId,
        'session_id': sessionId,
        'card_id': cardId,
        'device_id': device,
        'reviewed_at': reviewedAt.millisecondsSinceEpoch,
        'rating': rating.name,
      });
      await txn.update(
        'cards',
        {
          'repetitions': schedule.repetitions,
          'interval_days': schedule.intervalDays,
          'ease_factor': schedule.easeFactor,
          'due_date': schedule.nextReviewAt.millisecondsSinceEpoch,
          'updated_at': reviewedAt.millisecondsSinceEpoch,
        },
        where: 'card_id=?',
        whereArgs: [cardId],
      );
      final queue = session.queue.toList();
      final learning = session.learningQueue.toList();
      if (queue.isNotEmpty) {
        queue.removeAt(0);
      } else {
        learning.removeAt(0);
      }
      if (rating == ReviewRating.again) learning.add(cardId);
      await txn.update(
        'review_sessions',
        {
          'queue': jsonEncode(queue),
          'learning_queue': jsonEncode(learning),
          'status': queue.isEmpty && learning.isEmpty ? 'completed' : 'active',
          'updated_at': reviewedAt.millisecondsSinceEpoch,
        },
        where: 'session_id=?',
        whereArgs: [sessionId],
      );
      return _load(txn, sessionId);
    });
  }

  @override
  Future<ReviewSnapshot> endSession(String sessionId) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      await txn.update(
        'review_sessions',
        {'status': 'ended', 'updated_at': _clock().millisecondsSinceEpoch},
        where: "session_id=? AND status='active'",
        whereArgs: [sessionId],
      );
      return _load(txn, sessionId);
    });
  }
}
