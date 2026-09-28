import 'package:flutter/material.dart';

import '../../../shared/theme/memo_theme.dart';
import '../../ocr_editor/domain/ocr_models.dart';
import '../domain/flashcard_verifier.dart';
import '../domain/material_generation_models.dart';

class FlashcardEditDialog extends StatefulWidget {
  const FlashcardEditDialog({
    super.key,
    required this.card,
    required this.sourceBlock,
    required this.onSaved,
  });

  final FlashcardDraft card;
  final SourceBlock? sourceBlock;
  final ValueChanged<FlashcardDraft> onSaved;

  static Future<void> show(
    BuildContext context, {
    required FlashcardDraft card,
    required SourceBlock? sourceBlock,
    required ValueChanged<FlashcardDraft> onSaved,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => FlashcardEditDialog(
        card: card,
        sourceBlock: sourceBlock,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<FlashcardEditDialog> createState() => _FlashcardEditDialogState();
}

class _FlashcardEditDialogState extends State<FlashcardEditDialog> {
  late final TextEditingController _questionController;
  late final TextEditingController _answerController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController(text: widget.card.question);
    _answerController = TextEditingController(text: widget.card.answer);
  }

  @override
  void dispose() {
    _questionController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  void _save() {
    setState(() => _errorMessage = null);
    try {
      final updated = FlashcardVerifier.verifyEditedCard(
        card: widget.card,
        sourceBlock: widget.sourceBlock,
        newQuestion: _questionController.text,
        newAnswer: _answerController.text,
      );
      widget.onSaved(updated);
      Navigator.of(context).pop();
    } on FormatException catch (e) {
      setState(() => _errorMessage = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);
    final theme = Theme.of(context);
    final isCloze = widget.card.format == FlashcardFormat.cloze;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: palette.surface,
      title: Row(
        children: [
          Icon(Icons.edit_note_rounded, color: palette.primary, size: 24),
          const SizedBox(width: 8),
          Text(
            'Chỉnh sửa Flashcard',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: palette.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: palette.error.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: palette.error, fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Question
            Text(
              isCloze ? 'Câu điền khuyết (chứa "[...]"): ' : 'Câu hỏi:',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _questionController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: isCloze
                    ? 'Ví dụ: Thủ đô của Việt Nam là [...]'
                    : 'Nhập câu hỏi...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            if (isCloze) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Chèn [...]'),
                  onPressed: () {
                    final text = _questionController.text;
                    final sel = _questionController.selection;
                    final newText = sel.isValid
                        ? text.replaceRange(sel.start, sel.end, '[...]')
                        : '$text [...]';
                    _questionController.text = newText;
                  },
                ),
              ),
            ],
            const SizedBox(height: 14),

            // Answer
            Text(
              isCloze ? 'Từ / cụm từ cần điền (đáp án):' : 'Đáp án:',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _answerController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Nhập đáp án...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 12),

            // Source context hint
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Lưu ý (BR07-08): Nội dung sau khi sửa vẫn cần có căn cứ trong đoạn trích nguồn: "${widget.card.sourceQuote}"',
                style: TextStyle(fontSize: 11, color: palette.textMuted),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Lưu thay đổi'),
        ),
      ],
    );
  }
}
