import 'dart:typed_data';

import '../domain/image_normalization_models.dart';

class NormalizedRenderedImage {
  const NormalizedRenderedImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

abstract interface class ImageNormalizationEngine {
  Future<CropQuadrilateral?> detectCorners(String sourcePath);

  Future<NormalizedRenderedImage> renderPreview(
    String sourcePath,
    NormalizationParameters parameters,
  );

  Future<NormalizedRenderedImage> renderFullResolution(
    String sourcePath,
    NormalizationParameters parameters,
  );
}
