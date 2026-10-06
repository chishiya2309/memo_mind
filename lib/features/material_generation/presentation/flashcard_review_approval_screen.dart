import 'dart:io';

import '../../deck_management/domain/deck_models.dart';
import '../domain/material_validator.dart';

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
    required this.targetDeck,
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
  final Deck targetDeck;
  final List<MaterialDraft> initialCards;
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
  late final List<MaterialDraft> _cards;
  late final Map<String, SourceBlock> _blocksMap;
  late final Map<int, SourcePage> _pagesMap;
  late final SaveAcceptedCardsUseCase _saveUseCase;
  late Deck _deck;
  bool _isSaving = false;
  bool _allowExit = false;
  bool _askingExit = false;
  int _filter = 0;
  bool get _busy => _isSaving || _regeneratingCardIds.isNotEmpty;
  final Set<String> _regeneratingCardIds = {};

  @override
  void initState() {
    super.initState();
    _deck = widget.targetDeck;
    _cards = List.of(widget.initialCards)
      ..sort((a, b) => a.type.index.compareTo(b.type.index));
    _blocksMap = {for (final b in widget.sourceBlocks) b.blockId: b};
    _pagesMap = {for (final p in widget.sourcePages) p.pageNumber: p};
    _saveUseCase =
        widget.saveUseCase ??
        SaveAcceptedCardsUseCase(
          deckRepository: widget.deckRepository,
          ocrRepository: widget.ocrRepository,
        );
  }

  int get _acceptedCount => _cards.where((c) => c.isAccepted).length;

  List<MaterialIssue> _issues(MaterialDraft card) => MaterialValidator.issues(
    card,
    sourceBlock: _blocksMap[card.sourceBlockId],
    documentId: widget.documentId,
    cards: _cards,
  );
  bool _canSave(MaterialDraft card) => !_issues(card).any((i) => i.isError);
  bool _validate(MaterialDraft card) {
    final errors = _issues(card).where((i) => i.isError);
    if (errors.isEmpty) return true;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(errors.first.message)));
    return false;
  }

  Future<void> _requestExit() async {
    if (_busy || _askingExit) return;
    _askingExit = true;
    final leave =
        _cards.isEmpty ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Rời màn duyệt?'),
                content: const Text(
                  'Các kết quả chưa lưu sẽ mất. Văn bản OCR đã xác nhận vẫn được giữ.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Tiếp tục duyệt'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Rời màn hình'),
                  ),
                ],
              ),
            ) ==
            true;
    _askingExit = false;
    if (leave && mounted) {
      setState(() => _allowExit = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  void _toggleAccept(MaterialDraft card) {
    if (_busy || (!card.isAccepted && !_validate(card))) return;
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

  void _rejectCard(MaterialDraft card) {
    if (_busy) return;
    final index = _cards.indexWhere((c) => c.id == card.id);
    if (index == -1) return;

    setState(() => _cards.removeAt(index));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Đã bỏ thẻ khỏi danh sách.'),
        action: SnackBarAction(
          label: 'Hoàn tác',
          onPressed: () {
            if (mounted && !_busy && !_cards.any((c) => c.id == card.id)) {
              setState(
                () => _cards.insert(index.clamp(0, _cards.length), card),
              );
            }
          },
        ),
      ),
    );
  }

  void _acceptAll() {
    if (_busy) return;
    var skipped = 0;
    setState(() {
      for (var i = 0; i < _cards.length; i++) {
        if (_canSave(_cards[i])) {
          _cards[i] = _cards[i].copyWith(status: DraftCardStatus.accepted);
        } else {
          skipped++;
        }
      }
    });
    if (skipped > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$skipped thẻ cần sửa trước khi chọn. Các thẻ này vẫn có trong danh sách.',
          ),
        ),
      );
    }
  }

  Future<void> _regenerateCard(MaterialDraft card) async {
    if (_busy) return;
    var block = _blocksMap[card.sourceBlockId];
    if (block == null) {
      block = await showDialog<SourceBlock>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Chọn nguồn để tạo lại'),
          children: [
            for (final source in widget.sourceBlocks)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, source),
                child: Text(
                  'Trang ${source.pageNumber}: ${source.normalizedText}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      );
      if (block == null || !mounted) return;
    }

    setState(() => _regeneratingCardIds.add(card.id));

    try {
      final result = await widget.generationRepository.generateMaterials(
        documentId: widget.documentId,
        types: {card.type},
        quantityMode: QuantityMode.manual,
        desiredCount: 1,
        sourceBlocks: [block],
      );
      if (result.cards.isEmpty) {
        throw const MaterialGenerationFailure(
          MaterialGenerationFailureCode.noValidCards,
          'AI chưa tạo được thẻ; thẻ hiện tại vẫn được giữ.',
        );
      }

      final index = _cards.indexWhere((c) => c.id == card.id);
      if (index != -1 && mounted) {
        setState(() {
          _cards[index] = result.cards.first.copyWith(
            id: card.id,
            status: DraftCardStatus.pending,
          );
          _cards.addAll(
            result.cards
                .skip(1)
                .map((c) => c.copyWith(status: DraftCardStatus.pending)),
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.cards.length == 1
                  ? 'Đã tạo lại thẻ. Hãy xem và chọn lại.'
                  : 'AI trả ${result.cards.length} thẻ; tất cả được giữ để bạn duyệt.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Không thể tạo lại thẻ: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _regeneratingCardIds.remove(card.id));
      }
    }
  }

  void _openEditDialog(MaterialDraft card) {
    if (_busy) return;
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

  void _openSourceInspection(MaterialDraft card) {
    final block = _blocksMap[card.sourceBlockId];
    final page = _pagesMap[card.sourcePage];
    File? pageFile;

    if (page != null) {
      final file = File(page.displayPath);
      if (file.existsSync()) pageFile = file;
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
    if (_busy) return;
    // Luồng 30a: Kiểm tra chưa chấp nhận thẻ nào
    if (_acceptedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn ít nhất một flashcard để lưu.'),
        ),
      );
      return;
    }

    final deck = _deck;

    setState(() => _isSaving = true);

    try {
      final savedCount = await _saveUseCase.execute(
        deckId: deck.id,
        documentId: widget.documentId,
        drafts: List.of(_cards),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        setState(() {
          _isSaving = false;
          _allowExit = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pop<MaterialSaveResult>((
              deckId: deck.id,
              savedCount: savedCount,
            ));
          }
        });
      }
    } on MaterialGenerationFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Không thể lưu thẻ. Danh sách chưa được lưu; vui lòng thử lại.',
            ),
          ),
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
    final visible = _cards.where((card) {
      final issues = _issues(card);
      return _filter == 0 ||
          (_filter == 1
              ? issues.any((i) => !i.isError)
              : issues.any((i) => i.isError));
    }).toList()..sort((a, b) => a.type.index.compareTo(b.type.index));
    final warningCount = _cards
        .where((c) => _issues(c).any((i) => !i.isError))
        .length;
    final errorCount = _cards.where((c) => !_canSave(c)).length;
    return PopScope<MaterialSaveResult>(
      canPop: _allowExit && !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Duyệt học liệu', style: TextStyle(fontSize: 18)),
              Text(
                widget.documentTitle,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : _acceptAll,
              child: const Text('Chọn hết'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Deck: ${_deck.title}'),
              trailing: TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final deck = await SelectOrCreateDeckSheet.show(
                          context,
                          deckRepository: widget.deckRepository,
                          cardCountToSave: _acceptedCount,
                        );
                        if (mounted && deck != null) {
                          setState(() => _deck = deck);
                        }
                      },
                child: const Text('Đổi deck'),
              ),
            ),
            if (widget.warnings.isNotEmpty)
              ExpansionTile(
                title: const Text('Thông tin kết quả'),
                children: [
                  for (final warning in widget.warnings)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(warning),
                    ),
                ],
              ),
            Text(
              'Tổng cộng ${_cards.length} thẻ • $warningCount có cảnh báo • $errorCount cần sửa',
            ),
            const SizedBox(height: 8),
            Text('Đã chọn $_acceptedCount / ${_cards.length}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (index, label) in [
                  (0, 'Tất cả'),
                  (1, 'Có cảnh báo'),
                  (2, 'Cần sửa'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _filter == index,
                    onSelected: (_) => setState(() => _filter = index),
                  ),
              ],
            ),
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Không có thẻ nào để hiển thị.'),
              ),
            for (var index = 0; index < visible.length; index++) ...[
              if (index == 0 || visible[index - 1].type != visible[index].type)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '${visible[index].type.displayName} (${visible.where((c) => c.type == visible[index].type).length})',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              AbsorbPointer(
                absorbing: _busy,
                child: _FlashcardItemCard(
                  card: visible[index],
                  palette: palette,
                  theme: theme,
                  number: _cards.indexOf(visible[index]) + 1,
                  issues: _issues(visible[index]),
                  isRegenerating: _regeneratingCardIds.contains(
                    visible[index].id,
                  ),
                  onToggleAccept: () => _toggleAccept(visible[index]),
                  onReject: () => _rejectCard(visible[index]),
                  onEdit: () => _openEditDialog(visible[index]),
                  onInspectSource: () => _openSourceInspection(visible[index]),
                  onRegenerate: () => _regenerateCard(visible[index]),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _busy || _acceptedCount == 0 ? null : _handleSave,
              icon: const Icon(Icons.bookmark_added_outlined),
              label: Text(
                _isSaving
                    ? 'Đang lưu thẻ...'
                    : 'Lưu các thẻ đã chọn ($_acceptedCount)',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlashcardItemCard extends StatelessWidget {
  const _FlashcardItemCard({
    required this.card,
    required this.number,
    required this.issues,
    required this.palette,
    required this.theme,
    required this.isRegenerating,
    required this.onToggleAccept,
    required this.onReject,
    required this.onEdit,
    required this.onInspectSource,
    required this.onRegenerate,
  });

  final MaterialDraft card;
  final int number;
  final List<MaterialIssue> issues;
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
    final needsSourceCheck = issues.isNotEmpty;
    final needsRepair = issues.any((i) => i.isError);

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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Text('#$number'),
                // Format badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.aiContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    card.rawResponse != null
                        ? 'Lỗi định dạng'
                        : card.type.displayName,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surfaceMuted,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    card.sourcePage > 0
                        ? 'Trang ${card.sourcePage}'
                        : 'Chưa rõ trang',
                    style: TextStyle(fontSize: 11, color: palette.textMuted),
                  ),
                ),

                // Status chip
                if (isAccepted)
                  _buildStatusChip('Đã chấp nhận', palette.success)
                else if (isRejected)
                  _buildStatusChip('Đã loại bỏ', palette.error)
                else if (needsSourceCheck)
                  _buildStatusChip(
                    needsRepair ? 'Cần sửa trước khi lưu' : 'Có cảnh báo',
                    palette.warning,
                  )
                else
                  _buildStatusChip('Chưa duyệt', palette.textMuted),
              ],
            ),
            const SizedBox(height: 12),

            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  issue.message,
                  style: TextStyle(
                    color: issue.isError ? palette.error : palette.warning,
                  ),
                ),
              ),
            if (card.rawResponse != null)
              ExpansionTile(
                title: const Text('Dữ liệu AI gốc'),
                children: [SelectableText(card.rawResponse!)],
              ),
            // Question
            Text(
              'Câu hỏi:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            _buildQuestionText(),
            const SizedBox(height: 10),

            if (card.type == CardType.mcq) ...[
              for (final option in card.options)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '${option.optionId}. ${option.text}',
                    style: TextStyle(
                      fontWeight: option.optionId == card.correctOptionId
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text('Giải thích: ${card.explanation ?? ""}'),
              const SizedBox(height: 8),
            ],
            // Answer
            Text(
              'Đáp án:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: palette.hero,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                card.back,
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
                    Icon(
                      Icons.format_quote_rounded,
                      size: 14,
                      color: palette.primary,
                    ),
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
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 8,
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
                        isRejected
                            ? Icons.delete_rounded
                            : Icons.delete_outline_rounded,
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
                    foregroundColor: isAccepted
                        ? palette.success
                        : palette.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: Icon(
                    isAccepted
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                    size: 18,
                  ),
                  label: Text(isAccepted ? 'Đã chấp nhận' : 'Chấp nhận'),
                  onPressed: needsRepair && !isAccepted ? null : onToggleAccept,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionText() {
    if (card.type == CardType.cloze && card.front.contains('[...]')) {
      final parts = card.front.split('[...]');
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
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
      card.front,
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
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
