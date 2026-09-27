import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/ocr_models.dart';

class ImageRegionCropper {
  const ImageRegionCropper();

  Future<Uint8List?> cropRegion({
    required String imagePath,
    required NormalizedBoundingBox box,
    double paddingRatio = 0.05,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final int rawLeft = (box.left * decoded.width).round();
    final int rawTop = (box.top * decoded.height).round();
    final int rawWidth = (box.width * decoded.width).round();
    final int rawHeight = (box.height * decoded.height).round();

    final int paddingX = (rawWidth * paddingRatio).round();
    final int paddingY = (rawHeight * paddingRatio).round();

    final int x = math.max(0, rawLeft - paddingX);
    final int y = math.max(0, rawTop - paddingY);
    final int w = math.min(decoded.width - x, math.max(1, rawWidth + paddingX * 2));
    final int h = math.min(decoded.height - y, math.max(1, rawHeight + paddingY * 2));

    final cropped = img.copyCrop(
      decoded,
      x: x,
      y: y,
      width: w,
      height: h,
    );

    return Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
  }
}
