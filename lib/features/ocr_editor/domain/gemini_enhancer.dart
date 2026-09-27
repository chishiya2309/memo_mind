import 'dart:typed_data';

abstract class GeminiEnhancer {
  Future<String> enhanceCropText({
    required Uint8List imageBytes,
    String? currentText,
  });
}
