import '../application/image_normalization_engine.dart';
import '../domain/image_normalization_models.dart';

class DocumentScanImageNormalizationEngine implements ImageNormalizationEngine {
  @override
  Future<CropQuadrilateral?> detectCorners(String sourcePath) async => null;

  @override
  Future<NormalizedRenderedImage> renderFullResolution(
    String sourcePath,
    NormalizationParameters parameters,
  ) => throw const NormalizationFailure(
    NormalizationFailureCode.unsupportedPlatform,
    'Chuẩn hóa ảnh hiện chỉ được hỗ trợ trên Android.',
  );

  @override
  Future<NormalizedRenderedImage> renderPreview(
    String sourcePath,
    NormalizationParameters parameters,
  ) => renderFullResolution(sourcePath, parameters);
}
