import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:memo_mind/core/workspace/workspace_context.dart';
import 'package:memo_mind/features/account_backup/domain/auth_repository.dart';
import 'package:memo_mind/features/deck_management/data/local_deck_repository.dart';
import 'package:memo_mind/features/sync/application/sync_controller.dart';

import '../support/account_backup_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late WorkspaceRepository workspaces;
  late FakeAccountAuth auth;
  late FakeSyncApi api;
  late SyncController sync;
  setUpAll(() {
    sqfliteFfiInit();
    sqlite.databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sync-scheduling-');
    workspaces = WorkspaceRepository(
      rootPath: p.join(root.path, 'files'),
      databaseRoot: p.join(root.path, 'db'),
    );
    await workspaces.initialize();
    auth = FakeAccountAuth(
      identity: const AccountIdentity(
        uid: 'A',
        email: 'a@example.com',
        emailVerified: true,
      ),
    );
    api = FakeSyncApi(auth);
    sync = SyncController(auth: auth, workspaces: workspaces, api: api);
    await workspaces.select(await sync.prepareAccount());
    await sync.bind();
  });
  tearDown(() async {
    sync.dispose();
    await auth.updates.close();
    await workspaces.close();
    await root.delete(recursive: true);
  });
  Future<void> edit() =>
      LocalDeckRepository(database: workspaces.current!.database)
          .createDeck(title: 'Local lesson');
  Future<void> until(bool Function() ready) async {
    for (var i = 0; i < 200 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(ready(), isTrue);
  }

  test(
    'manual default never sends on login, bind, resume, connectivity or edits',
    () async {
      expect(sync.automatic, isFalse);
      expect(sync.phase, SyncPhase.ready);
      await edit();
      sync.resumed();
      sync.connectivityRestored();
      sync.schedule(immediate: true);
      await Future<void>.delayed(const Duration(milliseconds: 3300));
      expect(api.requests, isEmpty);
      expect(sync.pendingChanges, isTrue);
      expect(sync.phase, SyncPhase.pending);
      await sync.syncNow();
      expect(sync.error, isNull);
      expect(await sync.hasPending, isFalse);
      api.requests.clear();
      await sync.syncNow();
      expect(api.requests.any((r) => r.contains('/changes')), isTrue);
    },
  );
  test('automatic preference survives controller restart and is isolated by account', () async {
    await sync.setAutomatic(true);
    await until(() => !sync.busy && sync.lastSynced != null);
    sync.dispose();
    sync = SyncController(auth: auth, workspaces: workspaces, api: api);
    final count = api.requests.length;
    await sync.bind();
    expect(sync.automatic, isTrue);
    await until(() => api.requests.length > count && !sync.busy);
    auth.change(
      const AccountIdentity(
        uid: 'B',
        email: 'b@example.com',
        emailVerified: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await workspaces.select(await sync.prepareAccount());
    await sync.bind();
    expect(sync.automatic, isFalse);
    auth.change(
      const AccountIdentity(
        uid: 'A',
        email: 'a@example.com',
        emailVerified: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await workspaces.select(await sync.prepareAccount());
    await sync.bind();
    expect(sync.automatic, isTrue);
    await sync.setAutomatic(false);
  });
  test('terminal authentication failure suppresses dirty polling and network triggers', () async {
    await edit();
    api.failure = const AccountFailure('reauth_required', 'Xác thực lại.');
    await sync.setAutomatic(true);
    await until(() => sync.requiresAuthentication && !sync.busy);
    final count = api.requests.length;
    sync.resumed();
    sync.connectivityRestored();
    await edit();
    await Future<void>.delayed(const Duration(milliseconds: 3300));
    expect(api.requests.length, count);
    expect(sync.requiresAuthentication, isTrue);
    expect(await sync.hasPending, isTrue);
    api.failure = null;
    await sync.syncNow();
    expect(sync.phase, SyncPhase.synced);
  });
  test(
    'manual failure does not retry, double tap joins no extra run',
    () async {
      api.holdRequest = Completer<void>();
      final first = sync.syncNow();
      await until(() => api.requests.isNotEmpty);
      await sync.syncNow();
      expect(api.requests.length, 1);
      api.failure = const AccountFailure('waiting_network', 'Offline');
      api.holdRequest!.complete();
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 5300));
      expect(api.requests.length, 1);
      expect(sync.phase, SyncPhase.failed);
    },
  );
}
