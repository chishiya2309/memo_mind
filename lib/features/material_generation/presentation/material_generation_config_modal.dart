import 'package:flutter/material.dart';

import '../../deck_management/domain/deck_models.dart';
import '../../deck_management/domain/deck_repository.dart';
import '../../ocr_editor/domain/ocr_models.dart';
import '../domain/material_generation_models.dart';
import 'select_or_create_deck_sheet.dart';

typedef GenerationSelection = ({MaterialGenerationConfig config, Deck deck});

class MaterialGenerationConfigModal extends StatefulWidget {
  const MaterialGenerationConfigModal({
    super.key,
    required this.documentId,
    required this.documentTitle,
    required this.verifiedBlocks,
    required this.deckRepository,
  });
  final String documentId, documentTitle;
  final List<SourceBlock> verifiedBlocks;
  final DeckRepository deckRepository;
  static Future<GenerationSelection?> show(
    BuildContext context, {
    required String documentId,
    required String documentTitle,
    required List<SourceBlock> verifiedBlocks,
    required DeckRepository deckRepository,
  }) => showModalBottomSheet<GenerationSelection>(
    context: context,
    isScrollControlled: true,
    builder: (_) => MaterialGenerationConfigModal(
      documentId: documentId,
      documentTitle: documentTitle,
      verifiedBlocks: verifiedBlocks,
      deckRepository: deckRepository,
    ),
  );
  @override
  State<MaterialGenerationConfigModal> createState() =>
      _MaterialGenerationConfigModalState();
}

class _MaterialGenerationConfigModalState
    extends State<MaterialGenerationConfigModal> {
  final _types = <CardType>{CardType.basic, CardType.cloze};
  final _count = TextEditingController(text: '10');
  QuantityMode _mode = QuantityMode.auto;
  late final Set<String> _blocks = widget.verifiedBlocks
      .map((b) => b.blockId)
      .toSet();
  Deck? _deck;
  String? _error;
  bool _choosingDeck = false;
  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  Future<void> _chooseDeck() async {
    if (_choosingDeck) return;
    setState(() => _choosingDeck = true);
    try {
      final deck = await SelectOrCreateDeckSheet.show(
        context,
        deckRepository: widget.deckRepository,
        cardCountToSave: 0,
      );
      if (mounted && deck != null) setState(() => _deck = deck);
    } finally {
      if (mounted) setState(() => _choosingDeck = false);
    }
  }

  void _submit() {
    final count = int.tryParse(_count.text);
    String? error;
    if (_types.isEmpty) {
      error = 'Chọn ít nhất một loại học liệu.';
    } else if (_mode == QuantityMode.manual &&
        (count == null || count < _types.length || count > 30)) {
      error =
          'Số lượng phải từ ${_types.length} đến 30, đủ cho các loại đã chọn.';
    } else if (_blocks.isEmpty) {
      error = 'Chọn ít nhất một đoạn nguồn.';
    } else if (widget.verifiedBlocks
            .where((b) => _blocks.contains(b.blockId))
            .fold<int>(0, (n, b) => n + b.normalizedText.length) >
        100000) {
      error = 'Nguồn vượt 100.000 ký tự. Vui lòng chọn ít đoạn hơn.';
    } else if (_deck == null) {
      error = 'Chọn deck đích trước khi tạo học liệu.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, (
      config: MaterialGenerationConfig(
        documentId: widget.documentId,
        types: Set.unmodifiable(_types),
        quantityMode: _mode,
        desiredCount: _mode == QuantityMode.manual ? count : null,
        selectedBlockIds: Set.unmodifiable(_blocks),
      ),
      deck: _deck!,
    ));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          24,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Tạo học liệu', style: Theme.of(context).textTheme.titleLarge),
            Text(widget.documentTitle),
            const SizedBox(height: 20),
            const Text('Loại học liệu'),
            Wrap(
              spacing: 8,
              children: [
                for (final type in CardType.values)
                  FilterChip(
                    label: Text(type.displayName),
                    selected: _types.contains(type),
                    onSelected: (selected) => setState(
                      () => selected ? _types.add(type) : _types.remove(type),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<QuantityMode>(
              segments: const [
                ButtonSegment(value: QuantityMode.auto, label: Text('Tự động')),
                ButtonSegment(
                  value: QuantityMode.manual,
                  label: Text('Tùy chỉnh'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (m) => setState(() => _mode = m.first),
            ),
            const SizedBox(height: 10),
            if (_mode == QuantityMode.auto)
              const Text(
                'AI chọn số thẻ theo các ý đáng học trong nguồn, tối đa 20 thẻ.',
              )
            else
              TextField(
                key: const Key('material-count'),
                controller: _count,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tổng số thẻ mong muốn (1–30)',
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Kết quả có thể ít hơn nếu nguồn không đủ hoặc thẻ không đạt kiểm tra.',
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Nguồn: ${_blocks.length} đoạn đã xác nhận'),
              children: [
                for (final block in widget.verifiedBlocks)
                  CheckboxListTile(
                    value: _blocks.contains(block.blockId),
                    title: Text(
                      'Trang ${block.pageNumber} • ${block.normalizedText}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onChanged: (checked) => setState(
                      () => checked == true
                          ? _blocks.add(block.blockId)
                          : _blocks.remove(block.blockId),
                    ),
                  ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined),
              title: Text(_deck?.title ?? 'Chọn deck đích'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _choosingDeck ? null : _chooseDeck,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _choosingDeck ? null : _submit,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Tạo học liệu'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
