import '../../../core/workspace/workspace_context.dart';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/memo_mind_database.dart';
import '../../deck_management/data/local_deck_repository_io.dart';
import '../domain/due_cards_source.dart';
import '../domain/review_models.dart';

class LocalDueCardsSource implements DueCardsSource {
  LocalDueCardsSource({MemoMindDatabase? database})
    : _database = database ?? WorkspaceRuntime.database;
  final MemoMindDatabase _database;

  @override
  Future<bool> hasActiveSession() async =>
      (await (await _database.database).query(
        'review_sessions',
        columns: ['session_id'],
        where: "status='active'",
        limit: 1,
      )).isNotEmpty;

  @override
  Future<List<DueCard>> getDueCards(DateTime at) async =>
      query(await _database.database, at: at);

  static bool isEligible(Map<String, Object?> row) {
    if (!ScheduleState.hasValidStoredSchedule(row)) return false;
    try {
      LocalDeckRepository.cardFromRow(row).content.validate();
      return true;
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  // Also usable inside review transactions, without opening another connection.
  static Future<List<DueCard>> query(
    DatabaseExecutor db, {
    DateTime? at,
    String? deckId,
    String? cardId,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT c.*, d.title AS deck_title FROM cards c
      JOIN decks d ON d.deck_id=c.deck_id
      WHERE c.status='active' AND d.status='active'
      ${at != null ? 'AND c.due_date <= ?' : ''}
      ${deckId != null ? 'AND c.deck_id=?' : ''}
      ${cardId != null ? 'AND c.card_id=?' : ''}
      ORDER BY c.due_date, c.created_at, c.card_id
    ''',
      [if (at != null) at.millisecondsSinceEpoch, ?deckId, ?cardId],
    );
    return rows
        .where(isEligible)
        .map(
          (row) => DueCard(
            LocalDeckRepository.cardFromRow(row),
            row['deck_title'] as String,
          ),
        )
        .toList(growable: false);
  }
}
