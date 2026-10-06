import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memo_mind/features/account_backup/data/backup_api_client.dart';
import 'package:memo_mind/features/account_backup/domain/auth_repository.dart';

import '../support/account_backup_fakes.dart';

void main() {
  late FakeAccountAuth auth;
  setUp(
    () => auth = FakeAccountAuth(
      identity: const AccountIdentity(
        uid: 'A',
        email: 'a@example.com',
        emailVerified: true,
      ),
    ),
  );
  tearDown(() => auth.updates.close());
  BackupApiClient client(MockClient transport) => BackupApiClient(
    auth: auth,
    baseUrl: 'https://example.test',
    client: transport,
  );

  for (final code in ['token_expired', 'token_invalid', 'reauth_required']) {
    test('$code refreshes once and replays the identical operation', () async {
      final requests = <http.Request>[];
      final api = client(
        MockClient((request) async {
          requests.add(request);
          return requests.length == 1
              ? http.Response(jsonEncode({'error': code}), 401)
              : http.Response('{"ok":true}', 200);
        }),
      );
      expect(
        await api.request(
          'POST',
          '/push',
          uid: 'A',
          body: {'groupId': 'same-id', 'operations': []},
        ),
        {'ok': true},
      );
      expect(auth.tokenRefreshes, [false, true]);
      expect(requests[0].body, requests[1].body);
      expect(requests[1].headers['Authorization'], 'Bearer refreshed-token');
    });
  }
  test('persistent rejection is actionable and never loops', () async {
    var attempts = 0;
    final api = client(
      MockClient((_) async {
        attempts++;
        return http.Response('{"error":"token_invalid"}', 401);
      }),
    );
    await expectLater(
      api.request('GET', '/status', uid: 'A'),
      throwsA(
        isA<AccountFailure>().having((e) => e.code, 'code', 'reauth_required'),
      ),
    );
    expect(attempts, 2);
  });
  test('service failure does not refresh or ask for authentication', () async {
    final api = client(
      MockClient(
        (_) async => http.Response('{"error":"auth_service_unavailable"}', 503),
      ),
    );
    await expectLater(
      api.request('GET', '/status', uid: 'A'),
      throwsA(
        isA<AccountFailure>().having(
          (e) => e.code,
          'code',
          'auth_service_unavailable',
        ),
      ),
    );
    expect(auth.tokenRefreshes, [false]);
  });
  test('account change during refresh never sends a second request', () async {
    var requests = 0;
    auth.onToken = (refresh) async {
      if (refresh) {
        auth.change(
          const AccountIdentity(
            uid: 'B',
            email: 'b@example.com',
            emailVerified: true,
          ),
        );
      }
    };
    final api = client(
      MockClient((_) async {
        requests++;
        return http.Response('{"error":"token_expired"}', 401);
      }),
    );
    await expectLater(
      api.request('POST', '/push', uid: 'A', body: {'groupId': 'a'}),
      throwsA(
        isA<AccountFailure>().having((e) => e.code, 'code', 'sync_cancelled'),
      ),
    );
    expect(requests, 1);
  });
  test(
    'cancel during token refresh prevents replay even for the same UID',
    () async {
      var requests = 0;
      late BackupApiClient api;
      auth.onToken = (refresh) async {
        if (refresh) api.cancelTransfers();
      };
      api = client(
        MockClient((_) async {
          requests++;
          return http.Response('{"error":"token_expired"}', 401);
        }),
      );
      await expectLater(
        api.request('GET', '/status', uid: 'A'),
        throwsA(
          isA<AccountFailure>().having((e) => e.code, 'code', 'sync_cancelled'),
        ),
      );
      expect(requests, 1);
    },
  );

  test(
    'gateway HTML response is a service failure, not a login failure',
    () async {
      final api = client(
        MockClient((_) async => http.Response('<html>Unavailable</html>', 502)),
      );
      await expectLater(
        api.request('GET', '/status', uid: 'A'),
        throwsA(
          isA<AccountFailure>().having(
            (e) => e.code,
            'code',
            'service_unavailable',
          ),
        ),
      );
      expect(auth.tokenRefreshes, [false]);
    },
  );
}
