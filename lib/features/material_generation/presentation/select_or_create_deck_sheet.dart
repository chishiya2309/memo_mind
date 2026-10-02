import 'package:flutter/material.dart';

import '../../../shared/theme/memo_theme.dart';
import '../../deck_management/domain/deck_models.dart';
import '../../deck_management/domain/deck_repository.dart';
import '../../home/domain/home_dashboard_data.dart';

class SelectOrCreateDeckSheet extends StatefulWidget {
  const SelectOrCreateDeckSheet({
    super.key,
    required this.deckRepository,
    required this.cardCountToSave,
  });

  final DeckRepository deckRepository;
  final int cardCountToSave;

  static Future<Deck?> show(
    BuildContext context, {
    required DeckRepository deckRepository,
    required int cardCountToSave,
  }) {
    return showModalBottomSheet<Deck>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SelectOrCreateDeckSheet(
        deckRepository: deckRepository,
        cardCountToSave: cardCountToSave,
      ),
    );
  }

  @override
  State<SelectOrCreateDeckSheet> createState() =>
      _SelectOrCreateDeckSheetState();
}

class _SelectOrCreateDeckSheetState extends State<SelectOrCreateDeckSheet> {
  late Future<List<Deck>> _decksFuture;
  bool _isCreatingNew = false;
  final _newTitleController = TextEditingController();
  final _newDescController = TextEditingController();
  final _newTagsController = TextEditingController();
  bool _saving = false;
  DeckTone _selectedTone = DeckTone.indigo;
  String? _createError;

  @override
  void initState() {
    super.initState();
    _loadDecks();
  }

  void _loadDecks() {
    _decksFuture = widget.deckRepository.getDecks();
  }

  @override
  void dispose() {
    _newTitleController.dispose();
    _newDescController.dispose();
    _newTagsController.dispose();
    super.dispose();
  }

  Future<void> _createAndSelectDeck() async {
    if (_saving) return;
    final title = _newTitleController.text.trim();
    if (title.isEmpty) {
      setState(() => _createError = 'Vui lòng nhập tên bộ thẻ.');
      return;
    }

    setState(() {
      _saving = true;
      _createError = null;
    });
    try {
      final deck = await widget.deckRepository.createDeck(
        title: title,
        description: _newDescController.text.trim().isEmpty
            ? null
            : _newDescController.text.trim(),
        tone: _selectedTone,
        tags: CardContent.normalizeTags(
          _newTagsController.text.split(RegExp(r'[,;\n]')),
        ),
      );
      if (mounted) {
        Navigator.of(context).pop(deck);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _createError = 'Không thể tạo deck. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);
    final theme = Theme.of(context);

    final media = MediaQuery.of(context);
    return PopScope(
      canPop: !_saving,
      child: AbsorbPointer(
        absorbing: _saving,
        child: Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: Material(
            color: palette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (media.size.height * 0.85 - media.viewInsets.bottom)
                    .clamp(0.0, media.size.height),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.outline.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Lưu vào Bộ thẻ (Deck)',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                widget.cardCountToSave == 0
                                    ? 'Chọn deck đích'
                                    : 'Lưu ${widget.cardCountToSave} thẻ đã chấp nhận',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: palette.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (_isCreatingNew)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: _newTagsController,
                            decoration: const InputDecoration(
                              labelText: 'Nhãn (ngăn cách bằng dấu phẩy)',
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Form tạo Deck mới (Luồng 31a)
                          Text(
                            'Tạo bộ thẻ mới',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_createError != null) ...[
                            Text(
                              _createError!,
                              style: TextStyle(
                                color: palette.error,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                          TextField(
                            controller: _newTitleController,
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: 'Tên bộ thẻ *',
                              hintText: 'Ví dụ: Lịch sử đại cương',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _newDescController,
                            decoration: InputDecoration(
                              labelText: 'Mô tả (tùy chọn)',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                'Màu sắc: ',
                                style: TextStyle(
                                  color: palette.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: DeckTone.values.map((tone) {
                                      final isSelected = _selectedTone == tone;
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: InkWell(
                                          onTap: () => setState(
                                            () => _selectedTone = tone,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: Container(
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: MemoPalette.deckPastel(
                                                context,
                                                tone.index,
                                              ),
                                              shape: BoxShape.circle,
                                              border: isSelected
                                                  ? Border.all(
                                                      color: palette.primary,
                                                      width: 2.5,
                                                    )
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _saving
                                      ? null
                                      : () => setState(
                                          () => _isCreatingNew = false,
                                        ),
                                  child: const Text('Hủy'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: _saving
                                      ? null
                                      : _createAndSelectDeck,
                                  child: const Text('Tạo & Lưu'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    else ...[
                      // Nút mở form tạo deck mới
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Tạo bộ thẻ mới'),
                        onPressed: () => setState(() => _isCreatingNew = true),
                      ),
                      const SizedBox(height: 12),

                      // Danh sách các deck có sẵn
                      FutureBuilder<List<Deck>>(
                        future: _decksFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (snapshot.hasError) {
                            return Column(
                              children: [
                                const Text('Không thể tải bộ thẻ.'),
                                TextButton(
                                  onPressed: () => setState(_loadDecks),
                                  child: const Text('Thử lại'),
                                ),
                              ],
                            );
                          }
                          final decks = snapshot.data ?? [];
                          if (decks.isEmpty) {
                            return Center(
                              child: Text(
                                'Chưa có bộ thẻ nào. Hãy bấm "Tạo bộ thẻ mới" ở trên.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: palette.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            );
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: decks.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final deck = decks[index];
                              return ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: palette.outline.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                                tileColor: palette.surfaceMuted,
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: MemoPalette.deckPastel(
                                      context,
                                      deck.tone.index,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.folder_copy_rounded,
                                    color: palette.primary,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  deck.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${deck.cardCount} thẻ'
                                  '${deck.description != null ? ' • ${deck.description}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () => Navigator.of(context).pop(deck),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
