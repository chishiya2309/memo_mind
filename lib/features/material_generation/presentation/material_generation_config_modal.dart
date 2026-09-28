import 'package:flutter/material.dart';

import '../../../shared/theme/memo_theme.dart';
import '../../ocr_editor/domain/ocr_models.dart';
import '../domain/material_generation_models.dart';

typedef MaterialGenerationConfig = ({
  FlashcardFormat format,
  int count,
  Set<String> selectedBlockIds,
});

class MaterialGenerationConfigModal extends StatefulWidget {
  const MaterialGenerationConfigModal({
    super.key,
    required this.documentTitle,
    required this.verifiedBlocks,
  });

  final String documentTitle;
  final List<SourceBlock> verifiedBlocks;

  static Future<MaterialGenerationConfig?> show(
    BuildContext context, {
    required String documentTitle,
    required List<SourceBlock> verifiedBlocks,
  }) {
    return showModalBottomSheet<MaterialGenerationConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MaterialGenerationConfigModal(
        documentTitle: documentTitle,
        verifiedBlocks: verifiedBlocks,
      ),
    );
  }

  @override
  State<MaterialGenerationConfigModal> createState() => _MaterialGenerationConfigModalState();
}

class _MaterialGenerationConfigModalState extends State<MaterialGenerationConfigModal> {
  FlashcardFormat _format = FlashcardFormat.mixed;
  int _cardCount = 5;
  final bool _useAllBlocks = true;
  late final Set<String> _selectedBlockIds;

  @override
  void initState() {
    super.initState();
    _selectedBlockIds = widget.verifiedBlocks.map((b) => b.blockId).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
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

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: palette.aiContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.auto_awesome_rounded, color: palette.aiAccent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tạo Flashcard bằng AI',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.documentTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Section 1: Card Format
          Text(
            'Loại flashcard',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<FlashcardFormat>(
            segments: const [
              ButtonSegment(
                value: FlashcardFormat.qa,
                label: Text('Hỏi – đáp'),
                icon: Icon(Icons.question_answer_outlined, size: 16),
              ),
              ButtonSegment(
                value: FlashcardFormat.cloze,
                label: Text('Điền khuyết'),
                icon: Icon(Icons.edit_note_rounded, size: 16),
              ),
              ButtonSegment(
                value: FlashcardFormat.mixed,
                label: Text('Cả hai'),
                icon: Icon(Icons.all_inclusive_rounded, size: 16),
              ),
            ],
            selected: {_format},
            onSelectionChanged: (set) => setState(() => _format = set.first),
          ),
          const SizedBox(height: 16),

          // Section 2: Card Count
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Số lượng flashcard',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$_cardCount thẻ',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: palette.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [3, 5, 8, 10].map((count) {
              final isSelected = _cardCount == count;
              return ChoiceChip(
                label: Text('$count thẻ'),
                selected: isSelected,
                onSelected: (_) => setState(() => _cardCount = count),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Section 3: Source scope
          Row(
            children: [
              Icon(Icons.menu_book_rounded, size: 18, color: palette.textMuted),
              const SizedBox(width: 8),
              Text(
                'Nguồn: ${widget.verifiedBlocks.length} khối văn bản đã xác nhận',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Confirm Button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: palette.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text(
                'Tạo Flashcard',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              onPressed: () {
                Navigator.of(context).pop((
                  format: _format,
                  count: _cardCount,
                  selectedBlockIds: _selectedBlockIds,
                ));
              },
            ),
          ),
        ],
      ),
    );
  }
}
