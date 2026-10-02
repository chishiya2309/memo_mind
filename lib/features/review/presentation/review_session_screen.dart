import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../material_generation/domain/material_generation_models.dart';
import '../../material_generation/presentation/source_inspection_modal.dart';
import '../../deck_management/application/get_card_source_trace_use_case.dart';
import '../../deck_management/data/local_deck_repository.dart';
import '../../deck_management/domain/deck_repository.dart';
import '../../deck_management/domain/deck_models.dart';
import '../application/review_session_controller.dart';
import '../data/local_review_repository.dart';
import '../domain/review_models.dart';
import '../domain/review_repository.dart';
import 'review_deck_selection_screen.dart';
import 'review_summary_screen.dart';

class ReviewSessionScreen extends StatefulWidget {
  const ReviewSessionScreen({
    super.key,
    this.repository,
    this.dueOnly = true,
    this.deckId,
    this.cardId,
    this.deckRepository,
  });
  final ReviewRepository? repository;
  final bool dueOnly;
  final String? deckId, cardId;
  final DeckRepository? deckRepository;
  @override
  State<ReviewSessionScreen> createState() => _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends State<ReviewSessionScreen> {
  late final ReviewSessionController controller;
  bool get unsupported => kIsWeb && widget.repository == null;
  @override
  void initState() {
    super.initState();
    controller = ReviewSessionController(
      widget.repository ?? LocalReviewRepository(),
    );
    if (!unsupported) _initialize();
  }

  Future<void> _initialize() => controller.initialize(
    dueOnly: widget.dueOnly,
    deckId: widget.deckId,
    cardId: widget.cardId,
  );

  Future<void> _openFreeReview() async {
    // Keep this route's Future pending until the whole free-review flow ends,
    // so the caller refreshes Home after returning, not on entering the picker.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ReviewDeckSelectionScreen(repository: widget.repository),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _haptic() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {
      /* Optional feedback. */
    }
  }

  Future<void> _source(CardEntity card) async {
    final trace = await GetCardSourceTraceUseCase(
      deckRepository: widget.deckRepository ?? LocalDeckRepository(),
    ).execute(card);
    if (!mounted) return;
    await SourceInspectionModal.show(
      context,
      documentTitle: trace.documentTitle,
      sourcePage: trace.sourcePage,
      sourceBlock: trace.sourceBlock,
      sourceQuote: trace.sourceQuote,
      sourcePageFile: trace.imageFile,
      sourcePageNumber: trace.sourcePageNumber,
      imageUsesNormalizedCoordinates: trace.imageUsesNormalizedCoordinates,
      warning: trace.warning,
    );
  }

  Future<void> _end() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kết thúc phiên ôn?'),
        content: const Text(
          'Các đánh giá đã lưu được giữ lại. Bạn có thể bắt đầu phiên mới sau đó.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Tiếp tục ôn'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kết thúc'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) await controller.end();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final snapshot = controller.snapshot;
      return PopScope(
        canPop: !controller.busy,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Ôn tập ngoại tuyến'),
            actions: [
              if (snapshot?.session.isActive ?? false) ...[
                TextButton(
                  onPressed: controller.busy
                      ? null
                      : () => Navigator.pop(context),
                  child: const Text('Tạm dừng'),
                ),
                IconButton(
                  tooltip: 'Kết thúc phiên',
                  onPressed: controller.busy ? null : _end,
                  icon: const Icon(Icons.stop_circle_outlined),
                ),
              ],
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: unsupported
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Ôn tập ngoại tuyến hiện hỗ trợ trên Android. Hãy chạy ứng dụng trên điện thoại hoặc máy ảo Android.',
                        ),
                      )
                    : controller.busy && snapshot == null
                    ? const CircularProgressIndicator()
                    : snapshot == null
                    ? _empty()
                    : !snapshot.session.isActive
                    ? ReviewSummary(snapshot: snapshot)
                    : controller.awaitingResume
                    ? _resume(snapshot)
                    : _card(snapshot),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _empty() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          controller.error ??
              (widget.dueOnly
                  ? 'Hiện không có thẻ đến hạn'
                  : 'Deck chưa có thẻ để ôn'),
        ),
        const SizedBox(height: 16),
        if (controller.error != null)
          FilledButton(onPressed: _initialize, child: const Text('Thử lại'))
        else if (widget.dueOnly)
          FilledButton(
            onPressed: _openFreeReview,
            child: const Text('Ôn tự do'),
          ),
      ],
    ),
  );

  Widget _resume(ReviewSnapshot snapshot) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Bạn có phiên ôn đang dở',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          '${snapshot.reviewedCards} thẻ đã ôn • ${snapshot.session.remaining} lượt còn chờ',
        ),
        if (controller.error != null) Text(controller.error!),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: controller.busy ? null : controller.resume,
          child: const Text('Tiếp tục phiên'),
        ),
        TextButton(
          onPressed: controller.busy ? null : _end,
          child: const Text('Kết thúc phiên đang dở'),
        ),
      ],
    ),
  );

  Widget _card(ReviewSnapshot snapshot) {
    final card = snapshot.card;
    if (card == null) return const Center(child: Text('Không còn thẻ hợp lệ.'));
    final revealed = controller.revealed;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (card.hasSource)
            OutlinedButton.icon(
              onPressed: controller.busy ? null : () => _source(card),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Xem nguồn'),
            ),
          Text(
            '${snapshot.reviewedCards}/${snapshot.session.initialCount} thẻ đã ôn • ${snapshot.session.remaining} lượt còn chờ',
          ),
          if (snapshot.session.queue.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Ôn lại các thẻ Again'),
            ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: snapshot.session.initialCount == 0
                ? 0
                : (snapshot.reviewedCards / snapshot.session.initialCount)
                      .clamp(0.0, 1.0),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    card.type.displayName,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 20),
                  SelectableText(
                    card.front,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (card.type == CardType.mcq) ...[
                    const SizedBox(height: 16),
                    for (final option in card.options)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text('${option.optionId}. ${option.text}'),
                      ),
                  ],
                  if (revealed) ...[
                    const Divider(height: 40),
                    Text(
                      'Đáp án',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      card.type == CardType.mcq
                          ? '${card.correctOptionId}. ${card.back}'
                          : card.back,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (card.explanation?.isNotEmpty ?? false)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(card.explanation!),
                      ),
                    if (card.sourceQuote.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(
                          'Nguồn: ${card.sourceQuote}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (!revealed)
            FilledButton(
              onPressed: controller.busy
                  ? null
                  : () {
                      controller.reveal();
                      _haptic();
                    },
              child: const Text('Lật thẻ'),
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final rating in ReviewRating.values)
                  FilledButton.tonal(
                    onPressed: controller.busy || controller.hasPendingRating
                        ? null
                        : () {
                            controller.rate(rating);
                            _haptic();
                          },
                    child: Text(rating.label),
                  ),
              ],
            ),
          if (controller.busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (controller.error != null) ...[
            const SizedBox(height: 16),
            Text(
              controller.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            if (controller.hasPendingRating)
              TextButton(
                onPressed: controller.busy ? null : controller.retry,
                child: const Text('Thử lưu lại'),
              ),
            TextButton(
              onPressed: controller.busy ? null : controller.reload,
              child: const Text('Tải lại phiên'),
            ),
          ],
        ],
      ),
    );
  }
}
