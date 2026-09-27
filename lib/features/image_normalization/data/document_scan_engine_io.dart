import 'dart:isolate';
import 'dart:typed_data';

import 'package:document_scan/document_scan.dart';
import 'package:image/image.dart' as img;

import '../application/image_normalization_engine.dart';
import '../domain/image_normalization_models.dart';

class DocumentScanImageNormalizationEngine implements ImageNormalizationEngine {
  DocumentScanImageNormalizationEngine({
    DocumentDetector? detector,
    DocumentProcessor? processor,
  }) : _detector = detector ?? DocumentDetector(),
       _processor = processor ?? const DocumentProcessor();

  final DocumentDetector _detector;
  final DocumentProcessor _processor;

  @override
  Future<CropQuadrilateral?> detectCorners(String sourcePath) async {
    try {
      final result = await _detector.detect(ScanInput.file(sourcePath));
      if (result == null) return null;
      final corners = CropQuadrilateral(
        topLeft: NormalizedPoint(result.topLeft.x, result.topLeft.y),
        topRight: NormalizedPoint(result.topRight.x, result.topRight.y),
        bottomRight: NormalizedPoint(
          result.bottomRight.x,
          result.bottomRight.y,
        ),
        bottomLeft: NormalizedPoint(result.bottomLeft.x, result.bottomLeft.y),
      );
      return corners.isValid ? corners : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<NormalizedRenderedImage> renderPreview(
    String sourcePath,
    NormalizationParameters parameters,
  ) => _render(sourcePath, parameters, maxDimension: 1280);

  @override
  Future<NormalizedRenderedImage> renderFullResolution(
    String sourcePath,
    NormalizationParameters parameters,
  ) => _render(sourcePath, parameters, maxDimension: null);

  Future<NormalizedRenderedImage> _render(
    String sourcePath,
    NormalizationParameters parameters, {
    required int? maxDimension,
  }) async {
    if (!parameters.isValid) {
      throw const NormalizationFailure(
        NormalizationFailureCode.invalidCrop,
        'Vùng cắt không hợp lệ. Vui lòng điều chỉnh lại bốn góc.',
      );
    }
    try {
      final corners = DocumentCorners(
        topLeft: (
          x: parameters.corners.topLeft.x,
          y: parameters.corners.topLeft.y,
        ),
        topRight: (
          x: parameters.corners.topRight.x,
          y: parameters.corners.topRight.y,
        ),
        bottomRight: (
          x: parameters.corners.bottomRight.x,
          y: parameters.corners.bottomRight.y,
        ),
        bottomLeft: (
          x: parameters.corners.bottomLeft.x,
          y: parameters.corners.bottomLeft.y,
        ),
      );
      final cropped = await _processor.crop(
        ScanInput.file(sourcePath),
        corners,
        filter: ScanFilter.none,
        output: ScanOutputFormat.png,
        maxDimension: maxDimension,
        background: true,
      );
      if (cropped == null) {
        throw const NormalizationFailure(
          NormalizationFailureCode.processingFailed,
          'Không thể xử lý ảnh trên thiết bị. Vui lòng thử lại.',
        );
      }
      return await Isolate.run(
        () => _applyAdjustments(
          cropped.bytes,
          parameters.rotationDegrees,
          parameters.contrast,
        ),
      );
    } on NormalizationFailure {
      rethrow;
    } on OutOfMemoryError catch (error) {
      throw NormalizationFailure(
        NormalizationFailureCode.insufficientMemory,
        'Không thể xử lý ảnh trên thiết bị. Vui lòng đóng bớt ứng dụng hoặc sử dụng ảnh có độ phân giải thấp hơn.',
        error,
      );
    } catch (error) {
      throw NormalizationFailure(
        NormalizationFailureCode.processingFailed,
        'Không thể xử lý ảnh trên thiết bị. Vui lòng thử lại.',
        error,
      );
    }
  }
}

NormalizedRenderedImage _applyAdjustments(
  Uint8List bytes,
  int rotation,
  double contrast,
) {
  var image = img.decodePng(bytes);
  if (image == null) {
    throw const NormalizationFailure(
      NormalizationFailureCode.processingFailed,
      'Không thể tạo ảnh chuẩn hóa.',
    );
  }
  if (rotation != 0) {
    image = img.copyRotate(image, angle: rotation);
  }
  if (contrast != 0) {
    image = img.adjustColor(image, contrast: 1 + contrast);
  }
  final encoded = Uint8List.fromList(img.encodePng(image));
  return NormalizedRenderedImage(
    bytes: encoded,
    width: image.width,
    height: image.height,
  );
}
