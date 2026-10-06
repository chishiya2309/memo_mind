import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/auth_repository.dart';

class BackupApiClient {
  BackupApiClient({
    required this.auth,
    String? baseUrl,
    http.Client? client,
    this.apiPath = 'backups',
    this.requestTimeout = const Duration(minutes: 10),
  }) : baseUrl = baseUrl ?? const String.fromEnvironment('BACKEND_BASE_URL'),
       _injectedClient = client;
  final AuthRepository auth;
  final String baseUrl;
  final String apiPath;
  final Duration requestTimeout;
  final http.Client? _injectedClient;
  final _active = <http.Client>{};
  int _generation = 0;
  void cancelTransfers() {
    _generation++;
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
  }) => _request(
    method,
    suffix,
    encodedBody: body == null ? null : jsonEncode(body),
    uid: uid,
    generation: _generation,
  );

  void _checkSession(String uid, int generation) {
    if (auth.current?.uid != uid || generation != _generation) {
      throw const AccountFailure(
        'sync_cancelled',
        'Tài khoản hoặc thư viện đã thay đổi.',
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String suffix, {
    String? encodedBody,
    required String uid,
    required int generation,
    bool refreshed = false,
  }) async {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(
      '$base${base.endsWith('/api') ? '' : '/api'}/v1/$apiPath$suffix',
    );
    if (base.isEmpty ||
        uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' &&
            !['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host))) {
      throw const AccountFailure(
        'backup_not_configured',
        'Chưa cấu hình dịch vụ sao lưu HTTPS.',
      );
    }
    _checkSession(uid, generation);
    final String token;
    try {
      token = await auth.token(refresh: refreshed).timeout(requestTimeout);
    } on TimeoutException {
      throw const AccountFailure(
        'waiting_network',
        'Chưa kết nối được dịch vụ xác thực. Bạn vẫn có thể học trên thiết bị.',
      );
    }
    _checkSession(uid, generation);
    final client = _injectedClient ?? http.Client();
    _active.add(client);
    try {
      final req = http.Request(method, uri)
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        });
      if (encodedBody != null) req.body = encodedBody;
      final response = await (() async => http.Response.fromStream(
        await client.send(req),
      ))().timeout(requestTimeout);
      _checkSession(uid, generation);
      Map<String, dynamic> decoded;
      try {
        final value = jsonDecode(utf8.decode(response.bodyBytes));
        if (value is! Map<String, dynamic>) throw const FormatException();
        decoded = value;
      } on FormatException {
        if (response.statusCode >= 500) {
          throw const AccountFailure(
            'service_unavailable',
            'Chưa kết nối được dịch vụ. Hãy thử lại sau.',
          );
        }
        rethrow;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = decoded['error'] as String?;
        if (response.statusCode == 401 &&
            [
              'token_expired',
              'token_invalid',
              'reauth_required',
            ].contains(code)) {
          if (!refreshed) {
            return await _request(
              method,
              suffix,
              encodedBody: encodedBody,
              uid: uid,
              generation: generation,
              refreshed: true,
            );
          }
          throw const AccountFailure(
            'reauth_required',
            'Không thể khôi phục phiên. Xác thực lại để tiếp tục đồng bộ.',
          );
        }
        throw AccountFailure(
          code ??
              (response.statusCode >= 500
                  ? 'service_unavailable'
                  : 'backup_failed'),
          decoded['message'] as String? ?? 'Chưa thực hiện được yêu cầu. Dữ liệu trên thiết bị được giữ nguyên.',
        );
      }
      return decoded;
    } on TimeoutException {
      throw const AccountFailure(
        'unconfirmed',
        'Chưa xác nhận kết quả. Hãy thử lại; thay đổi vẫn được giữ trên thiết bị.',
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
      _active.remove(client);
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
      final feeding = (() async {
        try {
          await request.sink.addStream(
            file.openRead().map((chunk) {
              sent += chunk.length;
              progress(sent / request.contentLength!);
              return chunk;
            }),
          );
        } finally {
          await request.sink.close();
        }
      })();
      // Attach handlers to both futures immediately: cancelling a transfer may
      // fail the HTTP request before the file stream has finished feeding it.
      final response = await (() async {
        final results = await Future.wait<Object?>([
          sending,
          feeding,
        ], eagerError: true);
        final result = results.first as http.StreamedResponse;
        await result.stream.drain<void>();
        return result;
      })().timeout(const Duration(minutes: 10));
      if (response.statusCode != 200 && response.statusCode != 412) {
        throw const AccountFailure(
          'waiting_network',
          'Chưa tải được gói. Có thể thử lại snapshot này.',
        );
      }
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
    var timedOut = false;
    final deadline = Timer(const Duration(minutes: 10), () {
      timedOut = true;
      client.close();
    });
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(minutes: 10));
      if (response.statusCode != 200) {
        throw const AccountFailure('download_failed', 'Không thể tải bản sao.');
      }
      final sink = destination.openWrite();
      var total = 0;
      try {
        await for (final chunk in response.stream.timeout(
          const Duration(minutes: 10),
        )) {
          total += chunk.length;
          if (total > 100 * 1024 * 1024) {
            throw const AccountFailure(
              'backup_limit',
              'Gói vượt giới hạn 100 MiB.',
            );
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
    } on http.ClientException {
      throw AccountFailure(
        timedOut ? 'backup_timeout' : 'waiting_network',
        timedOut
            ? 'Tải bản sao quá thời gian chờ 10 phút.'
            : 'Mạng bị ngắt hoặc tác vụ đã dừng.',
      );
    } on TimeoutException {
      throw const AccountFailure(
        'backup_timeout',
        'Tải bản sao quá thời gian chờ 10 phút.',
      );
    } finally {
      deadline.cancel();
      _active.remove(client);
      client.close();
    }
  }
}
