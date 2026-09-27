import 'dart:ui';

import '../domain/ocr_engine.dart';
import '../domain/ocr_models.dart';

class MlKitTextRecognitionEngine implements OcrEngine {
  const MlKitTextRecognitionEngine();

  @override
  Future<ExtractedPageOcr> recognizeText({
    required String imagePath,
    required Size imageSize,
  }) {
    throw const OcrFailure(
      OcrFailureCode.modelUnavailable,
      'Nhận dạng văn bản ML Kit chỉ khả dụng trên thiết bị di động.',
    );
  }

  @override
  Future<void> dispose() async {}
}
