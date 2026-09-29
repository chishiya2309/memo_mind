import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/network/backend_api_client.dart';
import '../domain/gemini_enhancer.dart';
import '../domain/ocr_models.dart';

class GeminiVisionEnhancer implements GeminiEnhancer {
  GeminiVisionEnhancer({String? baseUrl, http.Client? httpClient})
    : _backend = BackendApiClient(baseUrl: baseUrl, httpClient: httpClient);
  final BackendApiClient _backend;
  @override
  Future<String> enhanceCropText({
    required Uint8List imageBytes,
    String? currentText,
  }) async {
    if (imageBytes.length > 5 * 1024 * 1024) {
      throw const OcrFailure(
        OcrFailureCode.invalidOutput,
        'Vùng ảnh tối đa 5 MB. Vui lòng chọn vùng nhỏ hơn.',
      );
    }
    try {
      final body = await _backend.post('ocr/enhance', {
        'imageBase64': base64Encode(imageBytes),
        'currentText': ?currentText,
      });
      final text = body['text'];
      if (text is! String || text.trim().isEmpty) {
        throw const OcrFailure(
          OcrFailureCode.invalidOutput,
          'Dịch vụ OCR trả dữ liệu không hợp lệ.',
        );
      }
      return text.trim();
    } on BackendApiException catch (e) {
      throw OcrFailure(switch (e.code) {
        'network_unavailable' => OcrFailureCode.networkUnavailable,
        'provider_timeout' ||
        'provider_quota' ||
        'rate_limit_exceeded' => OcrFailureCode.serviceQuotaOrTimeout,
        'no_text_found' => OcrFailureCode.noTextFound,
        _ => OcrFailureCode.invalidOutput,
      }, e.message);
    }
  }
}
