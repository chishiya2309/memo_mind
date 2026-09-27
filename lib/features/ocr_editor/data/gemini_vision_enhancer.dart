import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/gemini_enhancer.dart';
import '../domain/ocr_models.dart';

class GeminiVisionEnhancer implements GeminiEnhancer {
  GeminiVisionEnhancer({
    String? apiKey,
    http.Client? httpClient,
  })  : _apiKey = apiKey ?? const String.fromEnvironment('GEMINI_API_KEY'),
        _client = httpClient ?? http.Client();

  final String _apiKey;
  final http.Client _client;

  static const String _model = 'gemini-1.5-flash';

  @override
  Future<String> enhanceCropText({
    required Uint8List imageBytes,
    String? currentText,
  }) async {
    if (_apiKey.isEmpty) {
      throw const OcrFailure(
        OcrFailureCode.networkUnavailable,
        'Chưa cấu hình API Key cho dịch vụ Gemini AI.',
      );
    }

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey',
    );

    final base64Image = base64Encode(imageBytes);

    final prompt = StringBuffer(
      'Bạn là một công cụ OCR chuyên nghiệp. Hãy chép lại CHÍNH XÁC NGUYÊN VĂN '
      'toàn bộ chữ in xuất hiện trong ảnh này.\n'
      'Quy tắc tuyệt đối:\n'
      '1. KHÔNG dịch sang ngôn ngữ khác.\n'
      '2. KHÔNG tóm tắt, diễn giải hoặc thêm lời bình.\n'
      '3. KHÔNG tự ý sửa chính tả hoặc đoán từ bị khuyết.\n'
      '4. Giữ nguyên định dạng xuống dòng.\n'
      '5. Chỉ trả về duy nhất văn bản được chép lại.',
    );

    if (currentText != null && currentText.trim().isNotEmpty) {
      prompt.write('\nVăn bản nhận dạng trước đó (tham khảo đối chiếu): "$currentText"');
    }

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt.toString()},
            {
              'inlineData': {
                'mimeType': 'image/jpeg',
                'data': base64Image,
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.0,
        'maxOutputTokens': 1024,
      },
    });

    try {
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final candidates = data['candidates'] as List<dynamic>?;
        if (candidates != null && candidates.isNotEmpty) {
          final firstCandidate = candidates.first as Map<String, dynamic>;
          final content = firstCandidate['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List<dynamic>?;
          if (parts != null && parts.isNotEmpty) {
            final text = (parts.first as Map<String, dynamic>)['text'] as String?;
            if (text != null && text.trim().isNotEmpty) {
              return text.trim();
            }
          }
        }
        throw const OcrFailure(
          OcrFailureCode.noTextFound,
          'Gemini không tìm thấy văn bản trong vùng ảnh được chọn.',
        );
      } else if (response.statusCode == 429) {
        throw const OcrFailure(
          OcrFailureCode.serviceQuotaOrTimeout,
          'Dịch vụ AI vượt quá hạn mức yêu cầu. Vui lòng thử lại sau.',
        );
      } else {
        throw OcrFailure(
          OcrFailureCode.unknown,
          'Dịch vụ Gemini trả về mã lỗi ${response.statusCode}.',
        );
      }
    } on http.ClientException catch (e) {
      throw OcrFailure(
        OcrFailureCode.networkUnavailable,
        'Cần kết nối Internet để nhận dạng văn bản bằng dịch vụ AI.',
        e,
      );
    } catch (e) {
      if (e is OcrFailure) rethrow;
      throw OcrFailure(
        OcrFailureCode.serviceQuotaOrTimeout,
        'Yêu cầu đến dịch vụ AI bị gián đoạn hoặc quá thời gian chờ.',
        e,
      );
    }
  }
}
