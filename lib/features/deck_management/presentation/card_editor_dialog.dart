import 'package:flutter/material.dart';

import '../domain/deck_models.dart';
import '../domain/deck_repository.dart';
import '../../material_generation/domain/material_generation_models.dart';

class CardEditorDialog extends StatefulWidget {
  const CardEditorDialog({
    super.key,
    required this.repository,
    required this.deckId,
    this.card,
  });
  final DeckRepository repository;
  final String deckId;
  final CardEntity? card;
  static Future<bool> show(
    BuildContext context, {
    required DeckRepository repository,
    required String deckId,
    CardEntity? card,
  }) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CardEditorDialog(
          repository: repository,
          deckId: deckId,
          card: card,
        ),
      ) ??
      false;
  @override
  State<CardEditorDialog> createState() => _CardEditorDialogState();
}

class _CardEditorDialogState extends State<CardEditorDialog> {
  late CardType _type = widget.card?.type ?? CardType.basic;
  late final _front = TextEditingController(text: widget.card?.front);
  late final _back = TextEditingController(text: widget.card?.back);
  late final _explanation = TextEditingController(
    text: widget.card?.explanation,
  );
  late final _tags = TextEditingController(text: widget.card?.tags.join(', '));
  late final _options = {
    for (final id in ['A', 'B', 'C', 'D'])
      id: TextEditingController(
        text: widget.card?.options
            .where((o) => o.optionId == id)
            .firstOrNull
            ?.text,
      ),
  };
  late String _correct = widget.card?.correctOptionId ?? 'A';
  Map<String, String> _errors = {};
  String? _storageError;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_front, _back, _explanation, _tags, ..._options.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final content = CardContent(
      type: _type,
      front: _front.text.trim(),
      back: _back.text.trim(),
      tags: _tags.text.split(RegExp(r'[,;\n]')),
      options: _type == CardType.mcq
          ? [
              for (final e in _options.entries)
                McqOption(optionId: e.key, text: e.value.text.trim()),
            ]
          : const [],
      correctOptionId: _type == CardType.mcq ? _correct : null,
      explanation: _type == CardType.mcq ? _explanation.text.trim() : null,
    );
    setState(() {
      _errors = content.errors;
      _storageError = null;
    });
    if (_errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      if (widget.card == null) {
        await widget.repository.createManualCard(
          deckId: widget.deckId,
          content: content,
        );
      } else {
        await widget.repository.updateCard(widget.card!.id, content: content);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _storageError =
              'Không thể lưu thẻ. Nội dung vẫn được giữ để thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String key,
    String label,
    TextEditingController c, {
    int lines = 2,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: Key('card-editor-$key'),
      controller: c,
      enabled: !_busy,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        errorText: _errors[key],
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.card == null ? 'Tạo thẻ thủ công' : 'Sửa thẻ'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.card == null) ...[
                DropdownButtonFormField<CardType>(
                  key: const Key('card-editor-type'),
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Loại thẻ'),
                  items: [
                    for (final t in CardType.values)
                      DropdownMenuItem(value: t, child: Text(t.wireName)),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _type = v!;
                          _errors = {};
                        }),
                ),
                const SizedBox(height: 12),
              ],
              _field(
                'front',
                _type == CardType.cloze ? 'Câu chứa [...]' : 'Câu hỏi',
                _front,
                lines: 3,
              ),
              if (_type == CardType.mcq) ...[
                for (final e in _options.entries)
                  _field(e.key, 'Lựa chọn ${e.key}', e.value),
                if (_errors['options'] != null) Text(_errors['options']!),
                DropdownButtonFormField<String>(
                  key: const Key('card-editor-correct'),
                  initialValue: _correct,
                  decoration: InputDecoration(
                    labelText: 'Đáp án đúng',
                    errorText: _errors['correctOptionId'],
                  ),
                  items: [
                    for (final id in _options.keys)
                      DropdownMenuItem(value: id, child: Text(id)),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _correct = v!),
                ),
                const SizedBox(height: 12),
                _field('explanation', 'Giải thích', _explanation),
              ] else
                _field('back', 'Đáp án', _back),
              _field('tags', 'Nhãn (ngăn cách bằng dấu phẩy)', _tags, lines: 1),
              if (widget.card?.hasSource ?? false)
                Text('Nguồn đã lưu: “${widget.card!.sourceQuote}”')
              else
                const Text('Thẻ thủ công không có nguồn tài liệu.'),
              if (_storageError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _storageError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('card-editor-save'),
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Đang lưu...' : 'Lưu'),
        ),
      ],
    ),
  );
}
