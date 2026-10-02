import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/auth_repository.dart';

class BackupApiClient {
  BackupApiClient({required this.auth, String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? const String.fromEnvironment('BACKEND_BASE_URL'),
      _injectedClient = client;
  final AuthRepository auth;
  final String baseUrl;
  final http.Client? _injectedClient;
  final _active = <http.Client>{};
  void cancelTransfers() {
    for (final client in _active.toList()) {
      client.close();
    }
    _active.clear();
  }

  Future<Map<String, dynamic>> request(
    String method,
    String suffix, {
    Map<String, Object?>? body,
    required String uid,
  }) async {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(
      '$base${base.endsWith('/api') ? '' : '/api'}/v1/backups$suffix',
    );
    if (base.isEmpty ||
        uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' &&
            !['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host)))
      throw const AccountFailure(
        'backup_not_configured',
        'Chưa cấu hình dịch vụ sao lưu HTTPS.',
      );
    if (auth.current?.uid != uid)
      throw const AccountFailure('reauth_required', 'Tài khoản đã thay đổi.');
    final token = await auth.token(refresh: true);
    if (auth.current?.uid != uid)
      throw const AccountFailure('reauth_required', 'Tài khoản đã thay đổi.');
    final client = _injectedClient ?? http.Client();
    try {
      final req = http.Request(method, uri)
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        });
      if (body != null) req.body = jsonEncode(body);
      final response = await http.Response.fromStream(
        await client.send(req).timeout(const Duration(minutes: 10)),
      ).timeout(const Duration(minutes: 10));
      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300)
        throw AccountFailure(
          decoded['error'] as String? ?? 'backup_failed',
          decoded['message'] as String? ?? 'Không thể xử lý sao lưu.',
        );
      return decoded;
    } on TimeoutException {
      throw const AccountFailure(
        'unconfirmed',
        'Chưa xác nhận kết quả. Hãy đối chiếu bản sao trước khi thử lại.',
      );
    } on http.ClientException {
      throw const AccountFailure(
        'waiting_network',
        'Chờ mạng hoặc tác vụ đã dừng. Dữ liệu cục bộ được giữ.',
      );
    } on FormatException {
      throw const AccountFailure(
        'backup_failed',
        'Dịch vụ trả dữ liệu không hợp lệ.',
      );
    } finally {
      if (_injectedClient == null) client.close();
    }
  }

  Future<void> upload(
    File file,
    Map<String, dynamic> upload,
    void Function(double) progress,
  ) async {
    final client = http.Client();
    _active.add(client);
    try {
      final request = http.StreamedRequest(
        'PUT',
        Uri.parse(upload['url'] as String),
      )..contentLength = await file.length();
      request.headers.addAll(
        Map<String, String>.from(upload['headers'] as Map),
      );
      final sending = client.send(request);
      var sent = 0;
      await for (final chunk in file.openRead()) {
        request.sink.add(chunk);
        sent += chunk.length;
        progress(sent / request.contentLength!);
      }
      await request.sink.close();
      final response = await sending.timeout(const Duration(minutes: 10));
      await response.stream.drain<void>();
      if (response.statusCode != 200 && response.statusCode != 412)
        throw const AccountFailure(
          'waiting_network',
          'Chưa tải được gói. Có thể thử lại snapshot này.',
        );
    } on http.ClientException {
      throw const AccountFailure(
        'waiting_network',
        'Tác vụ bị ngắt. Dữ liệu cục bộ được giữ.',
      );
    } on TimeoutException {
      throw const AccountFailure('unconfirmed', 'Tải gói quá thời gian chờ.');
    } finally {
      _active.remove(client);
      client.close();
    }
  }

  Future<void> download(String url, File destination) async {
    final client = http.Client();
    _active.add(client);
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(minutes: 10));
      if (response.statusCode != 200)
        throw const AccountFailure('download_failed', 'Không thể tải bản sao.');
      final sink = destination.openWrite();
      var total = 0;
      try {
        await for (final chunk in response.stream.timeout(
          const Duration(minutes: 10),
        )) {
          total += chunk.length;
          if (total > 100 * 1024 * 1024)
            throw const AccountFailure(
              'backup_limit',
              'Gói vượt giới hạn 100 MiB.',
            );
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
    } finally {
      _active.remove(client);
      client.close();
    }
  }
}
