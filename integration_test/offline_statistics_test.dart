import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:memo_mind/features/deck_management/data/local_deck_repository.dart';
import 'package:memo_mind/features/deck_management/domain/deck_models.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/review/data/local_review_repository.dart';
import 'package:memo_mind/features/review/domain/review_models.dart';
import 'package:memo_mind/features/statistics/application/statistics_controller.dart';
import 'package:memo_mind/features/statistics/data/local_statistics_repository.dart';
import 'package:memo_mind/features/statistics/presentation/statistics_screen.dart';
import 'package:memo_mind/shared/theme/memo_theme.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'FR17 offline committed partial session, deletion and native reopen',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'memo_statistics_native_',
      );
      final path = p.join(directory.path, 'statistics.db');
      Database? db;
      StatisticsController? controller;
      final now = DateTime.utc(2026, 10, 2, 8);
      try {
        db = await openDatabase(
          path,
          version: 8,
          onConfigure: (d) => d.execute('PRAGMA foreign_keys=ON'),
          onCreate: (d, _) => MemoMindDatabase.createV8(d),
        );
        var store = MemoMindDatabase.forTesting(db);
        final decks = LocalDeckRepository(database: store, clock: () => now);
        final review = LocalReviewRepository(database: store, clock: () => now);
        final deck = await decks.createDeck(title: 'Offline FR17');
        final card = await decks.createManualCard(
          deckId: deck.id,
          content: const CardContent(
            type: CardType.basic,
            front: 'Q',
            back: 'A',
          ),
        );
        final statistics = LocalStatisticsRepository(
          database: store,
          clock: () => now,
          timeZone: () async => 'Asia/Ho_Chi_Minh',
        );
        controller = StatisticsController(
          repository: statistics,
          studyChanges: store.studyChanges,
          clock: () => now,
          timeZone: () async => 'Asia/Ho_Chi_Minh',
        );
        controller.setVisible(true);
        await controller.refresh();
        expect(controller.snapshot!.dueCardCount, 1);
        final session = (await review.startSession())!;
        await review.rate(
          sessionId: session.session.id,
          cardId: card.id,
          eventId: 'again',
          reviewedAt: now,
          rating: ReviewRating.again,
        );
        await controller.refresh();
        expect(controller.snapshot!.reviewCountToday, 1);
        expect(controller.snapshot!.successRateToday, 0);
        expect((await review.getActiveSession())!.session.isActive, true);
        await review.rate(
          sessionId: session.session.id,
          cardId: card.id,
          eventId: 'good',
          reviewedAt: now,
          rating: ReviewRating.good,
        );
        await controller.refresh();
        await tester.pumpWidget(
          MaterialApp(
            theme: MemoTheme.light,
            home: Scaffold(
              body: StatisticsScreen(
                controller: controller,
                onOpenDueCards: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('50,0%'), findsOneWidget);
        expect(find.text('Theo tự đánh giá\n1/2 lượt đạt'), findsOneWidget);
        await decks.deleteCard(card.id);
        await decks.deleteDeck(deck.id);
        await controller.refresh();
        expect(controller.snapshot!.reviewCountToday, 2);
        expect(controller.snapshot!.dueCardCount, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        controller = null;
        await db.close();
        db = await openDatabase(path, version: 8);
        store = MemoMindDatabase.forTesting(db);
        final restored = await LocalStatisticsRepository(
          database: store,
          clock: () => now,
          timeZone: () async => 'Asia/Ho_Chi_Minh',
        ).loadSnapshot();
        expect(restored.reviewCountToday, 2);
        expect(restored.successRateToday, 50);
        expect(restored.currentStreakDays, 1);
        expect(restored.dueCardCount, 0);
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller?.dispose();
        await db?.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
