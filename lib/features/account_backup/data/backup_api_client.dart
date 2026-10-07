import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../domain/auth_repository.dart';

class BackupApiClient {
  BackupApiClient({
    required this.auth,
    String? baseUrl,
    http.Client? client,
    this.apiPath = 'backups',
    this.requestTimeout = const Duration(minutes: 10),
    this.transferTimeout = const Duration(minutes: 10),
    http.Client Function()? transferClientFactory,
  }) : baseUrl = baseUrl ?? const String.fromEnvironment('BACKEND_BASE_URL'),
       _injectedClient = client,
       _transferClientFactory = transferClientFactory ?? http.Client.new;
  final AuthRepository auth;
  final String baseUrl;
  final String apiPath;
  final Duration requestTimeout;
  final Duration transferTimeout;
  final http.Client Function() _transferClientFactory;
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
          httpStatus: response.statusCode,
          requestId: response.headers['x-request-id'],
          missingParents: [
            for (final parent
                in decoded['missingParents'] is List
                    ? decoded['missingParents'] as List
                    : const [])
              if (parent is Map &&
                  parent['table'] is String &&
                  parent['entityId'] is String)
                {
                  'table': parent['table'] as String,
                  'entityId': parent['entityId'] as String,
                },
          ],
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
    final generation = _generation;
    final uid = auth.current?.uid;
    void check() {
      if (generation != _generation || auth.current?.uid != uid) {
        throw const AccountFailure(
          'sync_cancelled',
          'Tác vụ đã dừng. Dữ liệu được giữ trên thiết bị.',
        );
      }
    }

    final subject = apiPath == 'sync' ? 'ảnh/PDF' : 'bản sao';
    final client = _transferClientFactory();
    _active.add(client);
    int? status;
    String? requestId;
    try {
      final request = http.StreamedRequest(
        'PUT',
        Uri.parse(upload['url'] as String),
      )..contentLength = await file.length();
      check();
      request.headers.addAll(
        Map<String, String>.from(upload['headers'] as Map),
      );
      final sending = client.send(request).then((response) {
        status = response.statusCode;
        requestId = _safeDiagnostic(response.headers['x-amz-request-id']);
        return response;
      });
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
        status = result.statusCode;
        requestId = _safeDiagnostic(result.headers['x-amz-request-id']);
        check();
        if (status != 200 && status != 412) {
          final bytes = <int>[];
          await for (final chunk in result.stream) {
            final remaining = 16384 - bytes.length;
            bytes.addAll(chunk.take(remaining));
            if (bytes.length == 16384) break;
          }
          check();
          throw _storageFailure(status!, bytes, requestId, subject);
        }
        await result.stream.drain<void>();
        return result;
      })().timeout(transferTimeout);
      check();
      assert(response.statusCode == 200 || response.statusCode == 412);
    } on http.ClientException {
      check();
      if (status != null && status != 200 && status != 412) {
        throw _storageFailure(status!, const [], requestId, subject);
      }
      throw AccountFailure(
        'waiting_network',
        'Kết nối bị ngắt khi tải lên $subject. Dữ liệu được giữ trên thiết bị.',
      );
    } on TimeoutException {
      check();
      if (status != null && status != 200 && status != 412) {
        throw _storageFailure(status!, const [], requestId, subject);
      }
      throw AccountFailure(
        'unconfirmed',
        'Tải lên $subject quá thời gian chờ.',
        httpStatus: status,
        requestId: requestId,
      );
    } catch (error) {
      check();
      if (error is! AccountFailure &&
          status != null &&
          status != 200 &&
          status != 412) {
        throw _storageFailure(status!, const [], requestId, subject);
      }
      rethrow;
    } finally {
      _active.remove(client);
      client.close();
    }
  }

  static String? _safeDiagnostic(String? value) =>
      value != null && RegExp(r'^[A-Za-z0-9_+/=.-]{1,128}$').hasMatch(value)
      ? value
      : null;

  AccountFailure _storageFailure(
    int status,
    List<int> bytes,
    String? requestId,
    String subject,
  ) {
    String? storageCode;
    try {
      final root = XmlDocument.parse(utf8.decode(bytes)).rootElement;
      if (root.name.local == 'Error') {
        storageCode = _safeDiagnostic(root.getElement('Code')?.innerText);
        requestId ??= _safeDiagnostic(root.getElement('RequestId')?.innerText);
      }
    } catch (_) {
      /* Preserve HTTP diagnostics when the response is malformed. */
    }
    final String code, message;
    if (['ExpiredToken', 'RequestExpired'].contains(storageCode) ||
        (storageCode == 'AccessDenied' && _expiredResponse(bytes))) {
      code = 'storage_url_expired';
      message = 'Liên kết tải lên $subject đã hết hạn. Hãy thử lại.';
    } else if (storageCode == 'SignatureDoesNotMatch' ||
        storageCode == 'AuthorizationHeaderMalformed') {
      code = 'storage_signature_invalid';
      message =
          'Chữ ký tải lên $subject không hợp lệ. Cần kiểm tra cấu hình dịch vụ lưu trữ.';
    } else if ([
      'BadDigest',
      'InvalidDigest',
      'ChecksumMismatch',
    ].contains(storageCode)) {
      code = 'storage_checksum_mismatch';
      message =
          'Kiểm tra toàn vẹn $subject không khớp. Dữ liệu được giữ trên thiết bị.';
    } else if (status == 413 || storageCode == 'EntityTooLarge') {
      code = 'storage_file_limit';
      message = '$subject vượt giới hạn dung lượng cho phép.';
    } else if (status == 429 || status >= 500 || storageCode == 'SlowDown') {
      code = 'storage_unavailable';
      message =
          'Dịch vụ lưu trữ tạm thời chưa xử lý được $subject. Hãy thử lại sau.';
    } else if (status == 401 ||
        status == 403 ||
        [
          'NoSuchBucket',
          'PermanentRedirect',
          'InvalidAccessKeyId',
        ].contains(storageCode)) {
      code = 'storage_not_configured';
      message =
          'Dịch vụ lưu trữ chưa được cấu hình đúng. Chưa tải lên được $subject.';
    } else {
      code = 'storage_upload_failed';
      message =
          'Dịch vụ lưu trữ từ chối tải lên $subject. Dữ liệu được giữ trên thiết bị.';
    }
    developer.log(
      'upload_failed http=$status code=${storageCode ?? 'unknown'} requestId=${requestId ?? 'unknown'}',
      name: 'MemoMind.storage',
    );
    return AccountFailure(
      code,
      message,
      httpStatus: status,
      storageCode: storageCode,
      requestId: requestId,
    );
  }

  static bool _expiredResponse(List<int> bytes) {
    try {
      final message = XmlDocument.parse(utf8.decode(bytes)).rootElement
          .getElement('Message')
          ?.innerText;
      return message == 'Request has expired' ||
          message == 'Request has expired.';
    } catch (_) {
      return false;
    }
  }

  Future<void> download(String url, File destination) async {
    final subject = apiPath == 'sync' ? 'ảnh/PDF' : 'bản sao';
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
        throw AccountFailure('download_failed', 'Chưa tải về được $subject.');
      }
      final sink = destination.openWrite();
      var total = 0;
      try {
        await for (final chunk in response.stream.timeout(
          const Duration(minutes: 10),
        )) {
          total += chunk.length;
          if (total > 100 * 1024 * 1024) {
            throw AccountFailure(
              'backup_limit',
              '$subject vượt giới hạn 100 MiB.',
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
            ? 'Tải về $subject quá thời gian chờ 10 phút.'
            : 'Mạng bị ngắt hoặc tác vụ đã dừng.',
      );
    } on TimeoutException {
      throw AccountFailure(
        'backup_timeout',
        'Tải về $subject quá thời gian chờ 10 phút.',
      );
    } finally {
      deadline.cancel();
      _active.remove(client);
      client.close();
    }
  }
}
