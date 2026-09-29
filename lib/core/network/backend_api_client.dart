import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class BackendApiException implements Exception {
  const BackendApiException(this.code, this.message);
  final String code;
  final String message;
}

class BackendApiClient {
  BackendApiClient({String? baseUrl, http.Client? httpClient})
    : _baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'BACKEND_BASE_URL',
            defaultValue: 'https://api.leaselinkconnect.me',
          ),
      _client = httpClient;
  final String _baseUrl;
  final http.Client? _client;
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, Object?> payload,
  ) async {
    final base = _baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(
      '$base${base.endsWith('/api') ? '' : '/api'}/v1/$path',
    );
    if (uri == null ||
        !uri.hasAuthority ||
        !['http', 'https'].contains(uri.scheme)) {
      throw const BackendApiException(
        'backend_not_configured',
        'Chưa cấu hình địa chỉ dịch vụ AI.',
      );
    }
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 90));
      Map<String, dynamic>? body;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) body = decoded;
      } on FormatException {
        /* HTTP status remains authoritative for proxy errors. */
      }
      if (response.statusCode != 200) {
        final code =
            body?['error'] as String? ??
            switch (response.statusCode) {
              400 => 'invalid_request',
              413 => 'payload_too_large',
              429 => 'provider_quota',
              503 => 'backend_not_configured',
              504 => 'provider_timeout',
              _ => 'provider_unavailable',
            };
        throw BackendApiException(code, switch (code) {
          'invalid_request' => 'Cấu hình hoặc nguồn gửi lên không hợp lệ.',
          'payload_too_large' =>
            'Nội dung quá lớn. Vui lòng chọn ít nguồn hơn.',
          'provider_quota' ||
          'rate_limit_exceeded' ||
          'quota_exceeded' => 'Dịch vụ AI đang quá tải. Vui lòng thử lại sau.',
          'backend_not_configured' ||
          'invalid_api_key' => 'Dịch vụ AI chưa được cấu hình.',
          'provider_timeout' =>
            'Dịch vụ AI quá thời gian chờ. Bạn có thể thử lại.',
          'no_valid_cards' =>
            'Không có học liệu đạt kiểm tra nguồn và cấu trúc.',
          'no_text_found' => 'Không tìm thấy văn bản trong vùng ảnh.',
          'invalid_llm_output' ||
          'invalid_provider_response' => 'Dịch vụ AI trả dữ liệu không hợp lệ.',
          _ => 'Dịch vụ AI chưa sẵn sàng. Vui lòng thử lại sau.',
        });
      }
      if (body == null) {
        throw const BackendApiException(
          'invalid_provider_response',
          'Dịch vụ AI trả dữ liệu không hợp lệ.',
        );
      }
      return body;
    } on TimeoutException {
      throw const BackendApiException(
        'provider_timeout',
        'Dịch vụ AI quá thời gian chờ. Bạn có thể thử lại.',
      );
    } on http.ClientException {
      throw const BackendApiException(
        'network_unavailable',
        'Không thể kết nối dịch vụ AI. Kiểm tra mạng và thử lại.',
      );
    } finally {
      if (_client == null) client.close();
    }
  }
}
