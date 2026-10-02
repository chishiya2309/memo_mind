import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:memo_mind/features/deck_management/data/local_deck_repository.dart';
import 'package:memo_mind/features/deck_management/domain/deck_models.dart';
import 'package:memo_mind/features/deck_management/application/get_card_source_trace_use_case.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/review/data/local_review_repository.dart';
import 'package:memo_mind/features/review/domain/review_models.dart';
import 'package:memo_mind/features/ocr_editor/domain/ocr_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'material_generation_database_v6_test.dart' as fixture;

final now = DateTime.utc(2026, 10, 2, 8);
CardContent content(
  CardType type, {
  String front = 'Câu hỏi',
  List<String> tags = const [],
}) => CardContent(
  type: type,
  front: type == CardType.cloze ? 'Câu [...]' : front,
  back: 'Đáp án',
  tags: tags,
  options: type == CardType.mcq
      ? const [
          McqOption(optionId: 'A', text: 'Đúng'),
          McqOption(optionId: 'B', text: 'Sai'),
          McqOption(optionId: 'C', text: 'Có thể'),
          McqOption(optionId: 'D', text: 'Không'),
        ]
      : const [],
  correctOptionId: type == CardType.mcq ? 'A' : null,
  explanation: type == CardType.mcq ? 'Giải thích' : null,
);

class TraceRepository extends LocalDeckRepository {
  TraceRepository(this.trace);
  final CardSourceTrace trace;
  @override
  Future<CardSourceTrace> getCardSourceTrace(CardEntity card) async => trace;
}

void main() {
  setUpAll(sqfliteFfiInit);
  late Database db;
  late LocalDeckRepository decks;
  late LocalReviewRepository review;
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('memo_decks_');
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('PRAGMA foreign_keys=ON');
    await MemoMindDatabase.createV8(db);
    final store = MemoMindDatabase.forTesting(db);
    decks = LocalDeckRepository(
      database: store,
      clock: () => now,
      supportDirectory: () async => directory,
    );
    review = LocalReviewRepository(database: store, clock: () => now);
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test('deck names, tags, description and tone persist correctly', () async {
    await expectLater(decks.createDeck(title: '  '), throwsFormatException);
    final d = await decks.createDeck(
      title: ' Tên ',
      description: 'Giữ mô tả',
      tags: [' A ', 'a', '', 'B'],
    );
    expect(d.tags, ['A', 'B']);
    final saved = await decks.updateDeck(d.id, title: 'Đổi tên', tags: [' C ']);
    expect(saved.description, 'Giữ mô tả');
    expect(saved.tags, ['C']);
    await expectLater(
      decks.updateDeck(d.id, title: '\t'),
      throwsFormatException,
    );
    expect((await decks.getDeckById(d.id))!.title, 'Đổi tên');
  });

  for (final type in CardType.values) {
    test('manual $type is immediately due without a source', () async {
      final d = await decks.createDeck(title: 'Deck');
      final c = await decks.createManualCard(
        deckId: d.id,
        content: content(type, tags: [' T ', 't']),
      );
      expect(c.hasSource, false);
      expect(c.sourceDocumentId, isNull);
      expect(c.tags, ['T']);
      expect(c.easeFactor, 2.5);
      expect(c.dueDate.toUtc(), now);
      expect((await decks.getDeckById(d.id))!.cardCount, 1);
      final session = (await review.startSession(deckId: d.id))!;
      expect(session.card!.id, c.id);
      expect(session.card!.back, type == CardType.mcq ? 'Đúng' : 'Đáp án');
    });
  }

  test(
    'content validation and immutable type prevent invalid writes',
    () async {
      final d = await decks.createDeck(title: 'Deck');
      await expectLater(
        decks.createManualCard(
          deckId: d.id,
          content: const CardContent(
            type: CardType.cloze,
            front: 'No blank',
            back: 'Answer',
          ),
        ),
        throwsFormatException,
      );
      final c = await decks.createManualCard(
        deckId: d.id,
        content: content(CardType.basic),
      );
      await expectLater(
        decks.updateCard(c.id, content: content(CardType.mcq)),
        throwsFormatException,
      );
      expect((await decks.getCardsForDeck(d.id)).length, 1);
    },
  );

  test(
    'editing a reviewed sourced card preserves source, schedule and history',
    () async {
      await fixture.seed(db);
      final d = await decks.createDeck(title: 'Deck');
      await decks.saveCardsToDeck(
        deckId: d.id,
        cards: [fixture.card('c', CardType.basic).copyWith(deckId: d.id)],
      );
      final s = (await review.startSession(deckId: d.id))!;
      await review.rate(
        sessionId: s.session.id,
        cardId: 'c',
        eventId: 'event',
        reviewedAt: now,
        rating: ReviewRating.good,
      );
      final before = (await db.query('cards')).single;
      await decks.updateCard(
        'c',
        content: content(CardType.basic, front: 'Đã sửa', tags: ['nhãn']),
      );
      final after = (await db.query('cards')).single;
      for (final key in [
        'source_document_id',
        'source_page_id',
        'source_page_number',
        'source_block_id',
        'source_quote',
        'repetitions',
        'interval_days',
        'ease_factor',
        'due_date',
        'created_at',
      ]) {
        expect(after[key], before[key], reason: key);
      }
      expect(after['front'], 'Đã sửa');
      expect((await db.query('review_events')).length, 1);
    },
  );

  test(
    'soft deletion skips active queues and keeps history and shared source',
    () async {
      await fixture.seed(db);
      final d = await decks.createDeck(title: 'Deck');
      final other = await decks.createDeck(title: 'Khác');
      await decks.saveCardsToDeck(
        deckId: d.id,
        cards: [fixture.card('c', CardType.basic).copyWith(deckId: d.id)],
      );
      await decks.saveCardsToDeck(
        deckId: other.id,
        cards: [
          fixture.card('shared', CardType.basic).copyWith(deckId: other.id),
        ],
      );
      final s = (await review.startSession(deckId: d.id))!;
      await review.rate(
        sessionId: s.session.id,
        cardId: 'c',
        eventId: 'again',
        reviewedAt: now,
        rating: ReviewRating.again,
      );
      await decks.deleteDeck(d.id);
      expect(await review.getActiveSession(), isNull);
      expect(await review.startSession(deckId: d.id, dueOnly: false), isNull);
      expect((await review.getDecks()).map((d) => d.id), [other.id]);
      expect((await review.getDashboard()).totalDeckCount, 1);
      expect(await decks.getCardsForDeck(d.id), isEmpty);
      expect(
        (await db.query('cards', where: "card_id='c'")).single['status'],
        'deleted',
      );
      expect((await db.query('review_events')).length, 1);
      expect((await db.query('source_blocks')).length, 1);
      await decks.deleteCard('shared');
      expect((await decks.getDeckById(other.id))!.cardCount, 0);
    },
  );

  test('failed deck deletion rolls back deck and cards', () async {
    final d = await decks.createDeck(title: 'Deck');
    await decks.createManualCard(
      deckId: d.id,
      content: content(CardType.basic),
    );
    await db.execute(
      "CREATE TRIGGER fail_delete BEFORE UPDATE ON cards BEGIN SELECT RAISE(ABORT, 'failed'); END",
    );
    await expectLater(
      decks.deleteDeck(d.id),
      throwsA(isA<DatabaseException>()),
    );
    expect(await decks.getDeckById(d.id), isNotNull);
    expect((await decks.getCardsForDeck(d.id)).length, 1);
  });

  test('source loss keeps saved quote, page number and card', () async {
    await fixture.seed(db);
    final d = await decks.createDeck(title: 'Deck');
    await decks.saveCardsToDeck(
      deckId: d.id,
      cards: [fixture.card('c', CardType.basic).copyWith(deckId: d.id)],
    );
    await db.delete('documents', where: "document_id='doc'");
    final c = (await decks.getCardsForDeck(d.id)).single;
    final trace = await GetCardSourceTraceUseCase(deckRepository: decks)
        .execute(c);
    expect(trace.sourcePage, isNull);
    expect(trace.sourceBlock, isNull);
    expect(trace.sourceQuote, c.sourceQuote);
    expect(trace.sourcePageNumber, 1);
    expect(trace.warning, isNotNull);
  });
  test('source boxes reject non-finite, out-of-range, zero area and wrong image coordinates', () async {
    await fixture.seed(db);
    final d = await decks.createDeck(title: 'Deck');
    await decks.saveCardsToDeck(
      deckId: d.id,
      cards: [fixture.card('c', CardType.basic).copyWith(deckId: d.id)],
    );
    final c = (await decks.getCardsForDeck(d.id)).single;
    final base = await decks.getCardSourceTrace(c);
    const valid = NormalizedBoundingBox(
      left: .1,
      top: .1,
      width: .3,
      height: .3,
    );
    for (final box in [
      valid,
      const NormalizedBoundingBox(left: -.1, top: 0, width: .2, height: .2),
      const NormalizedBoundingBox(left: .9, top: 0, width: .2, height: .2),
      const NormalizedBoundingBox(left: 0, top: 0, width: 0, height: .2),
      const NormalizedBoundingBox(
        left: double.nan,
        top: 0,
        width: .2,
        height: .2,
      ),
    ]) {
      final trace = await GetCardSourceTraceUseCase(
        deckRepository: TraceRepository(
          CardSourceTrace(
            documentTitle: base.documentTitle,
            sourceQuote: c.sourceQuote,
            sourcePage: base.sourcePage,
            sourceBlock: base.sourceBlock!.copyWith(
              boundingBox: box,
              hasValidBox: true,
            ),
            imageFile: File('fixture'),
            imageUsesNormalizedCoordinates: true,
          ),
        ),
      ).execute(c);
      expect(trace.sourceBlock!.hasValidBox, box == valid);
    }
    final rawFallback = await GetCardSourceTraceUseCase(
      deckRepository: TraceRepository(
        CardSourceTrace(
          documentTitle: '',
          sourceQuote: c.sourceQuote,
          sourcePage: base.sourcePage,
          sourceBlock: base.sourceBlock!.copyWith(
            boundingBox: valid,
            hasValidBox: true,
          ),
          imageFile: File('raw'),
          imageUsesNormalizedCoordinates: false,
        ),
      ),
    ).execute(c);
    expect(rawFallback.sourceBlock!.hasValidBox, false);
    final mismatch = await GetCardSourceTraceUseCase(
      deckRepository: TraceRepository(
        CardSourceTrace(
          documentTitle: '',
          sourceQuote: c.sourceQuote,
          sourcePage: base.sourcePage,
          sourceBlock: base.sourceBlock!.copyWith(pageNumber: 2),
          imageFile: File('fixture'),
          imageUsesNormalizedCoordinates: true,
        ),
      ),
    ).execute(c);
    expect(mismatch.sourceBlock, isNull);
    expect(mismatch.sourceQuote, c.sourceQuote);
  });
}
