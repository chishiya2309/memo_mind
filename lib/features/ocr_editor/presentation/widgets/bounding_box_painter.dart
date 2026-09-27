import 'package:flutter/material.dart';

import '../../domain/ocr_models.dart';

class BoundingBoxPainter extends CustomPainter {
  const BoundingBoxPainter({
    required this.blocks,
    required this.selectedBlockId,
    required this.primaryColor,
    required this.warningColor,
    required this.tealColor,
  });

  final List<SourceBlock> blocks;
  final String? selectedBlockId;
  final Color primaryColor;
  final Color warningColor;
  final Color tealColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    for (final block in blocks) {
      if (block.isDeleted || block.boundingBox == null || !block.hasValidBox) {
        continue;
      }

      final box = block.boundingBox!;
      final rect = box.toRect(size);
      final isSelected = block.blockId == selectedBlockId;

      Color strokeColor;
      double strokeWidth;
      Color fillColor;

      if (isSelected) {
        strokeColor = primaryColor;
        strokeWidth = 3.0;
        fillColor = primaryColor.withValues(alpha: 0.22);
      } else if (block.needsReview) {
        strokeColor = warningColor;
        strokeWidth = 2.0;
        fillColor = warningColor.withValues(alpha: 0.12);
      } else if (block.isUserAdded) {
        strokeColor = tealColor;
        strokeWidth = 2.0;
        fillColor = tealColor.withValues(alpha: 0.12);
      } else {
        strokeColor = primaryColor.withValues(alpha: 0.5);
        strokeWidth = 1.2;
        fillColor = primaryColor.withValues(alpha: 0.05);
      }

      // Draw background fill
      final fillPaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        fillPaint,
      );

      // Draw border
      final borderPaint = Paint()
        ..color = strokeColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        borderPaint,
      );

      // Draw small badge on top-left of selected or warning block
      if (isSelected || block.needsReview) {
        final textSpan = TextSpan(
          text: isSelected
              ? '#${block.orderIndex + 1}'
              : (block.needsReview ? '!' : ''),
          style: TextStyle(
            color: Colors.white,
            fontSize: isSelected ? 10 : 11,
            fontWeight: FontWeight.bold,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout();

        final badgeBgPaint = Paint()
          ..color = isSelected ? primaryColor : warningColor
          ..style = PaintingStyle.fill;

        final badgeRect = Rect.fromLTWH(
          rect.left,
          rect.top - 14 >= 0 ? rect.top - 14 : rect.top,
          textPainter.width + 8,
          14,
        );

        canvas.drawRRect(
          RRect.fromRectAndRadius(badgeRect, const Radius.circular(3)),
          badgeBgPaint,
        );

        textPainter.paint(
          canvas,
          Offset(badgeRect.left + 4, badgeRect.top),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.blocks != blocks ||
        oldDelegate.selectedBlockId != selectedBlockId ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.warningColor != warningColor ||
        oldDelegate.tealColor != tealColor;
  }
}
