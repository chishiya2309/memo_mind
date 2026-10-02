import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/deck_management/domain/deck_models.dart';
import 'package:memo_mind/features/home/domain/home_dashboard_data.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/review/domain/review_models.dart';
import 'package:memo_mind/features/review/domain/review_repository.dart';
import 'package:memo_mind/features/review/presentation/review_session_screen.dart';

import '../unit/material_generation_database_v6_test.dart' as fixture;

class ScreenRepository implements ReviewRepository {
  ScreenRepository(this.card);
  final CardEntity? card;
  ReviewSnapshot? saved;
  Completer<void>? gate;
  bool fail = false;
  int calls = 0;
  @override
  Future<ReviewSnapshot?> getActiveSession() async =>
      saved?.session.isActive == true ? saved : null;
  @override
  Future<ReviewSnapshot?> startSession({
    bool dueOnly = true,
    String? deckId,
    String? cardId,
  }) async {
    if (card == null) return null;
    return saved = ReviewSnapshot(
      ReviewSession(
        id: 's',
        dueOnly: dueOnly,
        queue: [card!.id],
        learningQueue: [],
        initialCount: 1,
      ),
      card,
      [],
    );
  }

  @override
  Future<ReviewSnapshot> rate({
    required String sessionId,
    required String cardId,
    required String eventId,
    required DateTime reviewedAt,
    required ReviewRating rating,
  }) async {
    calls++;
    await gate?.future;
    if (fail) throw StateError('Write failed');
    final again = rating == ReviewRating.again;
    return saved = ReviewSnapshot(
      ReviewSession(
        id: 's',
        dueOnly: true,
        queue: [],
        learningQueue: again ? [cardId] : [],
        initialCount: 1,
        status: again ? 'active' : 'completed',
      ),
      again ? card : null,
      [
        ...saved!.events,
        ReviewEvent(
          eventId: eventId,
          sessionId: sessionId,
          cardId: cardId,
          deviceId: 'device',
          reviewedAt: reviewedAt,
          rating: rating,
        ),
      ],
    );
  }

  @override
  Future<ReviewSnapshot> loadSession(String sessionId) async => saved!;
  @override
  Future<ReviewSnapshot> endSession(String sessionId) async =>
      saved = ReviewSnapshot(
        ReviewSession(
          id: 's',
          dueOnly: true,
          queue: [],
          learningQueue: [],
          initialCount: 1,
          status: 'ended',
        ),
        null,
        saved!.events,
      );
  @override
  Future<List<ReviewDeck>> getDecks() async => [];
  @override
  Future<HomeDashboardData> getDashboard() => throw UnimplementedError();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  for (final type in CardType.values) {
    testWidgets('${type.name}: reveal then rating completes and summarizes', (
      tester,
    ) async {
      final haptics = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final repo = ScreenRepository(fixture.card('c', type));
      await tester.pumpWidget(
        MaterialApp(home: ReviewSessionScreen(repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đáp án'), findsNothing);
      expect(find.text('Good'), findsNothing);
      await tapText(tester, 'Lật thẻ');
      expect(find.text('Đáp án'), findsWidgets);
      for (final rating in ReviewRating.values) {
        expect(find.text(rating.label), findsOneWidget);
      }
      await tapText(tester, 'Good');
      expect(find.text('Hoàn thành phiên ôn'), findsOneWidget);
      expect(find.text('1 thẻ đã ôn • 1 lượt đánh giá'), findsOneWidget);
      expect(repo.calls, 1);
      expect(haptics, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.lightImpact',
      ]);
    });
  }
  testWidgets('unsupported haptics do not interrupt reveal or rating', (
    tester,
  ) async {
    var attempts = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          attempts++;
          throw PlatformException(code: 'unsupported');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final repo = ScreenRepository(fixture.card('c', CardType.basic));
    await tester.pumpWidget(
      MaterialApp(home: ReviewSessionScreen(repository: repo)),
    );
    await tester.pumpAndSettle();
    await tapText(tester, 'Lật thẻ');
    await tapText(tester, 'Good');
    expect(find.text('Hoàn thành phiên ôn'), findsOneWidget);
    expect(repo.calls, 1);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Again is shown again and unique cards differ from rating count',
    (tester) async {
      final repo = ScreenRepository(fixture.card('c', CardType.basic));
      await tester.pumpWidget(
        MaterialApp(home: ReviewSessionScreen(repository: repo)),
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Lật thẻ');
      await tapText(tester, 'Again');
      expect(find.text('Ôn lại các thẻ Again'), findsOneWidget);
      expect(find.text('Good'), findsNothing);
      await tapText(tester, 'Lật thẻ');
      await tapText(tester, 'Good');
      expect(find.text('1 thẻ đã ôn • 2 lượt đánh giá'), findsOneWidget);
    },
  );
  testWidgets('save failure keeps answer and retry completes', (tester) async {
    final repo = ScreenRepository(fixture.card('c', CardType.basic))
      ..fail = true;
    await tester.pumpWidget(
      MaterialApp(home: ReviewSessionScreen(repository: repo)),
    );
    await tester.pumpAndSettle();
    await tapText(tester, 'Lật thẻ');
    await tapText(tester, 'Good');
    expect(find.text('Thử lưu lại'), findsOneWidget);
    expect(find.text('Hoàn thành phiên ôn'), findsNothing);
    repo.fail = false;
    await tapText(tester, 'Thử lưu lại');
    expect(find.text('Hoàn thành phiên ôn'), findsOneWidget);
  });
  testWidgets('buttons are disabled while save is pending', (tester) async {
    final repo = ScreenRepository(fixture.card('c', CardType.basic))
      ..gate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(home: ReviewSessionScreen(repository: repo)),
    );
    await tester.pumpAndSettle();
    await tapText(tester, 'Lật thẻ');
    await tester.ensureVisible(find.text('Good'));
    await tester.tap(find.text('Good'));
    await tester.pump();
    await tester.tap(find.text('Easy'));
    expect(repo.calls, 1);
    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Hoàn thành phiên ôn'), findsOneWidget);
  });
  testWidgets('empty due and free sessions show distinct messages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewSessionScreen(repository: ScreenRepository(null)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hiện không có thẻ đến hạn'), findsOneWidget);
    expect(find.text('Ôn tự do'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewSessionScreen(
          key: const ValueKey('free'),
          repository: ScreenRepository(null),
          dueOnly: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Deck chưa có thẻ để ôn'), findsOneWidget);
  });
  testWidgets('existing session offers resume and hides answer until flipped', (
    tester,
  ) async {
    final repo = ScreenRepository(fixture.card('c', CardType.basic));
    await repo.startSession();
    await tester.pumpWidget(
      MaterialApp(home: ReviewSessionScreen(repository: repo)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bạn có phiên ôn đang dở'), findsOneWidget);
    await tapText(tester, 'Tiếp tục phiên');
    expect(find.text('Lật thẻ'), findsOneWidget);
    expect(find.text('Good'), findsNothing);
  });
}
