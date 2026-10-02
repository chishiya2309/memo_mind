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
    this.sourcePageNumber,
    this.imageUsesNormalizedCoordinates = true,
    this.warning,
  });
  final String documentTitle, sourceQuote;
  final SourcePage? sourcePage;
  final SourceBlock? sourceBlock;
  final File? sourcePageFile;
  final int? sourcePageNumber;
  final bool imageUsesNormalizedCoordinates;
  final String? warning;

  static Future<void> show(
    BuildContext context, {
    required String documentTitle,
    required SourcePage? sourcePage,
    required SourceBlock? sourceBlock,
    required String sourceQuote,
    File? sourcePageFile,
    int? sourcePageNumber,
    bool imageUsesNormalizedCoordinates = true,
    String? warning,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SourceInspectionModal(
      documentTitle: documentTitle,
      sourcePage: sourcePage,
      sourceBlock: sourceBlock,
      sourceQuote: sourceQuote,
      sourcePageFile: sourcePageFile,
      sourcePageNumber: sourcePageNumber,
      imageUsesNormalizedCoordinates: imageUsesNormalizedCoordinates,
      warning: warning,
    ),
  );

  bool get _validBox {
    final b = sourceBlock?.boundingBox;
    return imageUsesNormalizedCoordinates &&
        sourceBlock != null &&
        sourcePage != null &&
        sourceBlock!.pageId == sourcePage!.pageId &&
        sourceBlock!.documentId == sourcePage!.documentId &&
        sourceBlock!.pageNumber == sourcePage!.pageNumber &&
        !sourceBlock!.isDeleted &&
        sourceBlock!.hasValidBox &&
        b != null &&
        b.left.isFinite &&
        b.top.isFinite &&
        b.width.isFinite &&
        b.height.isFinite &&
        b.left >= 0 &&
        b.top >= 0 &&
        b.width > 0 &&
        b.height > 0 &&
        b.left + b.width <= 1 &&
        b.top + b.height <= 1;
  }

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    final pageNumber =
        sourcePage?.pageNumber ?? sourcePageNumber ?? sourceBlock?.pageNumber;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Đối chiếu nguồn dẫn chứng',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        [
                          if (pageNumber != null) 'Trang $pageNumber',
                          if (documentTitle.isNotEmpty) documentTitle,
                        ].join(' • '),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (warning != null)
                    Text(warning!, key: const Key('source-warning')),
                  _page(p),
                  const SizedBox(height: 16),
                  Text(
                    'Trích dẫn nguồn:',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    '"$sourceQuote"',
                    key: const Key('source-quote'),
                  ),
                  if (sourceBlock != null) ...[
                    const SizedBox(height: 12),
                    Text('Khối nguồn #${sourceBlock!.orderIndex + 1}'),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _page(MemoPalette p) {
    final file = sourcePageFile;
    final page = sourcePage;
    if (file == null || page == null || !file.existsSync()) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Ảnh trang nguồn không còn khả dụng. Bạn vẫn có thể đọc đoạn trích đã lưu.',
        ),
      );
    }
    final usesNormalized =
        page.normalizedAsset != null &&
        file.path == page.normalizedAsset!.absolutePath;
    final width = usesNormalized ? page.normalizedAsset!.width : page.width;
    final height = usesNormalized ? page.normalizedAsset!.height : page.height;
    if (width <= 0 || height <= 0) {
      return const Text('Kích thước ảnh nguồn không hợp lệ.');
    }
    return Column(
      children: [
        if (!_validBox) const Text('Vị trí đoạn nguồn không khả dụng.'),
        SizedBox(
          height: 320,
          child: InteractiveViewer(
            maxScale: 4,
            child: Center(
              child: AspectRatio(
                aspectRatio: width / height,
                child: Image.file(
                  file,
                  fit: BoxFit.fill,
                  errorBuilder: (_, error, stack) => const Center(
                    child: Text(
                      'Không thể đọc ảnh nguồn. Đoạn trích vẫn được giữ lại.',
                    ),
                  ),
                  frameBuilder: (context, image, frame, sync) {
                    if (frame == null && !sync) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        image,
                        if (_validBox &&
                            (page.normalizedAsset == null || usesNormalized))
                          CustomPaint(
                            key: const Key('source-highlight'),
                            painter: _BoundingBoxHighlightPainter(
                              box: sourceBlock!.boundingBox!,
                              color: p.warning,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
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
