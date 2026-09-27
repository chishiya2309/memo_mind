import 'package:flutter/material.dart';

import '../../../../shared/theme/memo_theme.dart';

class GeminiConsentDialog extends StatefulWidget {
  const GeminiConsentDialog({super.key});

  @override
  State<GeminiConsentDialog> createState() => _GeminiConsentDialogState();
}

class _GeminiConsentDialogState extends State<GeminiConsentDialog> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.auto_awesome, color: palette.primary, size: 24),
          const SizedBox(width: 10),
          const Expanded(child: Text('Cải thiện bằng Gemini AI')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hệ thống sẽ chỉ cắt riêng vùng ảnh của đoạn văn bản này và gửi tới mô hình Gemini Vision để trích xuất nội dung khó đọc.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.privacy_tip_outlined, color: palette.warning, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Lưu ý quyền riêng tư: Dữ liệu gửi qua dịch vụ miễn phí có thể được Google sử dụng để cải thiện sản phẩm. Vui lòng không gửi tài liệu chứa dữ liệu nhạy cảm hoặc bí mật cá nhân.',
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.warning,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Tôi hiểu và đồng ý tải vùng ảnh này lên AI',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              value: _agreed,
              onChanged: (val) => setState(() => _agreed = val ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('confirm-gemini-consent-btn'),
          onPressed: _agreed ? () => Navigator.pop(context, true) : null,
          child: const Text('Tiếp tục'),
        ),
      ],
    );
  }
}

class GeminiSuggestionDialog extends StatelessWidget {
  const GeminiSuggestionDialog({
    super.key,
    required this.currentText,
    required this.suggestedText,
  });

  final String currentText;
  final String suggestedText;

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);

    return AlertDialog(
      title: const Text('Đề xuất nhận dạng từ AI'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bản nhận dạng hiện tại:',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.hero,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                currentText.isEmpty ? '(Không có nội dung)' : currentText,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Đề xuất từ Gemini Vision:',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: palette.primary,
                  ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: palette.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                suggestedText,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Giữ nguyên bản cũ'),
        ),
        FilledButton(
          key: const Key('accept-gemini-suggestion-btn'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Áp dụng đề xuất'),
        ),
      ],
    );
  }
}
