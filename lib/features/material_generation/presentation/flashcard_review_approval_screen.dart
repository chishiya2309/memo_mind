import 'dart:io';
import 'package:flutter/material.dart';

import '../../../shared/theme/memo_theme.dart';
import '../../deck_management/domain/deck_repository.dart';
import '../../document_import/domain/document_import_models.dart';
import '../../ocr_editor/domain/ocr_models.dart';
import '../../ocr_editor/domain/ocr_repository.dart';
import '../application/save_accepted_cards_use_case.dart';
import '../domain/material_generation_models.dart';
import '../domain/material_generation_repository.dart';
import 'flashcard_edit_dialog.dart';
import 'select_or_create_deck_sheet.dart';
import 'source_inspection_modal.dart';

class FlashcardReviewApprovalScreen extends StatefulWidget {
  const FlashcardReviewApprovalScreen({
    super.key,
    required this.documentId,
    required this.documentTitle,
    required this.initialCards,
    required this.sourceBlocks,
    required this.sourcePages,
    required this.deckRepository,
    required this.ocrRepository,
    required this.generationRepository,
    this.saveUseCase,
    this.discardedCount = 0,
    this.warnings = const [],
    this.storageDirectory,
  });

  final String documentId;
  final String documentTitle;
  final List<FlashcardDraft> initialCards;
  final List<SourceBlock> sourceBlocks;
  final List<SourcePage> sourcePages;
  final DeckRepository deckRepository;
  final OcrRepository ocrRepository;
  final MaterialGenerationRepository generationRepository;
  final SaveAcceptedCardsUseCase? saveUseCase;
  final int discardedCount;
  final List<String> warnings;
  final Directory? storageDirectory;

  @override
  State<FlashcardReviewApprovalScreen> createState() =>
      _FlashcardReviewApprovalScreenState();
}

class _FlashcardReviewApprovalScreenState
    extends State<FlashcardReviewApprovalScreen> {
  late final List<FlashcardDraft> _cards;
  late final Map<String, SourceBlock> _blocksMap;
  late final Map<int, SourcePage> _pagesMap;
  late final SaveAcceptedCardsUseCase _saveUseCase;
  bool _isSaving = false;
  final Set<String> _regeneratingCardIds = {};

  @override
  void initState() {
    super.initState();
    _cards = List.of(widget.initialCards);
    _blocksMap = {for (final b in widget.sourceBlocks) b.blockId: b};
    _pagesMap = {for (final p in widget.sourcePages) p.pageNumber: p};
    _saveUseCase = widget.saveUseCase ??
        SaveAcceptedCardsUseCase(
          deckRepository: widget.deckRepository,
          ocrRepository: widget.ocrRepository,
        );
  }

  int get _acceptedCount => _cards.where((c) => c.isAccepted).length;

  void _toggleAccept(FlashcardDraft card) {
    final index = _cards.indexWhere((c) => c.id == card.id);
    if (index == -1) return;

    setState(() {
      final current = _cards[index];
      final newStatus = current.isAccepted
          ? DraftCardStatus.pending
          : DraftCardStatus.accepted;
      _cards[index] = current.copyWith(status: newStatus);
    });
  }

  void _rejectCard(FlashcardDraft card) {
    final index = _cards.indexWhere((c) => c.id == card.id);
    if (index == -1) return;

    setState(() {
      _cards[index] = _cards[index].copyWith(status: DraftCardStatus.rejected);
    });
  }

  void _acceptAll() {
    setState(() {
      for (var i = 0; i < _cards.length; i++) {
        if (!_cards[i].isRejected && !_cards[i].needsSourceCheck) {
          _cards[i] = _cards[i].copyWith(status: DraftCardStatus.accepted);
        }
      }
    });
  }

  Future<void> _regenerateCard(FlashcardDraft card) async {
    final block = _blocksMap[card.sourceBlockId];
    if (block == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy khối nguồn tương ứng.')),
      );
      return;
    }

    setState(() => _regeneratingCardIds.add(card.id));

    try {
      final newCard = await widget.generationRepository.regenerateSingleCard(
        sourceBlock: block,
        format: card.format,
      );

      final index = _cards.indexWhere((c) => c.id == card.id);
      if (index != -1 && mounted) {
        setState(() {
          _cards[index] = newCard;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã tạo lại thẻ thành công.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể tạo lại thẻ: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _regeneratingCardIds.remove(card.id));
      }
    }
  }

  void _openEditDialog(FlashcardDraft card) {
    final block = _blocksMap[card.sourceBlockId];
    FlashcardEditDialog.show(
      context,
      card: card,
      sourceBlock: block,
      onSaved: (updated) {
        final index = _cards.indexWhere((c) => c.id == card.id);
        if (index != -1) {
          setState(() {
            _cards[index] = updated;
          });
        }
      },
    );
  }

  void _openSourceInspection(FlashcardDraft card) {
    final block = _blocksMap[card.sourceBlockId];
    final page = _pagesMap[card.sourcePage];
    File? pageFile;

    if (page != null && widget.storageDirectory != null) {
      final path = '${widget.storageDirectory!.path}/${page.dataRelativePath}';
      final file = File(path);
      if (file.existsSync()) {
        pageFile = file;
      }
    }

    SourceInspectionModal.show(
      context,
      documentTitle: widget.documentTitle,
      sourcePage: page,
      sourceBlock: block,
      sourceQuote: card.sourceQuote,
      sourcePageFile: pageFile,
    );
  }

  Future<void> _handleSave() async {
    // Luồng 30a: Kiểm tra chưa chấp nhận thẻ nào
    if (_acceptedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn ít nhất một flashcard để lưu.')),
      );
      return;
    }

    // Luồng 31: Chọn deck có sẵn hoặc tạo mới
    final deck = await SelectOrCreateDeckSheet.show(
      context,
      deckRepository: widget.deckRepository,
      cardCountToSave: _acceptedCount,
    );

    if (deck == null || !mounted) return;

    setState(() => _isSaving = true);

    try {
      final savedCount = await _saveUseCase.execute(
        deckId: deck.id,
        documentId: widget.documentId,
        drafts: _cards,
      );

      if (mounted) {
        // Luồng 36: Hiển thị thông báo thành công
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã thêm $savedCount flashcard vào deck "${deck.title}".'),
            backgroundColor: MemoPalette.of(context).success,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } on MaterialGenerationFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi lưu thẻ: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Duyệt Flashcard',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.documentTitle,
              style: TextStyle(fontSize: 12, color: palette.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _acceptAll,
            child: const Text('Chọn hết'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Discarded warnings banner (Luồng 24a)
          if (widget.discardedCount > 0)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: palette.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: palette.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Đã tạo ${widget.initialCards.length} thẻ hợp lệ. Đã tự động loại bỏ ${widget.discardedCount} thẻ không đạt chuẩn nguồn hoặc trùng lặp.',
                      style: TextStyle(color: palette.warning, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          // Status counter bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tổng cộng ${_cards.length} thẻ',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _acceptedCount > 0
                        ? palette.success.withValues(alpha: 0.15)
                        : palette.surfaceMuted,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Đã chọn $_acceptedCount / ${_cards.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _acceptedCount > 0 ? palette.success : palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Cards list
          Expanded(
            child: _cards.isEmpty
                ? Center(
                    child: Text(
                      'Không có thẻ nào để hiển thị.',
                      style: TextStyle(color: palette.textMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    itemCount: _cards.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final card = _cards[index];
                      final isRegenerating = _regeneratingCardIds.contains(card.id);
                      return _FlashcardItemCard(
                        card: card,
                        palette: palette,
                        theme: theme,
                        isRegenerating: isRegenerating,
                        onToggleAccept: () => _toggleAccept(card),
                        onReject: () => _rejectCard(card),
                        onEdit: () => _openEditDialog(card),
                        onInspectSource: () => _openSourceInspection(card),
                        onRegenerate: () => _regenerateCard(card),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              offset: const Offset(0, -4),
              blurRadius: 10,
            ),
          ],
        ),
        child: SafeArea(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: palette.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.bookmark_added_rounded),
            label: Text(
              _isSaving ? 'Đang lưu thẻ...' : 'Lưu các thẻ đã chọn ($_acceptedCount)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            onPressed: _isSaving ? null : _handleSave,
          ),
        ),
      ),
    );
  }
}

class _FlashcardItemCard extends StatelessWidget {
  const _FlashcardItemCard({
    required this.card,
    required this.palette,
    required this.theme,
    required this.isRegenerating,
    required this.onToggleAccept,
    required this.onReject,
    required this.onEdit,
    required this.onInspectSource,
    required this.onRegenerate,
  });

  final FlashcardDraft card;
  final MemoPalette palette;
  final ThemeData theme;
  final bool isRegenerating;
  final VoidCallback onToggleAccept;
  final VoidCallback onReject;
  final VoidCallback onEdit;
  final VoidCallback onInspectSource;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final isAccepted = card.isAccepted;
    final isRejected = card.isRejected;
    final needsSourceCheck = card.needsSourceCheck;

    Color borderColor = palette.outline.withValues(alpha: 0.3);
    if (isAccepted) borderColor = palette.success;
    if (isRejected) borderColor = palette.error.withValues(alpha: 0.4);
    if (needsSourceCheck) borderColor = palette.warning;

    return Card(
      elevation: isAccepted ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor, width: isAccepted ? 2 : 1),
      ),
      color: isRejected
          ? palette.surfaceMuted.withValues(alpha: 0.5)
          : palette.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Format chip, Source Page badge, Status chip
            Row(
              children: [
                // Format badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: palette.aiContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    card.format == FlashcardFormat.qa ? 'Hỏi – đáp' : 'Điền khuyết',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: palette.aiAccent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Source page badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: palette.surfaceMuted,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Trang ${card.sourcePage}',
                    style: TextStyle(fontSize: 11, color: palette.textMuted),
                  ),
                ),

                const Spacer(),

                // Status chip
                if (isAccepted)
                  _buildStatusChip('Đã chấp nhận', palette.success)
                else if (isRejected)
                  _buildStatusChip('Đã loại bỏ', palette.error)
                else if (needsSourceCheck)
                  _buildStatusChip('Cần kiểm tra nguồn', palette.warning)
                else
                  _buildStatusChip('Chưa duyệt', palette.textMuted),
              ],
            ),
            const SizedBox(height: 12),

            // Question
            Text(
              'Câu hỏi:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: palette.textMuted),
            ),
            const SizedBox(height: 4),
            _buildQuestionText(),
            const SizedBox(height: 10),

            // Answer
            Text(
              'Đáp án:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: palette.textMuted),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: palette.hero,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                card.answer,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.primary,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Quote snippet
            InkWell(
              onTap: onInspectSource,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.format_quote_rounded, size: 14, color: palette.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        card.sourceQuote,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Xem nguồn',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: palette.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 18),

            // Actions Toolbar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: 'Chỉnh sửa thẻ',
                      onPressed: onEdit,
                    ),
                    IconButton(
                      icon: isRegenerating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      tooltip: 'Tạo lại thẻ này',
                      onPressed: isRegenerating ? null : onRegenerate,
                    ),
                    IconButton(
                      icon: Icon(
                        isRejected ? Icons.delete_rounded : Icons.delete_outline_rounded,
                        size: 18,
                        color: palette.error,
                      ),
                      tooltip: 'Loại bỏ thẻ',
                      onPressed: onReject,
                    ),
                  ],
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: isAccepted
                        ? palette.success.withValues(alpha: 0.15)
                        : palette.hero,
                    foregroundColor: isAccepted ? palette.success : palette.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: Icon(
                    isAccepted ? Icons.check_circle : Icons.check_circle_outline,
                    size: 18,
                  ),
                  label: Text(isAccepted ? 'Đã chấp nhận' : 'Chấp nhận'),
                  onPressed: onToggleAccept,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionText() {
    if (card.format == FlashcardFormat.cloze && card.question.contains('[...]')) {
      final parts = card.question.split('[...]');
      return RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: palette.text,
            height: 1.4,
          ),
          children: [
            for (var i = 0; i < parts.length; i++) ...[
              TextSpan(text: parts[i]),
              if (i < parts.length - 1)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: palette.aiContainer,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: palette.aiAccent, width: 1.2),
                    ),
                    child: Text(
                      '[ ... ]',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: palette.aiAccent,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    }

    return Text(
      card.question,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: palette.text,
        height: 1.4,
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
