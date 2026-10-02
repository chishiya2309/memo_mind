import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../shared/theme/memo_theme.dart';
import '../application/statistics_controller.dart';
import '../data/statistics_time_zone.dart';
import '../domain/statistics_models.dart';

/// Shared by the home summary and the statistics tab.
class StatisticsPanel extends StatelessWidget {
  const StatisticsPanel({
    super.key,
    required this.controller,
    required this.onOpenDueCards,
    this.onDetails,
  });

  final StatisticsController? controller;
  final Future<void> Function() onOpenDueCards;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final source = controller;
    if (source == null || !source.supported) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Thống kê học tập'),
          SizedBox(height: 12),
          Text('Thống kê học tập hiện hỗ trợ trên Android.'),
        ],
      );
    }
    return ListenableBuilder(
      listenable: source,
      builder: (context, _) {
        final data = source.snapshot;
        final p = MemoPalette.of(context);
        final style = Theme.of(context).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Thống kê học tập', style: style.titleLarge),
                if (onDetails != null)
                  TextButton(
                    onPressed: onDetails,
                    child: const Text('Xem chi tiết'),
                  ),
                IconButton(
                  onPressed: source.refresh,
                  tooltip: 'Làm mới',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            Text('Dữ liệu trên thiết bị này', style: style.bodySmall),
            const SizedBox(height: 12),
            if (source.refreshing)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(key: Key('statistics-loading')),
              ),
            if (source.state == StatisticsLoadState.error ||
                source.state == StatisticsLoadState.stale) ...[
              Text(
                'Chưa tải được thống kê',
                style: style.bodyMedium?.copyWith(color: p.error),
              ),
              if (data != null) const Text('Dữ liệu cũ'),
              TextButton(
                onPressed: source.refresh,
                child: const Text('Thử lại'),
              ),
            ],
            if (data != null) ...[
              Text(
                'Hôm nay · ${data.localDate.day}/${data.localDate.month}/${data.localDate.year}',
                style: style.bodySmall,
              ),
              Text(_updatedAt(data), style: style.bodySmall),
              if (data.dataQualityStatus == StatisticsDataQuality.partial)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Một số dữ liệu ôn chưa được tính',
                    style: style.bodyMedium?.copyWith(color: p.warning),
                  ),
                ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      constraints.maxWidth >= 340 &&
                          MediaQuery.textScalerOf(context).scale(14) <= 21
                      ? 2
                      : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _Metric(
                        width: width,
                        icon: Icons.style_outlined,
                        label: 'Thẻ đến hạn',
                        value: '${data.dueCardCount}',
                        detail: data.dueCardCount == 0
                            ? 'Bạn chưa có thẻ đến hạn'
                            : 'Tại thời điểm cập nhật',
                        onTap: data.dueCardCount > 0
                            ? () => _openDueCards(source)
                            : null,
                      ),
                      _Metric(
                        width: width,
                        icon: Icons.replay_rounded,
                        label: 'Lượt ôn hôm nay',
                        value: '${data.reviewCountToday}',
                        detail: 'Mỗi lần đánh giá đã lưu là một lượt',
                      ),
                      _Metric(
                        width: width,
                        icon: Icons.check_circle_outline_rounded,
                        label: 'Tỷ lệ đúng',
                        value: data.successRateToday == null
                            ? '—'
                            : '${data.successRateToday!.toStringAsFixed(1).replaceAll('.', ',')}%',
                        detail: data.reviewCountToday == 0
                            ? 'Theo tự đánh giá\nChưa có lượt ôn hôm nay'
                            : 'Theo tự đánh giá\n${data.successfulReviewCountToday}/${data.reviewCountToday} lượt đạt',
                      ),
                      _Metric(
                        width: width,
                        icon: Icons.local_fire_department_outlined,
                        label: 'Chuỗi ngày học',
                        value: '${data.currentStreakDays} ngày',
                        detail: data.studiedToday
                            ? 'Đã học hôm nay'
                            : 'Chưa học hôm nay',
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('statistics-review-due'),
                onPressed: data.dueCardCount > 0
                    ? () => _openDueCards(source)
                    : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Ôn thẻ đến hạn'),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _openDueCards(StatisticsController source) async {
    await onOpenDueCards();
    await source.refresh();
  }

  String _updatedAt(StatisticsSnapshot data) {
    final local = tz.TZDateTime.from(
      data.asOf,
      statisticsTimeZone(data.timeZoneId),
    );
    return 'Cập nhật lúc ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.onTap,
  });
  final double width;
  final IconData icon;
  final String label, value, detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    final style = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: p.primary),
                const SizedBox(height: 8),
                Text(label, style: style.titleSmall),
                Text(value, style: style.headlineMedium),
                const SizedBox(height: 4),
                Text(detail, style: style.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
