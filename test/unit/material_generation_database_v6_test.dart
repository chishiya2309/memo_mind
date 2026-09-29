import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:memo_mind/features/deck_management/data/local_deck_repository.dart';
import 'package:memo_mind/features/deck_management/domain/deck_models.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> database() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('PRAGMA foreign_keys = ON');
  await MemoMindDatabase.createV6(db);
  return db;
}

Future<void> seed(Database db) async {
  await db.insert('documents', {
    'document_id': 'doc',
    'title': 'D',
    'status': 'ready_for_generation',
    'privacy': 'private',
    'page_count': 1,
    'created_at': 1,
    'updated_at': 1,
  });
  await db.insert('source_pages', {
    'page_id': 'p',
    'document_id': 'doc',
    'page_number': 1,
    'original_page_number': 1,
    'source': 'camera',
    'data_relative_path': 'p.jpg',
    'mime_type': 'image/jpeg',
    'file_size_bytes': 10,
    'width': 100,
    'height': 100,
    'sha256': 'hash',
    'quality_code': 'good',
    'quality_warning_accepted': 0,
    'created_at': 1,
    'normalization_status': 'source_ready',
  });
  await db.insert('source_blocks', {
    'block_id': 'b',
    'document_id': 'doc',
    'page_id': 'p',
    'page_number': 1,
    'order_index': 0,
    'raw_text': 'Văn bản',
    'normalized_text': 'Văn bản chuẩn có đáp án',
    'confidence_source': 'mlkit',
    'status': 'verified',
    'created_at': 1,
    'updated_at': 1,
  });
}

CardEntity card(
  String id,
  CardType type, {
  String quote = 'Văn bản chuẩn',
  String document = 'doc',
  String page = 'p',
  int pageNumber = 1,
}) {
  final options = type == CardType.mcq
      ? const [
          McqOption(optionId: 'A', text: 'Đúng'),
          McqOption(optionId: 'B', text: 'Sai'),
          McqOption(optionId: 'C', text: 'Có thể'),
          McqOption(optionId: 'D', text: 'Không'),
        ]
      : const <McqOption>[];
  return CardEntity(
    id: id,
    deckId: 'd',
    type: type,
    front: type == CardType.cloze ? 'Đáp án là [...]' : 'Câu hỏi $id',
    back: type == CardType.mcq ? 'Đúng' : 'Đáp án',
    options: options,
    correctOptionId: type == CardType.mcq ? 'A' : null,
    explanation: type == CardType.mcq ? 'Giải thích nguồn.' : null,
    sourceDocumentId: document,
    sourcePageId: page,
    sourcePageNumber: pageNumber,
    sourceBlockId: 'b',
    sourceQuote: quote,
    dueDate: DateTime.fromMillisecondsSinceEpoch(2),
    createdAt: DateTime.fromMillisecondsSinceEpoch(2),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
  );
}

void main() {
  setUpAll(sqfliteFfiInit);
  test(
    'v6 persists all types and MCQ answer/payload with source metadata',
    () async {
      final db = await database();
      addTearDown(db.close);
      await seed(db);
      final repo = LocalDeckRepository(
        database: MemoMindDatabase.forTesting(db),
      );
      final deck = await repo.createDeck(title: 'D');
      await repo.saveCardsToDeck(
        deckId: deck.id,
        cards: [
          card('basic', CardType.basic).copyWith(deckId: deck.id),
          card('cloze', CardType.cloze).copyWith(deckId: deck.id),
          card('mcq', CardType.mcq).copyWith(deckId: deck.id),
        ],
      );
      final saved = await repo.getCardsForDeck(deck.id);
      expect(saved.map((c) => c.type), [
        CardType.basic,
        CardType.cloze,
        CardType.mcq,
      ]);
      expect(saved.last.back, 'Đúng');
      expect(saved.last.correctOptionId, 'A');
      expect(
        jsonDecode(
          (await db.query(
                'cards',
                where: 'card_id = ?',
                whereArgs: ['mcq'],
              )).single['mcq_payload']
              as String,
        )['options'],
        hasLength(4),
      );
      expect((await repo.getDeckById(deck.id))?.cardCount, 3);
    },
  );
  test('failure on second insert rolls back cards and deck count', () async {
    final db = await database();
    addTearDown(db.close);
    await seed(db);
    final repo = LocalDeckRepository(database: MemoMindDatabase.forTesting(db));
    final deck = await repo.createDeck(title: 'D');
    await db.execute("""CREATE TRIGGER fail_second BEFORE INSERT ON cards WHEN NEW.card_id = 'bad'
      BEGIN SELECT RAISE(ABORT, 'injected insert failure'); END""");
    await expectLater(
      repo.saveCardsToDeck(
        deckId: deck.id,
        cards: [
          card('good', CardType.basic).copyWith(deckId: deck.id),
          card('bad', CardType.mcq).copyWith(deckId: deck.id),
        ],
      ),
      throwsA(anything),
    );
    expect(await repo.getCardsForDeck(deck.id), isEmpty);
    expect((await repo.getDeckById(deck.id))?.cardCount, 0);
  });
  test('revalidates source quote, page, document and verified status inside transaction', () async {
    final db = await database();
    addTearDown(db.close);
    await seed(db);
    final repo = LocalDeckRepository(database: MemoMindDatabase.forTesting(db));
    final deck = await repo.createDeck(title: 'D');
    for (final invalid in [
      card('quote', CardType.basic, quote: 'not in source'),
      card('document', CardType.basic, document: 'other'),
      card('page', CardType.basic, pageNumber: 2),
    ]) {
      await expectLater(
        repo.saveCardsToDeck(
          deckId: deck.id,
          cards: [invalid.copyWith(deckId: deck.id)],
        ),
        throwsA(isA<Exception>()),
      );
      expect(await repo.getCardsForDeck(deck.id), isEmpty);
    }
    await db.update(
      'source_blocks',
      {'status': 'deleted'},
      where: 'block_id = ?',
      whereArgs: ['b'],
    );
    await expectLater(
      repo.saveCardsToDeck(
        deckId: deck.id,
        cards: [card('deleted', CardType.basic).copyWith(deckId: deck.id)],
      ),
      throwsA(isA<Exception>()),
    );
    expect((await repo.getDeckById(deck.id))?.cardCount, 0);
  });
}
