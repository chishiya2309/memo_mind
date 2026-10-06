import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memo_mind/features/account_backup/data/backup_api_client.dart';
import 'package:memo_mind/features/account_backup/domain/auth_repository.dart';

import '../support/account_backup_fakes.dart';

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('storage-upload-');
    file = await File('${directory.path}/file').writeAsString('source');
  });
  tearDown(() => directory.delete(recursive: true));
  const upload = {
    'url': 'https://storage.example/file?secret=never-log',
    'headers': <String, String>{},
  };
  BackupApiClient client(
    http.Client transport, {
    String path = 'sync',
    Duration timeout = const Duration(minutes: 10),
  }) => BackupApiClient(
    auth: FakeAccountAuth(),
    apiPath: path,
    transferClientFactory: () => transport,
    transferTimeout: timeout,
  );

  for (final status in [200, 412]) {
    test('upload accepts $status', () async {
      await client(MockClient((_) async => http.Response('', status)))
          .upload(file, upload, (_) {});
    });
  }
  final cases = <(int, String, String)>[
    (403, 'AccessDenied', 'storage_not_configured'),
    (403, 'SignatureDoesNotMatch', 'storage_signature_invalid'),
    (400, 'AuthorizationHeaderMalformed', 'storage_signature_invalid'),
    (403, 'ExpiredToken', 'storage_url_expired'),
    (403, 'RequestExpired', 'storage_url_expired'),
    (400, 'BadDigest', 'storage_checksum_mismatch'),
    (413, 'EntityTooLarge', 'storage_file_limit'),
    (429, 'SlowDown', 'storage_unavailable'),
    (503, 'ServiceUnavailable', 'storage_unavailable'),
  ];
  for (final (status, s3Code, code) in cases) {
    test('classifies $status $s3Code without Firebase reauthentication', () async {
      final api = client(
        MockClient(
          (_) async => http.Response(
            '<Error><Code>$s3Code</Code><RequestId>xml-id</RequestId></Error>',
            status,
          ),
        ),
      );
      await expectLater(
        api.upload(file, upload, (_) {}),
        throwsA(
          isA<AccountFailure>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.httpStatus, 'status', status)
              .having((e) => e.storageCode, 'S3 code', s3Code)
              .having((e) => e.requestId, 'request ID', 'xml-id')
              .having(
                (e) => e.message.contains('snapshot'),
                'snapshot wording',
                false,
              ),
        ),
      );
    });
  }
  test(
    'AccessDenied expiration is distinguished from permission denial',
    () async {
      await expectLater(
        client(
          MockClient(
            (_) async => http.Response(
              '<Error><Code>AccessDenied</Code><Message>Request has expired</Message></Error>',
              403,
            ),
          ),
        ).upload(file, upload, (_) {}),
        throwsA(
          isA<AccountFailure>().having(
            (e) => e.code,
            'code',
            'storage_url_expired',
          ),
        ),
      );
    },
  );
  test(
    'malformed XML preserves header diagnostics and backup wording',
    () async {
      await expectLater(
        client(
          MockClient(
            (_) async => http.Response(
              '<broken',
              403,
              headers: {'x-amz-request-id': 'header-id'},
            ),
          ),
          path: 'backups',
        ).upload(file, upload, (_) {}),
        throwsA(
          isA<AccountFailure>()
              .having((e) => e.requestId, 'request ID', 'header-id')
              .having(
                (e) => e.message.contains('bản sao'),
                'backup wording',
                true,
              ),
        ),
      );
    },
  );
  test('only reads 16 KiB of an error response', () async {
    var chunks = 0;
    final api = client(
      MockClient.streaming((request, body) async {
        await body.drain<void>();
        return http.StreamedResponse(
          (() async* {
            for (var i = 0; i < 100; i++) {
              chunks++;
              yield List.filled(4096, 65);
            }
          })(),
          500,
          headers: {'x-amz-request-id': 'bounded'},
        );
      }),
    );
    await expectLater(
      api.upload(file, upload, (_) {}),
      throwsA(isA<AccountFailure>().having((e) => e.httpStatus, 'status', 500)),
    );
    expect(chunks, 4);
  });
  test('unreadable error body preserves HTTP status', () async {
    final api = client(
      MockClient.streaming((request, body) async {
        await body.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.error(http.ClientException('secret response')),
          403,
          headers: {'x-amz-request-id': 'body-error'},
        );
      }),
    );
    await expectLater(
      api.upload(file, upload, (_) {}),
      throwsA(
        isA<AccountFailure>()
            .having((e) => e.code, 'code', 'storage_not_configured')
            .having((e) => e.requestId, 'id', 'body-error'),
      ),
    );
  });
  test('network failure and timeout remain retryable', () async {
    await expectLater(
      client(MockClient((_) async => throw http.ClientException('network')))
          .upload(file, upload, (_) {}),
      throwsA(
        isA<AccountFailure>().having((e) => e.code, 'code', 'waiting_network'),
      ),
    );
    await expectLater(
      client(
        MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 20),
      ).upload(file, upload, (_) {}),
      throwsA(
        isA<AccountFailure>().having((e) => e.code, 'code', 'unconfirmed'),
      ),
    );
  });
  test('cancellation never becomes an authentication failure', () async {
    final response = Completer<http.Response>();
    final api = client(MockClient((_) => response.future));
    final task = api.upload(file, upload, (_) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    api.cancelTransfers();
    response.complete(http.Response(utf8.decode([79, 75]), 200));
    await expectLater(
      task,
      throwsA(
        isA<AccountFailure>().having((e) => e.code, 'code', 'sync_cancelled'),
      ),
    );
  });
}
