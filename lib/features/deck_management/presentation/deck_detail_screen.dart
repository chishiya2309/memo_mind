import 'package:flutter/material.dart';

import '../../../shared/theme/memo_theme.dart';
import '../../material_generation/presentation/source_inspection_modal.dart';
import '../application/get_card_source_trace_use_case.dart';
import '../domain/deck_models.dart';
import '../domain/deck_repository.dart';
import 'card_editor_dialog.dart';
import '../../review/domain/review_repository.dart';
import '../../review/presentation/review_session_screen.dart';

class DeckDetailScreen extends StatefulWidget {
  const DeckDetailScreen({
    super.key,
    required this.deckId,
    required this.repository,
    this.reviewRepository,
  });

  final String deckId;
  final DeckRepository repository;
  final ReviewRepository? reviewRepository;

  @override
  State<DeckDetailScreen> createState() => _DeckDetailScreenState();
}

class _DeckDetailScreenState extends State<DeckDetailScreen> {
  final _searchController = TextEditingController();
  late final GetCardSourceTraceUseCase _sourceTraceUseCase;
  Deck? _deck;
  List<CardEntity> _cards = const [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _sourceTraceUseCase = GetCardSourceTraceUseCase(
      deckRepository: widget.repository,
    );
    _loadDeck();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CardEntity> get _visibleCards {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _cards;
    return _cards
        .where(
          (card) =>
              card.front.toLowerCase().contains(query) ||
              card.back.toLowerCase().contains(query) ||
              card.sourceQuote.toLowerCase().contains(query) ||
              (card.explanation?.toLowerCase().contains(query) ?? false) ||
              card.options.any((o) => o.text.toLowerCase().contains(query)) ||
              card.tags.any((t) => t.toLowerCase().contains(query)),
        )
        .toList(growable: false);
  }

  Future<void> _loadDeck() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final deck = await widget.repository.getDeckById(widget.deckId);
      final cards = await widget.repository.getCardsForDeck(widget.deckId);
      if (!mounted) return;
      setState(() {
        _deck = deck;
        _cards = cards;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Không thể tải bộ thẻ trên thiết bị.';
        _loading = false;
      });
    }
  }

  bool _hasSource(CardEntity card) => card.hasSource;

  Future<void> _editCard([CardEntity? card]) async {
    final saved = await CardEditorDialog.show(
      context,
      repository: widget.repository,
      deckId: widget.deckId,
      card: card,
    );
    if (mounted && saved) await _loadDeck();
  }

  Future<void> _review([CardEntity? card]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReviewSessionScreen(
          deckId: widget.deckId,
          cardId: card?.id,
          dueOnly: false,
          repository: widget.reviewRepository,
          deckRepository: widget.repository,
        ),
      ),
    );
    if (mounted) await _loadDeck();
  }

  Future<void> _viewSource(CardEntity card) async {
    if (!_hasSource(card)) return;
    final trace = await _sourceTraceUseCase.execute(card);
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

  Future<void> _deleteCard(CardEntity card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa thẻ?'),
        content: const Text(
          'Thẻ sẽ không còn xuất hiện trong deck hoặc phiên ôn. Lịch sử và tài liệu nguồn được giữ lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: MemoPalette.of(context).error,
            ),
            child: const Text('Xóa thẻ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.repository.deleteCard(card.id);
      if (!mounted) return;
      await _loadDeck();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể xóa thẻ. Vui lòng thử lại.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_deck?.title ?? 'Bộ thẻ'),
        actions: [
          IconButton(
            key: const Key('review-deck'),
            tooltip: 'Ôn ngay',
            onPressed: _deck == null ? null : () => _review(),
            icon: const Icon(Icons.play_arrow),
          ),
          IconButton(
            key: const Key('create-card'),
            tooltip: 'Tạo thẻ thủ công',
            onPressed: _deck == null ? null : () => _editCard(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_deck != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${_deck!.cardCount} thẻ',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                TextField(
                  key: const Key('search-cards'),
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Tìm mặt trước, mặt sau hoặc nguồn',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Xóa tìm kiếm',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: palette.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: palette.outline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: palette.outline),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(child: _buildCardList(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardList(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null || _deck == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _loadError ?? 'Bộ thẻ không còn tồn tại.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadDeck,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }

    final cards = _visibleCards;
    if (cards.isEmpty) {
      final searching = _searchController.text.trim().isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                searching ? Icons.search_off_rounded : Icons.style_outlined,
                size: 40,
                color: MemoPalette.of(context).textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                searching ? 'Không tìm thấy thẻ' : 'Bộ thẻ chưa có thẻ nào',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      key: const Key('deck-card-list'),
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: cards.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final card = cards[index];
        final hasSource = _hasSource(card);
        return _DeckCardItem(
          card: card,
          hasSource: hasSource,
          onViewSource: hasSource ? () => _viewSource(card) : null,
          onDelete: () => _deleteCard(card),
          onEdit: () => _editCard(card),
          onReview: () => _review(card),
        );
      },
    );
  }
}

class _DeckCardItem extends StatelessWidget {
  const _DeckCardItem({
    required this.card,
    required this.hasSource,
    required this.onViewSource,
    required this.onDelete,
    required this.onEdit,
    required this.onReview,
  });

  final CardEntity card;
  final bool hasSource;
  final VoidCallback? onViewSource;
  final VoidCallback onDelete;
  final VoidCallback onEdit, onReview;

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);
    final back = card.back.trim();
    final secondaryContent = back.isNotEmpty
        ? back
        : card.explanation?.trim() ?? '';
    final secondaryLabel = back.isNotEmpty ? 'Mặt sau' : 'Nội dung chính';

    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: palette.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surfaceMuted,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    card.type.displayName,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                for (final tag in card.tags) Chip(label: Text(tag)),
                if (!hasSource) const Text('Không có nguồn'),
                if (hasSource)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.link_rounded,
                        size: 16,
                        color: palette.secondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Có nguồn',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: palette.secondary),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              card.front.trim().isEmpty
                  ? 'Chưa có nội dung mặt trước'
                  : card.front,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              secondaryContent.isEmpty
                  ? 'Chưa có nội dung mặt sau'
                  : '$secondaryLabel: $secondaryContent',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (card.options.isNotEmpty)
              for (final o in card.options) Text('${o.optionId}: ${o.text}'),
            if (card.explanation != null)
              Text('Giải thích: ${card.explanation}'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (hasSource)
                  OutlinedButton.icon(
                    onPressed: onViewSource,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Xem nguồn'),
                  ),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Sửa thẻ'),
                ),
                TextButton.icon(
                  onPressed: onReview,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Ôn thẻ'),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(foregroundColor: palette.error),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Xóa thẻ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
