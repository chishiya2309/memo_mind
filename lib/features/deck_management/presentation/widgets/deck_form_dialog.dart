import 'package:flutter/material.dart';

import '../../domain/deck_models.dart';

class DeckFormData {
  const DeckFormData({required this.title, required this.tags});

  final String title;
  final List<String> tags;
}

class DeckFormDialog extends StatefulWidget {
  const DeckFormDialog({super.key, this.deck, this.onSave});

  final Deck? deck;
  final Future<void> Function(DeckFormData)? onSave;

  static Future<DeckFormData?> show(
    BuildContext context, {
    Deck? deck,
    Future<void> Function(DeckFormData)? onSave,
  }) => showDialog<DeckFormData>(
    context: context,
    builder: (context) => DeckFormDialog(deck: deck, onSave: onSave),
  );

  @override
  State<DeckFormDialog> createState() => _DeckFormDialogState();
}

class _DeckFormDialogState extends State<DeckFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _tagController;
  late final List<String> _tags;
  bool _saving = false;
  String? _error;

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

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    _addTags(_tagController.text);
    final form = DeckFormData(
      title: _titleController.text.trim(),
      tags: CardContent.normalizeTags(_tags),
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave?.call(form);
      if (mounted) Navigator.of(context).pop(form);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không thể lưu thay đổi. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.deck != null;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(editing ? 'Sửa bộ thẻ' : 'Tạo bộ thẻ'),
        content: SizedBox(
          width: 380,
          child: AbsorbPointer(
            absorbing: _saving,
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    TextFormField(
                      controller: _titleController,
                      autofocus: !editing,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Tên bộ thẻ',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
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
                              onDeleted: () =>
                                  setState(() => _tags.remove(tag)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(editing ? 'Lưu' : 'Tạo'),
          ),
        ],
      ),
    );
  }
}
