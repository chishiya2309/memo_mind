import 'package:flutter/material.dart';

import '../../../../shared/theme/memo_theme.dart';

class ConfirmDeleteDialog extends StatelessWidget {
  const ConfirmDeleteDialog({super.key, required this.deckTitle});

  final String deckTitle;

  static Future<bool> show(
    BuildContext context, {
    required String deckTitle,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => ConfirmDeleteDialog(deckTitle: deckTitle),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);
    return AlertDialog(
      title: const Text('Xóa bộ thẻ?'),
      content: Text(
        'Bộ thẻ “$deckTitle” và các thẻ bên trong sẽ được ẩn khỏi thư viện và phiên ôn tập. Lịch sử ôn và nguồn tài liệu được giữ lại.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: palette.error),
          child: const Text('Xóa bộ thẻ'),
        ),
      ],
    );
  }
}
