import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/document_import_models.dart';

/// Gives the raster, overlay and hit testing exactly the same local bounds.
/// Keep this inside InteractiveViewer so all three share its transformation.
class SourceRasterView extends StatelessWidget {
  const SourceRasterView({
    super.key,
    required this.image,
    this.painter,
    this.onTap,
    this.onLayout,
    this.onViewport,
    this.highlightKey,
  });

  final SourceImage image;
  final CustomPainter? painter;
  final void Function(Offset position, Size imageSize)? onTap;
  final ValueChanged<Size>? onLayout;
  final ValueChanged<Size>? onViewport;
  final Key? highlightKey;

  @override
  Widget build(BuildContext context) {
    if (image.width <= 0 || image.height <= 0) {
      return const Center(child: Text('Kích thước ảnh nguồn không hợp lệ.'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = applyBoxFit(
          BoxFit.contain,
          Size(image.width.toDouble(), image.height.toDouble()),
          constraints.biggest,
        ).destination;
        onLayout?.call(size);
        onViewport?.call(constraints.biggest);
        return Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Image.file(
              File(image.path),
              fit: BoxFit.fill,
              errorBuilder: (_, error, stack) => const Center(
                child: Text(
                  'Không thể đọc ảnh nguồn. Đoạn trích vẫn được giữ lại.',
                ),
              ),
              frameBuilder: (context, child, frame, synchronouslyLoaded) {
                if (frame == null && !synchronouslyLoaded) {
                  return const Center(child: CircularProgressIndicator());
                }
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: onTap == null
                      ? null
                      : (details) => onTap!(details.localPosition, size),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      child,
                      if (painter != null)
                        CustomPaint(key: highlightKey, painter: painter),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
