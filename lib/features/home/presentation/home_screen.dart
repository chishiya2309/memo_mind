import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/memo_theme.dart';
import '../domain/home_dashboard_data.dart';
import 'home_formatters.dart';
import 'home_sections.dart';

class HomeActions {
  const HomeActions({
    required this.onStartReview,
    required this.onFreeReview,
    required this.onOpenDueDecks,
    required this.onOpenDeck,
    required this.onStartDeckReview,
    required this.onOpenDocument,
    required this.onOpenStatistics,
    required this.onOpenLibrary,
    required this.onOpenProfile,
    required this.onOpenApprovals,
    required this.onOpenJob,
    required this.onRetrySync,
    required this.onRetryLoad,
    required this.onImport,
  });

  final VoidCallback onStartReview;
  final VoidCallback onFreeReview;
  final VoidCallback onOpenDueDecks;
  final ValueChanged<String> onOpenDeck;
  final ValueChanged<String> onStartDeckReview;
  final ValueChanged<String> onOpenDocument;
  final VoidCallback onOpenStatistics;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenApprovals;
  final ValueChanged<String> onOpenJob;
  final VoidCallback onRetrySync;
  final VoidCallback onRetryLoad;
  final ValueChanged<ImportSource> onImport;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.data, required this.actions});

  final HomeDashboardData data;
  final HomeActions actions;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedTab = 0;

  Future<void> _showCreateSheet() async {
    final source = await showModalBottomSheet<ImportSource>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: MemoPalette.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => const _CreateSheet(),
    );
    if (source != null && mounted) widget.actions.onImport(source);
  }

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: selectedTab == 0
            ? _HomeDashboard(
                data: widget.data,
                actions: widget.actions,
                onCreate: _showCreateSheet,
              )
            : _TabPlaceholder(index: selectedTab),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create-material-fab'),
        onPressed: _showCreateSheet,
        backgroundColor: p.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 3,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tạo học liệu'),
        tooltip: 'Tạo học liệu mới',
        shape: const StadiumBorder(),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _BottomNavigation(
        selectedTab: selectedTab,
        onSelect: (index) {
          setState(() => selectedTab = index);
        },
      ),
    );
  }
}

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard({
    required this.data,
    required this.actions,
    required this.onCreate,
  });

  final HomeDashboardData data;
  final HomeActions actions;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final hPadding = MediaQuery.sizeOf(context).width < 360 ? 16.0 : 20.0;
    return CustomScrollView(
      key: const Key('home-scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: EdgeInsets.fromLTRB(hPadding, 8, hPadding, 128),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BrandBar(data: data, onProfile: actions.onOpenProfile),
                    const SizedBox(height: 18),
                    Text(
                      '${greetingFor(data.now)}${data.displayName == null || data.displayName!.trim().isEmpty ? '' : ', ${data.displayName!.trim()}'}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vietnameseDate(data.now),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    if (data.loadState == HomeLoadState.loading)
                      const _HomeSkeleton()
                    else if (data.loadState == HomeLoadState.error)
                      _LoadError(
                        message: data.loadError,
                        onRetry: actions.onRetryLoad,
                      )
                    else ...[
                      if (data.syncState == HomeSyncState.failed ||
                          data.isOffline ||
                          data.syncState == HomeSyncState.syncing) ...[
                        _StatusBanner(data: data, onRetry: actions.onRetrySync),
                        const SizedBox(height: 16),
                      ],
                      _ReviewHero(
                        data: data,
                        onStartReview: () {
                          HapticFeedback.lightImpact();
                          actions.onStartReview();
                        },
                        onFreeReview: actions.onFreeReview,
                        onOpenDueDecks: actions.onOpenDueDecks,
                        onCreate: onCreate,
                        onImport: actions.onImport,
                      ),
                      if (data.pendingApprovalCount > 0) ...[
                        const SizedBox(height: 16),
                        _ApprovalCard(
                          data: data,
                          onOpen: actions.onOpenApprovals,
                        ),
                      ],
                      const SizedBox(height: 24),
                      WeeklyStatsSection(
                        stats: data.weeklyStats,
                        onDetails: actions.onOpenStatistics,
                      ),
                      if (data.recentDecks.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        RecentDecksSection(
                          decks: data.recentDecks.take(3).toList(),
                          onAll: actions.onOpenLibrary,
                          onOpen: actions.onOpenDeck,
                          onReview: actions.onStartDeckReview,
                        ),
                      ],
                      if (data.jobs.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        ProcessingJobsSection(
                          jobs: data.jobs,
                          onOpen: actions.onOpenJob,
                        ),
                      ],
                      if (data.recentDocuments.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        RecentDocumentsSection(
                          documents: data.recentDocuments.take(3).toList(),
                          now: data.now,
                          onAll: actions.onOpenLibrary,
                          onOpen: actions.onOpenDocument,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BrandBar extends StatelessWidget {
  const _BrandBar({required this.data, required this.onProfile});

  final HomeDashboardData data;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    final statusText = data.syncState == HomeSyncState.failed
        ? 'Cần kiểm tra đồng bộ'
        : data.pendingSyncChanges > 0
        ? 'Có dữ liệu chờ đồng bộ'
        : 'Chỉ lưu trên thiết bị';
    final statusColor =
        data.syncState == HomeSyncState.failed || data.pendingSyncChanges > 0
        ? p.warning
        : p.textMuted;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CustomPaint(painter: _MemoLogoPainter(p.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'MemoMind',
              maxLines: 2,
              softWrap: true,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Semantics(
            label: 'Tài khoản, $statusText',
            button: true,
            child: Tooltip(
              message: 'Cá nhân',
              child: InkWell(
                onTap: onProfile,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: p.hero,
                        child: Icon(Icons.person_rounded, color: p.primary),
                      ),
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: p.background, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoLogoPainter extends CustomPainter {
  const _MemoLogoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3, 3, size.width - 8, size.height - 8),
        const Radius.circular(5),
      ),
      stroke,
    );
    canvas.drawLine(const Offset(9, 11), const Offset(19, 11), stroke);
    canvas.drawLine(const Offset(9, 17), const Offset(14, 17), stroke);
    canvas.drawCircle(const Offset(23, 21), 5, stroke);
    canvas.drawCircle(Offset(23, 21), 1.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MemoLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.data, required this.onRetry});

  final HomeDashboardData data;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    final failed = data.syncState == HomeSyncState.failed;
    final offline = !failed && data.isOffline;
    final icon = failed
        ? Icons.warning_amber_rounded
        : offline
        ? Icons.cloud_off_rounded
        : Icons.sync_rounded;
    final title = failed
        ? 'Chưa thể sao lưu dữ liệu'
        : offline
        ? 'Bạn đang ngoại tuyến'
        : 'Đang sao lưu ${data.pendingSyncChanges} thay đổi…';
    final detail = failed
        ? 'Dữ liệu vẫn an toàn trên thiết bị.'
        : offline
        ? 'Việc ôn tập và dữ liệu đã tải vẫn hoạt động.'
        : null;
    return Semantics(
      container: true,
      label: detail == null ? title : '$title. $detail',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: failed ? p.warning : p.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(detail, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  if (failed)
                    TextButton(
                      onPressed: onRetry,
                      child: const Text('Thử lại'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewHero extends StatelessWidget {
  const _ReviewHero({
    required this.data,
    required this.onStartReview,
    required this.onFreeReview,
    required this.onOpenDueDecks,
    required this.onCreate,
    required this.onImport,
  });

  final HomeDashboardData data;
  final VoidCallback onStartReview;
  final VoidCallback onFreeReview;
  final VoidCallback onOpenDueDecks;
  final VoidCallback onCreate;
  final ValueChanged<ImportSource> onImport;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    final review = data.review;
    return Container(
      key: const Key('review-hero'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.hero,
        borderRadius: BorderRadius.circular(24),
      ),
      child: data.totalDeckCount == 0
          ? _newUser(context, p)
          : review.remaining == 0
          ? _completed(context, p)
          : _due(context, p, review),
    );
  }

  Widget _label(BuildContext context, MemoPalette p) => Row(
    children: [
      Expanded(
        child: Text(
          'ÔN TẬP HÔM NAY',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: p.primaryDark,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
          ),
        ),
      ),
      Icon(Icons.calendar_today_rounded, size: 20, color: p.primaryDark),
    ],
  );

  Widget _due(BuildContext context, MemoPalette p, ReviewPlan review) {
    final compact =
        MediaQuery.sizeOf(context).width < 350 ||
        MediaQuery.textScalerOf(context).scale(14) > 21;
    final title = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${review.remaining}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          TextSpan(
            text: ' thẻ còn lại',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
      key: const Key('remaining-due'),
    );
    final ring = SizedBox(
      width: 64,
      height: 64,
      child: Semantics(
        label: 'Tiến độ ôn tập hôm nay',
        value: '${review.reviewedToday} trên ${review.totalToday} thẻ đã ôn',
        child: Stack(
          alignment: Alignment.center,
          children: [
            _AnimatedProgressRing(value: review.progress, color: p.primary),
            Text(
              '${review.reviewedToday}/${review.totalToday}',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: p.text, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context, p),
        const SizedBox(height: 14),
        if (compact) ...[
          title,
          const SizedBox(height: 8),
          ring,
        ] else
          Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 12),
              ring,
            ],
          ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: onOpenDueDecks,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(48, 48),
            alignment: Alignment.centerLeft,
          ),
          child: Text(
            'Từ ${review.deckCount} bộ thẻ • khoảng ${review.estimatedMinutes} phút',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: p.textMuted),
          ),
        ),
        const SizedBox(height: 2),
        Semantics(
          label: 'Tiến độ ôn tập',
          value: '${review.reviewedToday} trên ${review.totalToday} thẻ đã ôn',
          child: LinearProgressIndicator(
            value: review.progress,
            minHeight: 7,
            borderRadius: BorderRadius.circular(100),
            backgroundColor: p.outline.withValues(alpha: 0.45),
            color: p.primary,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: Semantics(
            label: 'Bắt đầu ôn ${review.remaining} thẻ còn lại',
            child: FilledButton.icon(
              key: const Key('start-review'),
              onPressed: onStartReview,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Bắt đầu ôn'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
                backgroundColor: p.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _completed(BuildContext context, MemoPalette p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label(context, p),
      const SizedBox(height: 18),
      Icon(Icons.check_circle_rounded, color: p.success, size: 32),
      const SizedBox(height: 8),
      Text(
        'Bạn đã hoàn thành lịch ôn hôm nay',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 6),
      Text(
        'Không còn thẻ đến hạn. Bạn có thể ôn tự do hoặc tạo học liệu mới.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(onPressed: onFreeReview, child: const Text('Ôn tự do')),
          OutlinedButton(
            onPressed: onCreate,
            child: const Text('Tạo học liệu'),
          ),
        ],
      ),
    ],
  );

  Widget _newUser(BuildContext context, MemoPalette p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label(context, p),
      const SizedBox(height: 16),
      Row(
        children: [
          Icon(Icons.description_outlined, color: p.primary, size: 36),
          Icon(Icons.arrow_forward_rounded, color: p.primary, size: 24),
          Icon(Icons.style_outlined, color: p.primary, size: 36),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        'Biến bài giảng thành bộ thẻ đầu tiên',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 6),
      Text(
        'Chụp một trang hoặc chọn PDF. MemoMind sẽ giúp bạn tạo flashcard có dẫn nguồn.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => onImport(ImportSource.camera),
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Chụp bài giảng'),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onCreate,
          child: const Text('Chọn ảnh hoặc PDF'),
        ),
      ),
    ],
  );
}

class _AnimatedProgressRing extends StatelessWidget {
  const _AnimatedProgressRing({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 300),
      builder: (context, animatedValue, _) => CircularProgressIndicator(
        value: animatedValue,
        strokeWidth: 5,
        strokeCap: StrokeCap.round,
        color: color,
        backgroundColor: color.withValues(alpha: 0.16),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.data, required this.onOpen});

  final HomeDashboardData data;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.aiContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, color: p.aiAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${data.pendingApprovalCount} thẻ mới đang chờ bạn kiểm tra',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (data.pendingApprovalDocument != null)
                  Text(
                    'Từ tài liệu “${data.pendingApprovalDocument}”',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                TextButton(onPressed: onOpen, child: const Text('Xem thẻ')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    Widget block(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
      ),
    );
    return Semantics(
      label: 'Đang tải dữ liệu học trên thiết bị',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: p.hero,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                block(120, 14),
                const SizedBox(height: 22),
                block(210, 36),
                const SizedBox(height: 16),
                block(double.infinity, 8),
                const SizedBox(height: 20),
                block(double.infinity, 52),
              ],
            ),
          ),
          const SizedBox(height: 24),
          block(110, 24),
          const SizedBox(height: 12),
          block(double.infinity, 100),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.outline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.folder_off_outlined, color: p.warning, size: 30),
          const SizedBox(height: 12),
          Text(
            'Chưa thể mở dữ liệu học trên thiết bị',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            message ?? 'Hãy thử lại. Dữ liệu của bạn chưa bị thay đổi.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Thử tải lại')),
        ],
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({required this.selectedTab, required this.onSelect});

  final int selectedTab;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    const labels = ['Trang chủ', 'Thư viện', 'Thống kê', 'Cá nhân'];
    const icons = [
      Icons.home_rounded,
      Icons.library_books_rounded,
      Icons.bar_chart_rounded,
      Icons.person_rounded,
    ];
    return Material(
      color: p.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: p.outline.withValues(alpha: 0.65)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: List.generate(labels.length, (index) {
              final selected = selectedTab == index;
              return Expanded(
                child: Semantics(
                  selected: selected,
                  button: true,
                  label: labels[index],
                  child: InkWell(
                    key: Key('tab-$index'),
                    onTap: () => onSelect(index),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 72),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 8,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              width: 56,
                              height: 32,
                              decoration: BoxDecoration(
                                color: selected ? p.hero : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                icons[index],
                                color: selected ? p.primary : p.textMuted,
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              labels[index],
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              softWrap: true,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: selected ? p.primary : p.textMuted,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _TabPlaceholder extends StatelessWidget {
  const _TabPlaceholder({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final title = switch (index) {
      1 => 'Thư viện',
      2 => 'Thống kê',
      _ => 'Cá nhân',
    };
    final p = MemoPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.construction_rounded, color: p.primary, size: 40),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Màn hình này chưa được triển khai.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateSheet extends StatelessWidget {
  const _CreateSheet();

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: p.outline,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Tạo học liệu mới',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          _CreateOption(
            source: ImportSource.camera,
            icon: Icons.camera_alt_outlined,
            title: 'Chụp bài giảng',
            subtitle: 'Dùng camera để nhập một trang mới',
          ),
          _CreateOption(
            source: ImportSource.gallery,
            icon: Icons.image_outlined,
            title: 'Chọn ảnh từ thư viện',
            subtitle: 'Nhập ảnh đã có trên thiết bị',
          ),
          _CreateOption(
            source: ImportSource.pdf,
            icon: Icons.picture_as_pdf_outlined,
            title: 'Nhập PDF',
            subtitle: 'Chọn tài liệu PDF ngắn',
          ),
          _CreateOption(
            source: ImportSource.manualDeck,
            icon: Icons.style_outlined,
            title: 'Tạo deck thủ công',
            subtitle: 'Tự nhập bộ thẻ học',
          ),
        ],
      ),
    );
  }
}

class _CreateOption extends StatelessWidget {
  const _CreateOption({
    required this.source,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final ImportSource source;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    return InkWell(
      key: Key('import-${source.name}'),
      onTap: () => Navigator.of(context).pop(source),
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: p.hero,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: p.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
