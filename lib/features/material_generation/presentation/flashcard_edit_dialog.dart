import 'package:flutter/material.dart';

import '../../ocr_editor/domain/ocr_models.dart';
import '../domain/material_generation_models.dart';
import '../domain/material_validator.dart';

class FlashcardEditDialog extends StatefulWidget {
  const FlashcardEditDialog({
    super.key,
    required this.card,
    required this.sourceBlock,
    required this.onSaved,
  });
  final MaterialDraft card;
  final SourceBlock? sourceBlock;
  final ValueChanged<MaterialDraft> onSaved;
  static Future<void> show(
    BuildContext context, {
    required MaterialDraft card,
    required SourceBlock? sourceBlock,
    required ValueChanged<MaterialDraft> onSaved,
  }) => showDialog<void>(
    context: context,
    builder: (_) => FlashcardEditDialog(
      card: card,
      sourceBlock: sourceBlock,
      onSaved: onSaved,
    ),
  );
  @override
  State<FlashcardEditDialog> createState() => _FlashcardEditDialogState();
}

class _FlashcardEditDialogState extends State<FlashcardEditDialog> {
  late final _front = TextEditingController(text: widget.card.front);
  late final _back = TextEditingController(text: widget.card.back);
  late final _explanation = TextEditingController(
    text: widget.card.explanation,
  );
  late final _options = {
    for (final id in ['A', 'B', 'C', 'D'])
      id: TextEditingController(
        text: widget.card.options
            .where((o) => o.optionId == id)
            .firstOrNull
            ?.text,
      ),
  };
  late String? _correct = widget.card.correctOptionId;
  Map<String, String> _errors = {};
  @override
  void dispose() {
    for (final controller in [
      _front,
      _back,
      _explanation,
      ..._options.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final card = widget.card.copyWith(
      front: _front.text.trim(),
      back: _back.text.trim(),
      options: widget.card.type == CardType.mcq
          ? [
              for (final entry in _options.entries)
                McqOption(optionId: entry.key, text: entry.value.text.trim()),
            ]
          : null,
      correctOptionId: _correct,
      explanation: widget.card.type == CardType.mcq
          ? _explanation.text.trim()
          : null,
      status: DraftCardStatus.pending,
      isEdited: true,
    );
    final errors = MaterialValidator.errors(card);
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    try {
      MaterialValidator.validate(
        card,
        sourceBlock: widget.sourceBlock,
        documentId: widget.sourceBlock?.documentId ?? '',
      );
      widget.onSaved(card);
      Navigator.pop(context);
    } on MaterialGenerationFailure catch (e) {
      setState(() => _errors = {'source': e.message});
    }
  }

  Widget _field(
    String key,
    String label,
    TextEditingController controller, {
    int lines = 2,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: Key('edit-$key'),
      controller: controller,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        errorText: _errors[key],
        border: const OutlineInputBorder(),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Chỉnh sửa học liệu'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(
              'front',
              widget.card.type == CardType.cloze ? 'Câu chứa [...]' : 'Câu hỏi',
              _front,
              lines: 3,
            ),
            if (widget.card.type == CardType.mcq) ...[
              for (final entry in _options.entries)
                _field(entry.key, 'Lựa chọn ${entry.key}', entry.value),
              DropdownButtonFormField<String>(
                initialValue: _correct,
                decoration: InputDecoration(
                  labelText: 'Đáp án đúng',
                  errorText: _errors['correctOptionId'],
                ),
                items: [
                  for (final id in _options.keys)
                    DropdownMenuItem(value: id, child: Text(id)),
                ],
                onChanged: (value) => setState(() => _correct = value),
              ),
              const SizedBox(height: 12),
              _field('explanation', 'Giải thích', _explanation),
            ] else
              _field('back', 'Đáp án', _back),
            if (_errors['source'] != null)
              Text(
                _errors['source']!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Text('Nguồn: “${widget.card.sourceQuote}”'),
            const SizedBox(height: 8),
            const Text(
              'Sau khi sửa, hãy đối chiếu nguồn và chấp nhận lại thẻ.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(onPressed: _save, child: const Text('Lưu thay đổi')),
    ],
  );
}
