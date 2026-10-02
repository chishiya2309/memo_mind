import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:memo_mind/features/deck_management/data/local_deck_repository.dart';
import 'package:memo_mind/features/deck_management/domain/deck_models.dart';
import 'package:memo_mind/features/deck_management/presentation/deck_detail_screen.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/review/data/local_review_repository.dart';
import 'package:memo_mind/features/review/domain/review_models.dart';
import 'package:memo_mind/shared/theme/memo_theme.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native offline CRUD, all card types, Again resume and durable history',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'memo_native_review_',
      );
      final path = p.join(directory.path, 'review.db');
      Database? db;
      try {
        db = await openDatabase(
          path,
          version: 8,
          onConfigure: (d) => d.execute('PRAGMA foreign_keys=ON'),
          onCreate: (d, version) => MemoMindDatabase.createV8(d),
        );
        final clock = DateTime.utc(2026, 10, 2, 8);
        var store = MemoMindDatabase.forTesting(db);
        var decks = LocalDeckRepository(database: store, clock: () => clock);
        var review = LocalReviewRepository(database: store, clock: () => clock);
        final deck = await decks.createDeck(
          title: 'Ngoại tuyến',
          tags: ['Android'],
        );
        for (final type in CardType.values) {
          await decks.createManualCard(
            deckId: deck.id,
            content: CardContent(
              type: type,
              front: type == CardType.cloze ? 'Câu [...]' : 'Câu hỏi',
              back: 'Đáp án',
              tags: ['local'],
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
            ),
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: MemoTheme.light,
            home: DeckDetailScreen(
              deckId: deck.id,
              repository: decks,
              reviewRepository: review,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('3 thẻ'), findsOneWidget);
        await tester.tap(find.byKey(const Key('review-deck')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Lật thẻ'));
        await tester.tap(find.text('Lật thẻ'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Again'));
        await tester.tap(find.text('Again'));
        await tester.pumpAndSettle();
        final active = (await review.getActiveSession())!;
        expect(active.events.length, 1);
        expect(active.session.learningQueue.length, 1);
        final due = (await db.query(
          'cards',
          where: 'card_id=?',
          whereArgs: [active.events.single.cardId],
        )).single['due_date'];
        expect(
          due,
          active.events.single.reviewedAt
              .add(const Duration(days: 1))
              .millisecondsSinceEpoch,
        );
        // Unmount before closing native SQLite to simulate recreation safely.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await db.close();
        db = await openDatabase(path, version: 8);
        store = MemoMindDatabase.forTesting(db);
        decks = LocalDeckRepository(database: store, clock: () => clock);
        review = LocalReviewRepository(database: store, clock: () => clock);
        var resumed = (await review.getActiveSession())!;
        expect(resumed.session.id, active.session.id);
        expect(resumed.events.single.deviceId, active.events.single.deviceId);
        while (resumed.session.isActive) {
          resumed = await review.rate(
            sessionId: resumed.session.id,
            cardId: resumed.card!.id,
            eventId: 'native-${resumed.events.length}',
            reviewedAt: clock,
            rating: ReviewRating.good,
          );
        }
        expect(resumed.reviewedCards, 3);
        expect(resumed.events.length, 4);
        final before = (await decks.getCardsForDeck(deck.id)).first;
        await decks.updateCard(
          before.id,
          content: CardContent(
            type: before.type,
            front: before.type == CardType.cloze ? 'Đã sửa [...]' : 'Đã sửa',
            back: before.back,
            options: before.options,
            correctOptionId: before.correctOptionId,
            explanation: before.explanation,
            tags: ['edited'],
          ),
        );
        expect(
          (await decks.getCardsForDeck(deck.id)).first.repetitions,
          before.repetitions,
        );
        await decks.deleteDeck(deck.id);
        expect(await decks.getDecks(), isEmpty);
        expect(
          await review.startSession(deckId: deck.id, dueOnly: false),
          isNull,
        );
        expect((await db.query('review_events')).length, 4);
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await db?.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
