import 'package:flutter/material.dart';

import '../../../shared/theme/memo_theme.dart';
import '../domain/deck_models.dart';
import '../../home/domain/home_dashboard_data.dart';
import '../domain/deck_repository.dart';
import 'widgets/confirm_delete_dialog.dart';
import 'widgets/deck_form_dialog.dart';

class LibraryDecksScreen extends StatefulWidget {
  const LibraryDecksScreen({
    super.key,
    required this.repository,
    required this.onOpenDeck,
    this.onOpenDeckAsync,
    this.onChanged,
  });

  final DeckRepository repository;
  final ValueChanged<String> onOpenDeck;
  final Future<void> Function(String)? onOpenDeckAsync;
  final VoidCallback? onChanged;

  @override
  State<LibraryDecksScreen> createState() => _LibraryDecksScreenState();
}

class _LibraryDecksScreenState extends State<LibraryDecksScreen> {
  final _searchController = TextEditingController();
  List<Deck> _decks = const [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadDecks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Deck> get _visibleDecks {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _decks;
    return _decks
        .where(
          (deck) =>
              deck.title.toLowerCase().contains(query) ||
              deck.tags.any((tag) => tag.toLowerCase().contains(query)),
        )
        .toList(growable: false);
  }

  Future<void> _loadDecks() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final decks = await widget.repository.getDecks();
      if (!mounted) return;
      setState(() {
        _decks = decks;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Không thể tải thư viện trên thiết bị.';
        _loading = false;
      });
    }
  }

  Future<void> _openDeck(String id) async {
    if (widget.onOpenDeckAsync != null) {
      await widget.onOpenDeckAsync!(id);
      if (mounted) await _loadDecks();
    } else {
      widget.onOpenDeck(id);
    }
  }

  Future<void> _createDeck() async {
    Deck? created;
    final form = await DeckFormDialog.show(
      context,
      onSave: (data) async {
        created = await widget.repository.createDeck(
          title: data.title,
          tags: data.tags,
        );
      },
    );
    if (form == null || !mounted || created == null) return;
    setState(() => _decks = [created!, ..._decks]);
    widget.onChanged?.call();
  }

  Future<void> _editDeck(Deck deck) async {
    Deck? updated;
    final form = await DeckFormDialog.show(
      context,
      deck: deck,
      onSave: (data) async {
        updated = await widget.repository.updateDeck(
          deck.id,
          title: data.title,
          tags: data.tags,
        );
      },
    );
    if (form == null || !mounted || updated == null) return;
    setState(() {
      _decks = [
        for (final current in _decks)
          current.id == deck.id ? updated! : current,
      ];
    });
    widget.onChanged?.call();
  }

  Future<void> _deleteDeck(Deck deck) async {
    final confirmed = await ConfirmDeleteDialog.show(
      context,
      deckTitle: deck.title,
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.repository.deleteDeck(deck.id);
      if (!mounted) return;
      setState(
        () => _decks = _decks.where((item) => item.id != deck.id).toList(),
      );
      widget.onChanged?.call();
    } catch (_) {
      _showMutationError();
    }
  }

  void _showMutationError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Không thể lưu thay đổi. Vui lòng thử lại.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Thư viện',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton.filledTonal(
                    key: const Key('create-deck'),
                    tooltip: 'Tạo bộ thẻ',
                    onPressed: _createDeck,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('search-decks'),
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Tìm tên bộ thẻ hoặc tag',
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
              Expanded(child: _buildDeckList(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeckList(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadDecks,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }

    final decks = _visibleDecks;
    if (decks.isEmpty) {
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
                searching ? 'Không tìm thấy bộ thẻ' : 'Chưa có bộ thẻ nào',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (!searching) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _createDeck,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Tạo bộ thẻ'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      key: const Key('library-deck-list'),
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: decks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _DeckListItem(
        deck: decks[index],
        onOpen: _openDeck,
        onEdit: _editDeck,
        onDelete: _deleteDeck,
      ),
    );
  }
}

class _DeckListItem extends StatelessWidget {
  const _DeckListItem({
    required this.deck,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final Deck deck;
  final ValueChanged<String> onOpen;
  final ValueChanged<Deck> onEdit;
  final ValueChanged<Deck> onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);
    final toneColor = MemoPalette.deckPastel(context, deck.tone.index);
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: palette.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('library-deck-${deck.id}'),
        onTap: () => onOpen(deck.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: toneColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.style_outlined,
                  color: palette.primaryDark,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deck.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${deck.cardCount} thẻ',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: toneColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: palette.outline),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _toneLabel(deck.tone),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      if (deck.tags.isEmpty)
                        Text(
                          'Chưa có tag',
                          style: Theme.of(context).textTheme.labelSmall,
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final tag in deck.tags)
                              Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 190,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.surfaceMuted,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  tag,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Tùy chọn ${deck.title}',
                onSelected: (value) {
                  if (value == 'edit') onEdit(deck);
                  if (value == 'delete') onDelete(deck);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text('Đổi tên và sửa tags'),
                  ),
                  PopupMenuItem(value: 'delete', child: Text('Xóa bộ thẻ')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _toneLabel(DeckTone tone) => switch (tone) {
    DeckTone.indigo => 'Chàm',
    DeckTone.teal => 'Ngọc lam',
    DeckTone.blue => 'Xanh dương',
    DeckTone.amber => 'Hổ phách',
    DeckTone.rose => 'Hồng',
    DeckTone.violet => 'Tím',
  };
}
