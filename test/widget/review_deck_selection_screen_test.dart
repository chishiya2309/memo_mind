import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/review/domain/review_models.dart';
import 'package:memo_mind/features/review/presentation/review_deck_selection_screen.dart';
import 'package:memo_mind/features/review/presentation/review_session_screen.dart';

import '../unit/material_generation_database_v6_test.dart' as fixture;
import 'review_session_screen_test.dart' show ScreenRepository, tapText;

class DeckScreenRepository extends ScreenRepository {
  DeckScreenRepository() : super(fixture.card('c', CardType.basic));
  int deckLoads = 0;
  bool failNextLoad = false;
  bool noDueCards = false;

  @override
  Future<ReviewSnapshot?> startSession({
    bool dueOnly = true,
    String? deckId,
    String? cardId,
  }) async {
    if (dueOnly && noDueCards) return null;
    return super.startSession(dueOnly: dueOnly, deckId: deckId, cardId: cardId);
  }

  @override
  Future<List<ReviewDeck>> getDecks() async {
    deckLoads++;
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('Cannot read decks');
    }
    return [
      ReviewDeck(
        id: 'd',
        title: 'Bộ thẻ kiểm thử',
        activeCount: 1,
        dueCount: noDueCards || saved?.events.isNotEmpty == true ? 0 : 1,
      ),
    ];
  }
}

void main() {
  testWidgets('empty due session waits for free review before notifying Home', (
    tester,
  ) async {
    final repository = DeckScreenRepository()..noDueCards = true;
    var returnedToHome = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReviewSessionScreen(repository: repository),
                  ),
                );
                returnedToHome++;
              },
              child: const Text('Ôn đến hạn'),
            ),
          ),
        ),
      ),
    );
    await tapText(tester, 'Ôn đến hạn');
    await tapText(tester, 'Ôn tự do');
    expect(returnedToHome, 0);
    await tapText(tester, 'Bộ thẻ kiểm thử');
    await tapText(tester, 'Lật thẻ');
    await tapText(tester, 'Good');
    await tapText(tester, 'Hoàn tất');
    expect(returnedToHome, 0);
    expect(find.text('1 thẻ • 0 đến hạn'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(returnedToHome, 1);
    expect(find.text('Ôn đến hạn'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switching from due decks to free review keeps caller waiting until returning',
    (tester) async {
      final repository = DeckScreenRepository()..noDueCards = true;
      var returnedToHome = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReviewDeckSelectionScreen(
                        repository: repository,
                        dueOnly: true,
                      ),
                    ),
                  );
                  returnedToHome++;
                },
                child: const Text('Mở danh sách đến hạn'),
              ),
            ),
          ),
        ),
      );
      await tapText(tester, 'Mở danh sách đến hạn');
      await tapText(tester, 'Ôn tự do');
      expect(returnedToHome, 0);
      expect(find.text('Bộ thẻ kiểm thử'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(returnedToHome, 1);
    },
  );

  testWidgets(
    'retry after deck load failure refreshes without returning a Future from setState',
    (tester) async {
      final repository = DeckScreenRepository()..failNextLoad = true;
      await tester.pumpWidget(
        MaterialApp(home: ReviewDeckSelectionScreen(repository: repository)),
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Không thể tải bộ thẻ. Thử lại');
      expect(tester.takeException(), isNull);
      expect(find.text('Bộ thẻ kiểm thử'), findsOneWidget);
      expect(repository.deckLoads, 2);
    },
  );

  testWidgets('pause returns to deck list and reopens the unfinished session', (
    tester,
  ) async {
    final repository = DeckScreenRepository();
    await tester.pumpWidget(
      MaterialApp(home: ReviewDeckSelectionScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tapText(tester, 'Bộ thẻ kiểm thử');
    await tapText(tester, 'Tạm dừng');
    expect(tester.takeException(), isNull);
    expect(repository.deckLoads, 2);
    await tapText(tester, 'Bộ thẻ kiểm thử');
    expect(find.text('Bạn có phiên ôn đang dở'), findsOneWidget);
    await tapText(tester, 'Tiếp tục phiên');
    expect(find.text('Lật thẻ'), findsOneWidget);
    expect(repository.calls, 0);
  });

  testWidgets(
    'completion refreshes the due count when returning to deck list',
    (tester) async {
      final repository = DeckScreenRepository();
      await tester.pumpWidget(
        MaterialApp(home: ReviewDeckSelectionScreen(repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 thẻ • 1 đến hạn'), findsOneWidget);
      await tapText(tester, 'Bộ thẻ kiểm thử');
      await tapText(tester, 'Lật thẻ');
      await tapText(tester, 'Good');
      await tapText(tester, 'Hoàn tất');
      expect(tester.takeException(), isNull);
      expect(find.text('1 thẻ • 0 đến hạn'), findsOneWidget);
      expect(repository.deckLoads, 2);
    },
  );

  testWidgets('refresh failure after returning can be retried', (tester) async {
    final repository = DeckScreenRepository();
    await tester.pumpWidget(
      MaterialApp(home: ReviewDeckSelectionScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tapText(tester, 'Bộ thẻ kiểm thử');
    repository.failNextLoad = true;
    await tapText(tester, 'Tạm dừng');
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Không thể tải bộ thẻ. Thử lại');
    expect(tester.takeException(), isNull);
    expect(find.text('Bộ thẻ kiểm thử'), findsOneWidget);
    expect(repository.deckLoads, 3);
  });
}
