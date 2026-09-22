import 'package:flutter/material.dart';

import '../../../shared/theme/memo_theme.dart';
import '../domain/home_dashboard_data.dart';
import 'home_formatters.dart';

class WeeklyStatsSection extends StatelessWidget {
  const WeeklyStatsSection({
    super.key,
    required this.stats,
    required this.onDetails,
  });

  final WeeklyStats? stats;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          title: 'Tuần này',
          action: 'Xem chi tiết',
          onTap: onDetails,
        ),
        const SizedBox(height: 12),
        _SurfaceCard(
          child: stats == null || stats!.reviewedCards == 0
              ? Text(
                  'Học thêm một vài phiên để xem xu hướng tuần.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final vertical =
                        constraints.maxWidth < 330 ||
                        MediaQuery.textScalerOf(context).scale(13) > 19;
                    final items = [
                      _StatItem(
                        icon: Icons.local_fire_department_outlined,
                        value: '${stats!.streakDays} ngày',
                        label: 'Chuỗi học',
                        color: p.primary,
                      ),
                      _StatItem(
                        icon: Icons.style_outlined,
                        value: '${stats!.reviewedCards} thẻ',
                        label: 'Đã ôn',
                        color: p.primary,
                      ),
                      _StatItem(
                        icon: Icons.check_circle_outline_rounded,
                        value: stats!.accuracyPercent == null
                            ? '—'
                            : '${stats!.accuracyPercent}%',
                        label: 'Tỷ lệ đúng',
                        color: p.secondary,
                      ),
                    ];
                    if (vertical) {
                      return Column(
                        children: [
                          for (var i = 0; i < items.length; i++) ...[
                            if (i > 0) ...[
                              const SizedBox(height: 10),
                              Divider(color: p.outline, height: 1),
                              const SizedBox(height: 10),
                            ],
                            items[i],
                          ],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0)
                            Container(
                              width: 1,
                              height: 64,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              color: p.outline,
                            ),
                          Expanded(child: items[i]),
                        ],
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label $value',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.titleLarge, maxLines: 2),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class RecentDecksSection extends StatelessWidget {
  const RecentDecksSection({
    super.key,
    required this.decks,
    required this.onAll,
    required this.onOpen,
    required this.onReview,
  });

  final List<DeckPreview> decks;
  final VoidCallback onAll;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onReview;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionHeading(
        title: 'Tiếp tục học',
        action: 'Xem tất cả',
        onTap: onAll,
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < decks.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        _DeckCard(deck: decks[i], onOpen: onOpen, onReview: onReview),
      ],
    ],
  );
}

class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.deck,
    required this.onOpen,
    required this.onReview,
  });

  final DeckPreview deck;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onReview;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    return _SurfaceCard(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: Key('deck-${deck.id}'),
              onTap: () => onOpen(deck.id),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: MemoPalette.deckPastel(context, deck.tone.index),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.style_rounded, color: p.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deck.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${deck.dueCount} thẻ đến hạn • khoảng ${deck.estimatedMinutes} phút',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (deck.statusLabel != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              deck.statusLabel!,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: p.primary),
                            ),
                          ],
                          const SizedBox(height: 9),
                          Semantics(
                            label:
                                '${deck.title}, đã học ${deck.learnedPercent} phần trăm',
                            child: Row(
                              children: [
                                Expanded(
                                  child: LinearProgressIndicator(
                                    value: deck.learnedPercent / 100,
                                    minHeight: 6,
                                    borderRadius: BorderRadius.circular(100),
                                    backgroundColor: p.surfaceMuted,
                                    color: p.secondary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${deck.learnedPercent}%',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 52,
            child: IconButton(
              key: Key('review-deck-${deck.id}'),
              onPressed: () => onReview(deck.id),
              tooltip: 'Ôn bộ thẻ ${deck.title}',
              icon: Icon(
                Icons.play_circle_fill_rounded,
                color: p.primary,
                size: 30,
              ),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class ProcessingJobsSection extends StatelessWidget {
  const ProcessingJobsSection({
    super.key,
    required this.jobs,
    required this.onOpen,
  });

  final List<HomeJobPreview> jobs;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Tài liệu đang xử lý',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < jobs.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        _JobCard(job: jobs[i], onOpen: () => onOpen(jobs[i].id)),
      ],
    ],
  );
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.onOpen});

  final HomeJobPreview job;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    final failed = job.state == HomeJobState.failed;
    return _SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: job.kind == HomeJobKind.ai ? p.aiContainer : p.hero,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              job.kind == HomeJobKind.ai
                  ? Icons.auto_awesome_rounded
                  : Icons.document_scanner_outlined,
              color: job.kind == HomeJobKind.ai ? p.aiAccent : p.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(job.title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  job.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (job.state == HomeJobState.running) ...[
                  const SizedBox(height: 10),
                  Semantics(
                    label: job.progress == null
                        ? 'Đang xử lý, chưa có tiến độ cụ thể'
                        : 'Đã xử lý ${(job.progress! * 100).round()} phần trăm',
                    child: LinearProgressIndicator(
                      value: job.progress,
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(100),
                      color: p.primary,
                      backgroundColor: p.surfaceMuted,
                    ),
                  ),
                ],
                if (failed) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Văn bản OCR của bạn vẫn được lưu.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (job.state != HomeJobState.running)
                  TextButton(
                    onPressed: onOpen,
                    child: Text(failed ? 'Xem lỗi' : 'Tiếp tục'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RecentDocumentsSection extends StatelessWidget {
  const RecentDocumentsSection({
    super.key,
    required this.documents,
    required this.now,
    required this.onAll,
    required this.onOpen,
  });

  final List<HomeDocumentPreview> documents;
  final DateTime now;
  final VoidCallback onAll;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionHeading(
        title: 'Tài liệu gần đây',
        action: 'Xem tất cả',
        onTap: onAll,
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < documents.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        _DocumentCard(
          document: documents[i],
          now: now,
          onOpen: () => onOpen(documents[i].id),
        ),
      ],
    ],
  );
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.now,
    required this.onOpen,
  });

  final HomeDocumentPreview document;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    final status = switch (document.state) {
      HomeDocumentState.ocrDone => 'Đã OCR',
      HomeDocumentState.needsReview => 'Chờ hiệu chỉnh',
      HomeDocumentState.hasCards => '${document.cardCount} thẻ đã tạo',
      HomeDocumentState.noCards => 'Chưa tạo thẻ',
    };
    return _SurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        key: Key('document-${document.id}'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 64,
                decoration: BoxDecoration(
                  color: p.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.picture_as_pdf_outlined, color: p.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${document.pageCount} trang • nhập ${importedDate(document.importedAt, now)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      status,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: document.state == HomeDocumentState.needsReview
                            ? p.warning
                            : p.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.action,
    required this.onTap,
  });

  final String title;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(13) > 19;
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          TextButton(onPressed: onTap, child: Text(action)),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.outline.withValues(alpha: 0.65)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}
