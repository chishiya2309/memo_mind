import 'dart:io';
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/ocr_engine.dart';
import '../domain/ocr_models.dart';

class MlKitTextRecognitionEngine implements OcrEngine {
  MlKitTextRecognitionEngine({
    TextRecognizer? textRecognizer,
  }) : _recognizer = textRecognizer ??
            TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  @override
  Future<ExtractedPageOcr> recognizeText({
    required String imagePath,
    required Size imageSize,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw OcrFailure(
        OcrFailureCode.pageImageNotFound,
        'Không tìm thấy file ảnh nguồn tại $imagePath.',
      );
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await _recognizer.processImage(inputImage);

      if (recognizedText.text.trim().isEmpty) {
        return ExtractedPageOcr(
          rawFullText: '',
          blocks: const [],
          detectedLanguage: null,
        );
      }

      final blocks = <ExtractedBlock>[];

      for (final block in recognizedText.blocks) {
        if (block.text.trim().isEmpty) continue;

        // Try to get recognized language from block recognized languages if available
        String? language;
        if (block.recognizedLanguages.isNotEmpty) {
          language = block.recognizedLanguages.first;
        }

        blocks.add(
          ExtractedBlock(
            text: block.text,
            boundingBox: block.boundingBox,
            confidence: null, // ML Kit Latin Text Recognition for mobile doesn't populate numeric confidence
            recognizedLanguage: language,
          ),
        );
      }

      // If blocks are empty but raw text exists (Luồng 9b)
      if (blocks.isEmpty && recognizedText.text.trim().isNotEmpty) {
        blocks.add(
          ExtractedBlock(
            text: recognizedText.text,
            boundingBox: Rect.fromLTWH(0, 0, imageSize.width, imageSize.height),
            confidence: null,
          ),
        );
      }

      return ExtractedPageOcr(
        rawFullText: recognizedText.text,
        blocks: blocks,
        detectedLanguage: blocks.isNotEmpty ? blocks.first.recognizedLanguage : null,
      );
    } catch (e) {
      if (e is OcrFailure) rethrow;
      throw OcrFailure(
        OcrFailureCode.unknown,
        'Lỗi trong quá trình nhận dạng văn bản ML Kit.',
        e,
      );
    }
  }

  @override
  Future<void> dispose() async {
    await _recognizer.close();
  }
}
