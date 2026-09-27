import 'dart:ui';

class ExtractedBlock {
  const ExtractedBlock({
    required this.text,
    this.boundingBox,
    this.confidence,
    this.recognizedLanguage,
  });

  final String text;
  final Rect? boundingBox;
  final double? confidence;
  final String? recognizedLanguage;
}

class ExtractedPageOcr {
  const ExtractedPageOcr({
    required this.rawFullText,
    required this.blocks,
    this.detectedLanguage,
  });

  final String rawFullText;
  final List<ExtractedBlock> blocks;
  final String? detectedLanguage;
}

abstract class OcrEngine {
  Future<ExtractedPageOcr> recognizeText({
    required String imagePath,
    required Size imageSize,
  });

  Future<void> dispose();
}
