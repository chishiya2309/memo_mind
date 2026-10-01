import 'package:flutter/material.dart';

import '../../domain/deck_models.dart';

class DeckFormData {
  const DeckFormData({required this.title, required this.tags});

  final String title;
  final List<String> tags;
}

class DeckFormDialog extends StatefulWidget {
  const DeckFormDialog({super.key, this.deck});

  final Deck? deck;

  static Future<DeckFormData?> show(BuildContext context, {Deck? deck}) =>
      showDialog<DeckFormData>(
        context: context,
        builder: (context) => DeckFormDialog(deck: deck),
      );

  @override
  State<DeckFormDialog> createState() => _DeckFormDialogState();
}

class _DeckFormDialogState extends State<DeckFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _tagController;
  late final List<String> _tags;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.deck?.title ?? '');
    _tagController = TextEditingController();
    _tags = [...?widget.deck?.tags];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _addTags(String value) {
    final values = value
        .split(RegExp(r'[,;\n]'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty && !_tags.contains(tag));
    setState(() {
      _tags.addAll(values);
      _tagController.clear();
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _addTags(_tagController.text);
    Navigator.of(context).pop(
      DeckFormData(
        title: _titleController.text.trim(),
        tags: List.unmodifiable(_tags),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.deck != null;
    return AlertDialog(
      title: Text(editing ? 'Sửa bộ thẻ' : 'Tạo bộ thẻ'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _titleController,
                  autofocus: !editing,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Tên bộ thẻ'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Tên bộ thẻ không được để trống.'
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tagController,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Thêm tag',
                    suffixIcon: IconButton(
                      tooltip: 'Thêm tag',
                      onPressed: () => _addTags(_tagController.text),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ),
                  onSubmitted: _addTags,
                ),
                if (_tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final tag in _tags)
                        InputChip(
                          label: Text(tag),
                          onDeleted: () => setState(() => _tags.remove(tag)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: Text(editing ? 'Lưu' : 'Tạo')),
      ],
    );
  }
}
