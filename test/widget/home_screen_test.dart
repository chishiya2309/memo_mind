import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/home/data/demo_home_data.dart';
import 'package:memo_mind/features/home/domain/home_dashboard_data.dart';
import 'package:memo_mind/features/home/presentation/home_screen.dart';
import 'package:memo_mind/shared/theme/memo_theme.dart';

final fixedNow = DateTime(2026, 9, 22, 9);

HomeDashboardData state({
  int deckCount = 4,
  ReviewPlan review = const ReviewPlan(
    totalToday: 18,
    reviewedToday: 7,
    deckCount: 3,
    estimatedMinutes: 8,
  ),
  WeeklyStats? stats,
  bool offline = false,
  HomeSyncState sync = HomeSyncState.idle,
  HomeLoadState load = HomeLoadState.ready,
  String? error,
  int approvals = 0,
  List<HomeJobPreview> jobs = const [],
}) => HomeDashboardData(
  now: fixedNow,
  review: review,
  totalDeckCount: deckCount,
  weeklyStats: stats,
  isOffline: offline,
  syncState: sync,
  loadState: load,
  loadError: error,
  pendingApprovalCount: approvals,
  pendingApprovalDocument: 'Mạng máy tính Chương 2',
  jobs: jobs,
);

HomeActions actions({
  VoidCallback? onStartReview,
  VoidCallback? onFreeReview,
  VoidCallback? onRetrySync,
  VoidCallback? onRetryLoad,
  ValueChanged<ImportSource>? onImport,
  ValueChanged<String>? onOpenDeck,
  ValueChanged<String>? onStartDeckReview,
}) => HomeActions(
  onStartReview: onStartReview ?? () {},
  onFreeReview: onFreeReview ?? () {},
  onOpenDueDecks: () {},
  onOpenDeck: onOpenDeck ?? (_) {},
  onStartDeckReview: onStartDeckReview ?? (_) {},
  onOpenDocument: (_) {},
  onOpenStatistics: () {},
  onOpenLibrary: () {},
  onOpenProfile: () {},
  onOpenApprovals: () {},
  onOpenJob: (_) {},
  onRetrySync: onRetrySync ?? () {},
  onRetryLoad: onRetryLoad ?? () {},
  onImport: onImport ?? (_) {},
);

Future<void> pumpHome(
  WidgetTester tester,
  HomeDashboardData data, {
  HomeActions? homeActions,
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: MemoTheme.light,
      darkTheme: MemoTheme.dark,
      themeMode: themeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: HomeScreen(data: data, actions: homeActions ?? actions()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('demo starts review with one tap and shows correct progress', (
    tester,
  ) async {
    var starts = 0;
    await pumpHome(
      tester,
      demoHomeDashboard(now: fixedNow),
      homeActions: actions(onStartReview: () => starts++),
    );

    expect(find.text('Chào buổi sáng, Hưng'), findsOneWidget);
    expect(find.text('11 thẻ còn lại'), findsOneWidget);
    expect(find.text('7/18'), findsOneWidget);
    expect(find.text('Tuần này'), findsOneWidget);
    expect(find.text('Tiếp tục học'), findsOneWidget);

    await tester.tap(find.byKey(const Key('start-review')));
    expect(starts, 1);
  });

  testWidgets('new user is invited to import without zero-valued statistics', (
    tester,
  ) async {
    ImportSource? selected;
    await pumpHome(
      tester,
      state(
        deckCount: 0,
        review: const ReviewPlan(
          totalToday: 0,
          reviewedToday: 0,
          deckCount: 0,
          estimatedMinutes: 0,
        ),
      ),
      homeActions: actions(onImport: (value) => selected = value),
    );

    expect(find.text('Biến bài giảng thành bộ thẻ đầu tiên'), findsOneWidget);
    expect(
      find.text('Học thêm một vài phiên để xem xu hướng tuần.'),
      findsOneWidget,
    );
    expect(find.text('0%'), findsNothing);
    await tester.tap(find.text('Chụp bài giảng'));
    expect(selected, ImportSource.camera);
  });

  testWidgets('completed plan offers free review', (tester) async {
    var freeReviews = 0;
    await pumpHome(
      tester,
      state(
        review: const ReviewPlan(
          totalToday: 18,
          reviewedToday: 18,
          deckCount: 3,
          estimatedMinutes: 0,
        ),
      ),
      homeActions: actions(onFreeReview: () => freeReviews++),
    );
    expect(find.text('Bạn đã hoàn thành lịch ôn hôm nay'), findsOneWidget);
    await tester.tap(find.text('Ôn tự do'));
    expect(freeReviews, 1);
  });

  testWidgets('sync failure takes precedence over offline and can retry', (
    tester,
  ) async {
    var retries = 0;
    await pumpHome(
      tester,
      state(offline: true, sync: HomeSyncState.failed),
      homeActions: actions(onRetrySync: () => retries++),
    );
    expect(find.text('Chưa thể sao lưu dữ liệu'), findsOneWidget);
    expect(find.text('Dữ liệu vẫn an toàn trên thiết bị.'), findsOneWidget);
    expect(find.text('Bạn đang ngoại tuyến'), findsNothing);
    await tester.tap(find.text('Thử lại'));
    expect(retries, 1);
  });

  testWidgets('offline banner explains that review still works', (
    tester,
  ) async {
    await pumpHome(tester, state(offline: true));
    expect(find.text('Bạn đang ngoại tuyến'), findsOneWidget);
    expect(
      find.text('Việc ôn tập và dữ liệu đã tải vẫn hoạt động.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('start-review')), findsOneWidget);
  });

  testWidgets('loading uses skeleton and database error has retry', (
    tester,
  ) async {
    var retries = 0;
    await pumpHome(tester, state(load: HomeLoadState.loading));
    expect(find.byKey(const Key('review-hero')), findsNothing);
    expect(find.text('11 thẻ còn lại'), findsNothing);

    await pumpHome(
      tester,
      state(load: HomeLoadState.error, error: 'Không đọc được cơ sở dữ liệu.'),
      homeActions: actions(onRetryLoad: () => retries++),
    );
    expect(find.text('Không đọc được cơ sở dữ liệu.'), findsOneWidget);
    await tester.tap(find.text('Thử tải lại'));
    expect(retries, 1);
  });

  testWidgets('pending approvals and AI job are conditional', (tester) async {
    await pumpHome(
      tester,
      state(
        approvals: 8,
        jobs: const [
          HomeJobPreview(
            id: 'ai-job',
            title: 'Đang tạo học liệu',
            description: 'Dự kiến tạo 8 flashcard và 4 câu trắc nghiệm…',
            kind: HomeJobKind.ai,
            state: HomeJobState.running,
          ),
        ],
      ),
    );
    expect(find.text('8 thẻ mới đang chờ bạn kiểm tra'), findsOneWidget);
    expect(find.text('Đang tạo học liệu'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets(
    'FAB choices return their source; tabs have visible destinations',
    (tester) async {
      ImportSource? source;
      await pumpHome(
        tester,
        state(),
        homeActions: actions(onImport: (value) => source = value),
      );
      await tester.tap(find.byKey(const Key('create-material-fab')));
      await tester.pumpAndSettle();
      expect(find.text('Tạo học liệu mới'), findsOneWidget);
      expect(find.text('Chụp bài giảng'), findsOneWidget);
      expect(find.text('Chọn ảnh từ thư viện'), findsOneWidget);
      expect(find.text('Nhập PDF'), findsOneWidget);
      expect(find.text('Tạo deck thủ công'), findsOneWidget);
      await tester.tap(find.byKey(const Key('import-pdf')));
      await tester.pumpAndSettle();
      expect(source, ImportSource.pdf);

      await tester.tap(find.byKey(const Key('tab-1')));
      await tester.pump();
      expect(find.text('Màn hình này chưa được triển khai.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tab-0')));
      await tester.pump();
      expect(find.byKey(const Key('review-hero')), findsOneWidget);
    },
  );

  testWidgets('deck card and play button call different actions', (
    tester,
  ) async {
    String? opened;
    String? reviewed;
    await pumpHome(
      tester,
      demoHomeDashboard(now: fixedNow),
      homeActions: actions(
        onOpenDeck: (id) => opened = id,
        onStartDeckReview: (id) => reviewed = id,
      ),
    );

    await tester.drag(
      find.byKey(const Key('home-scroll')),
      const Offset(0, -450),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deck-data-structures')));
    expect(opened, 'data-structures');
    expect(reviewed, isNull);

    await tester.tap(find.byKey(const Key('review-deck-data-structures')));
    expect(reviewed, 'data-structures');
    expect(
      tester
          .getSize(find.byKey(const Key('review-deck-data-structures')))
          .width,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('small screens, dark theme, and large text do not overflow', (
    tester,
  ) async {
    for (final width in [320.0, 360.0, 390.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      await pumpHome(
        tester,
        demoHomeDashboard(now: fixedNow),
        themeMode: ThemeMode.dark,
        textScale: 2,
      );
      expect(tester.takeException(), isNull, reason: 'Overflow at $width dp');
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}
