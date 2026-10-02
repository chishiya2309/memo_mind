import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/home/presentation/home_screen.dart';
import 'package:memo_mind/features/review/domain/due_cards_source.dart';
import 'package:memo_mind/features/review/presentation/due_cards_screen.dart';
import 'package:memo_mind/features/statistics/application/statistics_controller.dart';
import 'package:memo_mind/features/statistics/presentation/statistics_screen.dart';
import 'package:memo_mind/shared/theme/memo_theme.dart';

import '../support/statistics_fakes.dart';
import 'home_screen_test.dart' as home;

class EmptyDueSource implements DueCardsSource {
  int reads = 0;
  @override
  Future<List<DueCard>> getDueCards(DateTime at) async {
    reads++;
    return [];
  }

  @override
  Future<bool> hasActiveSession() async => false;
}

void main() {
  final now = DateTime.utc(2026, 10, 2, 8);
  late FakeStatisticsRepository repository;
  late StatisticsController controller;
  setUp(() {
    repository = FakeStatisticsRepository();
    controller = StatisticsController(
      repository: repository,
      studyChanges: const Stream<void>.empty(),
      clock: () => now,
      timeZone: () async => 'Asia/Ho_Chi_Minh',
    );
  });
  tearDown(() => controller.dispose());

  Future<void> pumpStatistics(
    WidgetTester tester, {
    double scale = 1,
    bool dark = false,
    Future<void> Function()? open,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MemoTheme.light,
        darkTheme: MemoTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: StatisticsScreen(
            controller: controller,
            onOpenDueCards: open ?? () async {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'AC01 empty success has four metrics, dash and disabled due action',
    (tester) async {
      await controller.refresh();
      await pumpStatistics(tester);
      expect(find.text('Dữ liệu trên thiết bị này'), findsOneWidget);
      expect(find.text('Thẻ đến hạn'), findsOneWidget);
      expect(find.text('Lượt ôn hôm nay'), findsOneWidget);
      expect(find.text('Tỷ lệ đúng'), findsOneWidget);
      expect(find.text('Chuỗi ngày học'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('0 ngày'), findsOneWidget);
      expect(
        find.text('Theo tự đánh giá\nChưa có lượt ôn hôm nay'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('statistics-review-due')),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Cập nhật lúc 15:00'), findsOneWidget);
    },
  );

  testWidgets('AC03/10 percentage, denominator and data-quality warning', (
    tester,
  ) async {
    repository.data = statisticsSnapshot(
      at: now,
      events: [
        for (final (id, rating) in [
          ('1', 'again'),
          ('2', 'hard'),
          ('3', 'good'),
          ('4', 'easy'),
          ('bad', 'unknown'),
        ])
          statisticsEvent(id, now, rating),
      ],
    );
    await controller.refresh();
    await pumpStatistics(tester);
    expect(find.text('75,0%'), findsOneWidget);
    expect(find.text('Theo tự đánh giá\n3/4 lượt đạt'), findsOneWidget);
    expect(find.text('Một số dữ liệu ôn chưa được tính'), findsOneWidget);
  });

  testWidgets(
    'AC10 loading/error contain no successful zeros; retry and stale retention',
    (tester) async {
      repository.delayed = true;
      final loading = controller.refresh();
      await pumpStatistics(tester);
      expect(find.byKey(const Key('statistics-loading')), findsOneWidget);
      expect(find.text('0'), findsNothing);
      repository.pending.first.completeError(StateError('database'));
      await loading;
      await tester.pump();
      expect(find.text('Chưa tải được thống kê'), findsOneWidget);
      expect(find.text('—'), findsNothing);
      repository.delayed = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pump();
      expect(find.text('—'), findsOneWidget);
      repository.error = StateError('database');
      await controller.refresh();
      await tester.pump();
      expect(find.text('Dữ liệu cũ'), findsOneWidget);
      expect(find.text('Cập nhật lúc 15:00'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    },
  );

  testWidgets('AC11 due action freshly queries and can open an empty list', (
    tester,
  ) async {
    repository.data = statisticsSnapshot(at: now, cards: {'card': now});
    await controller.refresh();
    final source = EmptyDueSource();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: StatisticsScreen(
              controller: controller,
              onOpenDueCards: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DueCardsScreen(
                      source: source,
                      clock: () => now,
                      onOpenLibrary: () {},
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('statistics-review-due')));
    await tester.tap(find.byKey(const Key('statistics-review-due')));
    await tester.pumpAndSettle();
    expect(source.reads, 1);
    expect(find.text('Bạn chưa có thẻ đến hạn'), findsOneWidget);
    final calls = repository.calls;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(repository.calls, calls + 1);
  });

  testWidgets(
    'home summary and details use the same tab and shared result; routes suspend timers',
    (tester) async {
      repository.data = statisticsSnapshot(
        at: now,
        events: [statisticsEvent('a', now)],
      );
      final observer = RouteObserver<ModalRoute<void>>();
      await tester.pumpWidget(
        MaterialApp(
          theme: MemoTheme.light,
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) => HomeScreen(
              data: home.state(),
              actions: home.actions(),
              statisticsController: controller,
              statisticsRouteObserver: observer,
              onOpenDueCards: () async => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Covered')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Xem chi tiết'));
      await tester.tap(find.text('Xem chi tiết'));
      await tester.pump();
      expect(find.byType(StatisticsScreen), findsOneWidget);
      expect(find.text('100,0%'), findsOneWidget);
      expect(find.text('7/18'), findsNothing);
      await tester.tap(find.byKey(const Key('tab-0')));
      await tester.pump();
      expect(find.text('7/18'), findsOneWidget);
      // Push directly so route visibility behavior is tested independently of counts.
      final context = tester.element(find.byType(HomeScreen));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              Scaffold(appBar: AppBar(title: const Text('Covered'))),
        ),
      );
      await tester.pumpAndSettle();
      final calls = repository.calls;
      await tester.pump(const Duration(seconds: 31));
      expect(repository.calls, calls);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(repository.calls, calls + 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'narrow screen, large text and dark theme remain scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      repository.data = statisticsSnapshot(at: now, cards: {'card': now});
      await controller.refresh();
      await pumpStatistics(tester, scale: 2, dark: true);
      await tester.ensureVisible(
        find.byKey(const Key('statistics-review-due')),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Ôn thẻ đến hạn'), findsOneWidget);
    },
  );

  testWidgets('unsupported platforms show a message without querying storage', (
    tester,
  ) async {
    final unsupported = StatisticsController(
      repository: repository,
      studyChanges: const Stream<void>.empty(),
      supported: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatisticsScreen(
            controller: unsupported,
            onOpenDueCards: () async {},
          ),
        ),
      ),
    );
    expect(
      find.text('Thống kê học tập hiện hỗ trợ trên Android.'),
      findsOneWidget,
    );
    expect(repository.calls, 0);
    unsupported.dispose();
  });
}
