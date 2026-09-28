import 'package:uuid/uuid.dart';

import '../../../core/database/memo_mind_database.dart';
import '../../home/domain/home_dashboard_data.dart';
import '../domain/deck_models.dart';
import '../domain/deck_repository.dart';

class LocalDeckRepository implements DeckRepository {
  LocalDeckRepository({
    MemoMindDatabase? database,
    DateTime Function()? clock,
  })  : _database = database ?? MemoMindDatabase.instance,
        _clock = clock ?? DateTime.now;

  final MemoMindDatabase _database;
  final DateTime Function() _clock;
  static const _uuid = Uuid();

  @override
  Future<List<Deck>> getDecks() async {
    final db = await _database.database;
    final rows = await db.query(
      'decks',
      orderBy: 'updated_at DESC',
    );
    return rows.map(_mapDeck).toList();
  }

  @override
  Future<Deck?> getDeckById(String deckId) async {
    final db = await _database.database;
    final rows = await db.query(
      'decks',
      where: 'deck_id = ?',
      whereArgs: [deckId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapDeck(rows.first);
  }

  @override
  Future<Deck> createDeck({
    required String title,
    String? description,
    DeckTone tone = DeckTone.indigo,
  }) async {
    final db = await _database.database;
    final now = _clock();
    final deckId = _uuid.v4();

    await db.insert('decks', {
      'deck_id': deckId,
      'title': title.trim(),
      'description': description?.trim(),
      'tone': tone.name,
      'card_count': 0,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });

    return Deck(
      id: deckId,
      title: title.trim(),
      description: description?.trim(),
      tone: tone,
      cardCount: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<void> saveCardsToDeck({
    required String deckId,
    required List<CardEntity> cards,
  }) async {
    if (cards.isEmpty) return;
    final db = await _database.database;
    final now = _clock().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      for (final card in cards) {
        await txn.insert('cards', {
          'card_id': card.id,
          'deck_id': deckId,
          'type': card.type,
          'format': card.format,
          'question': card.question,
          'answer': card.answer,
          'source_document_id': card.sourceDocumentId,
          'source_page_id': card.sourcePageId,
          'source_page_number': card.sourcePageNumber,
          'source_block_id': card.sourceBlockId,
          'source_quote': card.sourceQuote,
          'confidence': card.confidence,
          'status': card.status.name,
          'repetitions': card.repetitions,
          'interval_days': card.intervalDays,
          'ease_factor': card.easeFactor,
          'due_date': card.dueDate.millisecondsSinceEpoch,
          'created_at': card.createdAt.millisecondsSinceEpoch,
          'updated_at': now,
        });
      }

      // Update card_count in decks
      await txn.rawUpdate('''
        UPDATE decks
        SET card_count = (SELECT COUNT(*) FROM cards WHERE deck_id = ? AND status != 'deleted'),
            updated_at = ?
        WHERE deck_id = ?
      ''', [deckId, now, deckId]);
    });
  }

  @override
  Future<List<CardEntity>> getCardsForDeck(String deckId) async {
    final db = await _database.database;
    final rows = await db.query(
      'cards',
      where: 'deck_id = ? AND status != ?',
      whereArgs: [deckId, 'deleted'],
      orderBy: 'created_at ASC',
    );
    return rows.map(_mapCard).toList();
  }

  Deck _mapDeck(Map<String, dynamic> row) {
    return Deck(
      id: row['deck_id'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      tone: DeckTone.values.firstWhere(
        (t) => t.name == (row['tone'] as String?),
        orElse: () => DeckTone.indigo,
      ),
      cardCount: (row['card_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  CardEntity _mapCard(Map<String, dynamic> row) {
    return CardEntity(
      id: row['card_id'] as String,
      deckId: row['deck_id'] as String,
      type: row['type'] as String? ?? 'flashcard',
      format: row['format'] as String? ?? 'qa',
      question: row['question'] as String,
      answer: row['answer'] as String,
      sourceDocumentId: row['source_document_id'] as String,
      sourcePageId: row['source_page_id'] as String,
      sourcePageNumber: (row['source_page_number'] as num).toInt(),
      sourceBlockId: row['source_block_id'] as String,
      sourceQuote: row['source_quote'] as String,
      confidence: (row['confidence'] as num?)?.toDouble(),
      status: CardStatus.values.firstWhere(
        (s) => s.name == (row['status'] as String?),
        orElse: () => CardStatus.active,
      ),
      repetitions: (row['repetitions'] as num?)?.toInt() ?? 0,
      intervalDays: (row['interval_days'] as num?)?.toInt() ?? 0,
      easeFactor: (row['ease_factor'] as num?)?.toDouble() ?? 2.5,
      dueDate: DateTime.fromMillisecondsSinceEpoch(row['due_date'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }
}
