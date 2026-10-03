import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memo_mind/features/account_backup/data/backup_api_client.dart';
import 'package:memo_mind/features/account_backup/domain/auth_repository.dart';

import '../support/account_backup_fakes.dart';

void main() {
  test('unconfigured destination never receives token or requests', () async {
    final auth = FakeAccountAuth(
      identity: const AccountIdentity(
        uid: 'A',
        email: 'a@example.com',
        emailVerified: true,
      ),
    );
    var sent = false;
    final api = BackupApiClient(
      auth: auth,
      baseUrl: '',
      client: MockClient((_) async {
        sent = true;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      api.request('GET', '', uid: 'A'),
      throwsA(isA<AccountFailure>()),
    );
    expect(sent, isFalse);
  });
  test(
    'configured HTTPS receives bearer token; account mismatch cannot send',
    () async {
      final auth = FakeAccountAuth(
        identity: const AccountIdentity(
          uid: 'A',
          email: 'a@example.com',
          emailVerified: true,
        ),
      );
      var sent = 0;
      final api = BackupApiClient(
        auth: auth,
        baseUrl: 'https://configured.example/api',
        client: MockClient((request) async {
          sent++;
          expect(request.url.path, '/api/v1/backups');
          expect(request.headers['Authorization'], 'Bearer fake-token');
          return http.Response(jsonEncode({'backups': []}), 200);
        }),
      );
      await api.request('GET', '', uid: 'A');
      expect(sent, 1);
      await expectLater(
        api.request('GET', '', uid: 'B'),
        throwsA(isA<AccountFailure>()),
      );
      expect(sent, 1);
    },
  );
  test(
    'cloud access failures keep their own reauthentication error code',
    () async {
      final auth = FakeAccountAuth(
        identity: const AccountIdentity(
          uid: 'A',
          email: 'a@example.com',
          emailVerified: true,
        ),
      );
      final api = BackupApiClient(
        auth: auth,
        baseUrl: 'https://configured.example',
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(
              '{"error":"reauth_required","message":"Cần đăng nhập lại"}',
            ),
            401,
          ),
        ),
      );
      await expectLater(
        api.request('GET', '', uid: 'A'),
        throwsA(
          isA<AccountFailure>().having(
            (e) => e.code,
            'code',
            'reauth_required',
          ),
        ),
      );
    },
  );
}
