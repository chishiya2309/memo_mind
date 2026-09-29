import 'dart:io';

import 'package:flutter/material.dart';

import '../../../shared/theme/memo_theme.dart';
import '../../document_import/domain/document_import_models.dart';
import '../../ocr_editor/domain/ocr_models.dart';

class SourceInspectionModal extends StatelessWidget {
  const SourceInspectionModal({
    super.key,
    required this.documentTitle,
    required this.sourcePage,
    required this.sourceBlock,
    required this.sourceQuote,
    this.sourcePageFile,
  });

  final String documentTitle;
  final SourcePage? sourcePage;
  final SourceBlock? sourceBlock;
  final String sourceQuote;
  final File? sourcePageFile;

  static Future<void> show(
    BuildContext context, {
    required String documentTitle,
    required SourcePage? sourcePage,
    required SourceBlock? sourceBlock,
    required String sourceQuote,
    File? sourcePageFile,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SourceInspectionModal(
        documentTitle: documentTitle,
        sourcePage: sourcePage,
        sourceBlock: sourceBlock,
        sourceQuote: sourceQuote,
        sourcePageFile: sourcePageFile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Container(
      height: size.height * 0.85,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: palette.outline.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(
                  Icons.visibility_rounded,
                  color: palette.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Đối chiếu nguồn dẫn chứng',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Trang ${sourcePage?.pageNumber ?? sourceBlock?.pageNumber ?? 1} • $documentTitle',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 16),

          // Visual page viewer with bounding box highlight
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  color: palette.surfaceMuted,
                  width: double.infinity,
                  child: InteractiveViewer(
                    maxScale: 3.0,
                    child: Center(child: _buildPageContent(palette)),
                  ),
                ),
              ),
            ),
          ),

          // Source quote card
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.hero,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: palette.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.format_quote_rounded,
                        size: 18,
                        color: palette.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Trích dẫn nguồn:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: palette.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '"$sourceQuote"',
                    style: TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      color: palette.text,
                      height: 1.4,
                    ),
                  ),
                  if (sourceBlock != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Khối nguồn #${sourceBlock!.orderIndex + 1} • Trang ${sourceBlock!.pageNumber}',
                      style: TextStyle(fontSize: 11, color: palette.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageContent(MemoPalette palette) {
    final box = sourceBlock?.boundingBox;

    if (sourcePageFile != null &&
        sourcePageFile!.existsSync() &&
        sourcePage != null) {
      final width = sourcePage!.normalizedAsset?.width ?? sourcePage!.width;
      final height = sourcePage!.normalizedAsset?.height ?? sourcePage!.height;
      return AspectRatio(
        aspectRatio: width / height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(sourcePageFile!, fit: BoxFit.fill),
            if (box != null && sourceBlock!.hasValidBox && box.isValid)
              CustomPaint(
                painter: _BoundingBoxHighlightPainter(
                  box: box,
                  color: palette.warning,
                ),
              ),
          ],
        ),
      );
    }
    // Fallback if image file is not loaded: display simulated page with highlighted block text
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_rounded,
              size: 48,
              color: palette.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Khối văn bản nguồn:',
              style: TextStyle(
                fontSize: 12,
                color: palette.textMuted,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.warning, width: 2),
              ),
              child: Text(
                sourceBlock?.normalizedText ?? sourceQuote,
                style: const TextStyle(fontSize: 13, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoundingBoxHighlightPainter extends CustomPainter {
  const _BoundingBoxHighlightPainter({required this.box, required this.color});

  final NormalizedBoundingBox box;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      box.left * size.width,
      box.top * size.height,
      box.width * size.width,
      box.height * size.height,
    );

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxHighlightPainter oldDelegate) =>
      oldDelegate.box != box || oldDelegate.color != color;
}
