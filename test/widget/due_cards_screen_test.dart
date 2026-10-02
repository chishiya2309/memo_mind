import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/home/domain/home_dashboard_data.dart';
import 'package:memo_mind/features/review/domain/review_repository.dart';
import 'package:memo_mind/features/review/presentation/due_cards_screen.dart';

import '../support/reminder_fakes.dart';

class DashboardReviewRepository implements ReviewRepository {
  bool hasSession = false;
  @override
  Future<HomeDashboardData> getDashboard() async => HomeDashboardData(
    now: DateTime.utc(2026, 10, 2),
    hasActiveReviewSession: hasSession,
    totalDeckCount: 0,
    review: const ReviewPlan(
      totalToday: 0,
      reviewedToday: 0,
      deckCount: 0,
      estimatedMinutes: 0,
    ),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'shows queried due cards and re-queries stale notification on resume',
    (tester) async {
      var now = DateTime.utc(2026, 10, 2, 1);
      final source = FakeDueCardsSource()..cards = [dueCard(now)];
      final review = DashboardReviewRepository();
      var libraries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DueCardsScreen(
            source: source,
            reviewRepository: review,
            clock: () => now,
            onOpenLibrary: () => libraries++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Câu hỏi c'), findsOneWidget);
      expect(find.text('BASIC • Bộ thẻ'), findsOneWidget);
      expect(find.text('Bắt đầu ôn'), findsOneWidget);
      source.cards = [];
      now = now.add(const Duration(hours: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(source.requestedAt, now);
      expect(find.text('Bạn chưa có thẻ đến hạn'), findsOneWidget);
      await tester.tap(find.text('Về Thư viện'));
      expect(libraries, 1);
    },
  );
  testWidgets('read error retries and preserves active review entry', (
    tester,
  ) async {
    final source = FakeDueCardsSource()..fail = true;
    source.activeSession = true;
    final review = DashboardReviewRepository()..hasSession = true;
    await tester.pumpWidget(
      MaterialApp(
        home: DueCardsScreen(
          source: source,
          reviewRepository: review,
          onOpenLibrary: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Không thể tải thẻ đến hạn. Thử lại'), findsOneWidget);
    source.fail = false;
    await tester.tap(find.text('Không thể tải thẻ đến hạn. Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Tiếp tục phiên ôn đang dở'), findsOneWidget);
    expect(find.text('Bạn chưa có thẻ đến hạn'), findsOneWidget);
  });
}
