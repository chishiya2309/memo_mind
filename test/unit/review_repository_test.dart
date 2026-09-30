import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:memo_mind/features/deck_management/data/local_deck_repository.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/review/data/local_review_repository.dart';
import 'package:memo_mind/features/review/domain/review_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'material_generation_database_v6_test.dart' as fixture;

final reviewNow = DateTime.utc(2026, 9, 30, 8);

Future<Database> reviewDatabase({int count = 2, String? path}) async {
  final db = await databaseFactoryFfi.openDatabase(
    path ?? inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await db.execute('PRAGMA foreign_keys = ON');
  await MemoMindDatabase.createV6(db);
  await fixture.seed(db);
  final decks = LocalDeckRepository(
    database: MemoMindDatabase.forTesting(db),
    clock: () => reviewNow,
  );
  final deck = await decks.createDeck(title: 'Bộ thẻ thật');
  await decks.saveCardsToDeck(
    deckId: deck.id,
    cards: [
      for (var i = 0; i < count; i++)
        fixture.card('c$i', CardType.basic).copyWith(deckId: deck.id),
    ],
  );
  await MemoMindDatabase.migrateV6ToV7(db);
  return db;
}

void main() {
  setUpAll(sqfliteFfiInit);
  late Database db;
  late LocalReviewRepository repo;
  setUp(() async {
    db = await reviewDatabase();
    repo = LocalReviewRepository(
      database: MemoMindDatabase.forTesting(db),
      clock: () => reviewNow,
    );
  });
  tearDown(() async => db.close());

  test(
    'migration keeps cards and schedule; fresh v7 has the same review tables',
    () async {
      final cards = await db.query('cards');
      expect(cards.length, 2);
      expect(cards.first['ease_factor'], 2.5);
      expect(cards.first['due_date'], 2);
      final fresh = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        await MemoMindDatabase.createV7(fresh);
        expect(await fresh.query('review_events'), isEmpty);
        expect(await fresh.query('review_sessions'), isEmpty);
      } finally {
        await fresh.close();
      }
    },
  );

  test('due query excludes future, suspended, deleted; free mode includes future active', () async {
    await db.update('cards', {
      'due_date': reviewNow.add(const Duration(days: 1)).millisecondsSinceEpoch,
    }, where: "card_id='c0'");
    await db.update('cards', {'status': 'suspended'}, where: "card_id='c1'");
    expect(await repo.startSession(), isNull);
    expect(await db.query('review_sessions'), isEmpty);
    final free = (await repo.startSession(dueOnly: false))!;
    expect(free.session.queue, ['c0']);
    await repo.endSession(free.session.id);
    await db.update('cards', {'status': 'deleted'}, where: "card_id='c0'");
    expect(await repo.startSession(dueOnly: false), isNull);
  });

  test('Again queues at end; long term due stays one day; history and device ID persist', () async {
    var state = (await repo.startSession())!;
    final id = state.session.id;
    state = await repo.rate(
      sessionId: id,
      cardId: 'c0',
      eventId: 'e1',
      reviewedAt: reviewNow,
      rating: ReviewRating.again,
    );
    expect(state.session.queue, ['c1']);
    expect(state.session.learningQueue, ['c0']);
    expect((await repo.getDashboard()).hasActiveReviewSession, isTrue);
    final row = (await db.query('cards', where: "card_id='c0'")).single;
    expect(
      row['due_date'],
      reviewNow.add(const Duration(days: 1)).millisecondsSinceEpoch,
    );
    expect(row['repetitions'], 0);
    final reopened = LocalReviewRepository(
      database: MemoMindDatabase.forTesting(db),
      clock: () => reviewNow,
    );
    expect((await reopened.getActiveSession())!.card!.id, 'c1');
    state = await reopened.rate(
      sessionId: id,
      cardId: 'c1',
      eventId: 'e2',
      reviewedAt: reviewNow,
      rating: ReviewRating.good,
    );
    expect(state.card!.id, 'c0');
    state = await reopened.rate(
      sessionId: id,
      cardId: 'c0',
      eventId: 'e3',
      reviewedAt: reviewNow,
      rating: ReviewRating.good,
    );
    expect(state.session.status, 'completed');
    expect(state.events.length, 3);
    expect(state.reviewedCards, 2);
    expect(state.events.map((e) => e.deviceId).toSet().length, 1);
    expect(state.events.map((e) => e.sequence), [1, 2, 3]);
    final home = await repo.getDashboard();
    expect(home.review.reviewedToday, 2);
    expect(home.review.remaining, 0);
    expect(home.hasActiveReviewSession, isFalse);
    expect(home.recentDecks.single.learnedPercent, 100);
  });

  test(
    'same event retry is idempotent; mismatched payload is rejected',
    () async {
      final state = (await repo.startSession())!;
      Future<ReviewSnapshot> submit() => repo.rate(
        sessionId: state.session.id,
        cardId: 'c0',
        eventId: 'same',
        reviewedAt: reviewNow,
        rating: ReviewRating.good,
      );
      await submit();
      await submit();
      expect((await db.query('review_events')).length, 1);
      expect(
        (await db.query('cards', where: "card_id='c0'")).single['repetitions'],
        1,
      );
      await expectLater(
        repo.rate(
          sessionId: state.session.id,
          cardId: 'c0',
          eventId: 'same',
          reviewedAt: reviewNow,
          rating: ReviewRating.easy,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'failure on schedule or session write rolls back event, schedule and queue',
    () async {
      final state = (await repo.startSession())!;
      for (final table in ['cards', 'review_sessions']) {
        // For session writes, fail only after the card schedule was updated.
        await db.execute('''CREATE TRIGGER fail_save BEFORE UPDATE ON $table
        WHEN EXISTS(SELECT 1 FROM review_events)
        BEGIN SELECT RAISE(ABORT, 'injected storage failure'); END''');
        await expectLater(
          repo.rate(
            sessionId: state.session.id,
            cardId: 'c0',
            eventId: 'retry',
            reviewedAt: reviewNow,
            rating: ReviewRating.good,
          ),
          throwsA(isA<DatabaseException>()),
        );
        expect(await db.query('review_events'), isEmpty);
        expect(
          (await db.query(
            'cards',
            where: "card_id='c0'",
          )).single['repetitions'],
          0,
        );
        expect((await repo.loadSession(state.session.id)).card!.id, 'c0');
        await db.execute('DROP TRIGGER fail_save');
      }
      await repo.rate(
        sessionId: state.session.id,
        cardId: 'c0',
        eventId: 'retry',
        reviewedAt: reviewNow,
        rating: ReviewRating.good,
      );
      expect((await db.query('review_events')).length, 1);
    },
  );

  test(
    'resume skips deleted cards and ending does not count an unreviewed card',
    () async {
      final state = (await repo.startSession())!;
      await db.delete('cards', where: "card_id='c0'");
      final resumed = (await repo.getActiveSession())!;
      expect(resumed.card!.id, 'c1');
      final ended = await repo.endSession(state.session.id);
      expect(ended.reviewedCards, 0);
      expect(ended.session.status, 'ended');
      expect(await repo.getActiveSession(), isNull);
    },
  );

  test(
    'scope supports deck and single card; due boundary is inclusive',
    () async {
      final deck = (await repo.getDecks()).single;
      await db.update('cards', {'due_date': reviewNow.millisecondsSinceEpoch});
      expect(await repo.startSession(deckId: 'missing'), isNull);
      final state = (await repo.startSession(deckId: deck.id, cardId: 'c1'))!;
      expect(state.session.queue, ['c1']);
      expect((await repo.startSession())!.session.id, state.session.id);
    },
  );

  test(
    'closing and reopening file database preserves events, queue and device ID',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'memomind_review_test_',
      );
      final path = '${directory.path}/review.db';
      final disk = await reviewDatabase(path: path);
      final original = LocalReviewRepository(
        database: MemoMindDatabase.forTesting(disk),
        clock: () => reviewNow,
      );
      final initial = (await original.startSession())!;
      final saved = await original.rate(
        sessionId: initial.session.id,
        cardId: 'c0',
        eventId: 'disk-event',
        reviewedAt: reviewNow,
        rating: ReviewRating.again,
      );
      await disk.close();
      final reopened = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        final restored = LocalReviewRepository(
          database: MemoMindDatabase.forTesting(reopened),
          clock: () => reviewNow,
        );
        final state = (await restored.getActiveSession())!;
        expect(state.session.id, initial.session.id);
        expect(state.card!.id, 'c1');
        expect(state.session.learningQueue, ['c0']);
        expect(state.events.single.deviceId, saved.events.single.deviceId);
        expect(state.events.single.eventId, 'disk-event');
        expect(
          (await reopened.query(
            'cards',
            where: "card_id='c0'",
          )).single['due_date'],
          reviewNow.add(const Duration(days: 1)).millisecondsSinceEpoch,
        );
      } finally {
        await reopened.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
