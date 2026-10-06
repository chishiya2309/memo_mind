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
import 'package:memo_mind/features/account_backup/data/snapshot_codec.dart';

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

  Future<void> seedMedia() async {
    final file = File(
      p.join(
        workspaces.current!.record.filesPath,
        'documents',
        'doc',
        'image.png',
      ),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString('test source');
    await workspaces.current!.database.studyTransaction((txn) async {
      await txn.insert('documents', {
        'document_id': 'doc',
        'title': 'Source',
        'status': 'pending_ocr',
        'page_count': 1,
        'created_at': 1,
        'updated_at': 1,
      });
      await txn.insert('source_pages', {
        'page_id': 'page',
        'document_id': 'doc',
        'page_number': 1,
        'original_page_number': 1,
        'source': 'gallery',
        'data_relative_path': 'documents/doc/image.png',
        'mime_type': 'image/png',
        'file_size_bytes': await file.length(),
        'width': 2,
        'height': 2,
        'sha256': await fileHash(file),
        'quality_code': 'good',
        'quality_warning_accepted': 0,
        'created_at': 1,
        'normalization_status': 'source_ready',
      });
    });
  }

  test(
    'expired URL refreshes once and confirmed files are skipped on retry',
    () async {
      await seedMedia();
      api.uploadFailures.add(
        const AccountFailure('storage_url_expired', 'Expired'),
      );
      await sync.syncNow();
      expect(api.uploads, 2);
      expect(sync.phase, SyncPhase.synced);
      await sync.syncNow();
      expect(api.uploads, 2);
    },
  );
  test('repeated expiration stops after two uploads and preserves progress on restart', () async {
    await seedMedia();
    api.uploadFailures.addAll(
      List.filled(2, const AccountFailure('storage_url_expired', 'Expired')),
    );
    await sync.syncNow();
    expect(api.uploads, 2);
    expect(sync.phase, SyncPhase.blocked);
    expect(sync.mediaPhase, SyncMediaPhase.pending);
    final last = sync.lastSynced;
    expect(last, isNotNull);
    sync.dispose();
    sync = SyncController(auth: auth, workspaces: workspaces, api: api);
    await sync.bind();
    expect(
      sync.lastSynced?.millisecondsSinceEpoch,
      last?.millisecondsSinceEpoch,
    );
    expect(sync.mediaPhase, SyncMediaPhase.pending);
    expect(await sync.hasPending, isTrue);
    await sync.syncNow();
    expect(sync.mediaPhase, SyncMediaPhase.idle);
  });
  test(
    'account change during expired upload prevents refreshing its URL',
    () async {
      await seedMedia();
      api.uploadFailures.add(
        const AccountFailure('storage_url_expired', 'Expired'),
      );
      api.onUpload = () => auth.change(null);
      await sync.syncNow();
      expect(api.uploads, 1);
      expect(api.requests.where((r) => r.startsWith('POST /files/')).length, 1);
      expect(sync.requiresAuthentication, isFalse);
    },
  );
  for (final code in [
    'storage_not_configured',
    'storage_signature_invalid',
    'storage_checksum_mismatch',
  ]) {
    test(
      '$code stops automatic retries while keeping synced progress',
      () async {
        await seedMedia();
        api.uploadFailures.add(AccountFailure(code, 'Storage error'));
        await sync.setAutomatic(true);
        await until(() => !sync.busy && sync.failureCode == code);
        expect(sync.lastSynced, isNotNull);
        sync.resumed();
        sync.connectivityRestored();
        await Future<void>.delayed(const Duration(milliseconds: 5300));
        expect(api.uploads, 1);
        expect(sync.phase, SyncPhase.blocked);
      },
    );
  }

  test('temporary storage failure automatically retries media', () async {
    await seedMedia();
    api.uploadFailures.add(
      const AccountFailure('storage_unavailable', 'Temporary'),
    );
    await sync.setAutomatic(true);
    await until(() => !sync.busy && sync.failureCode == 'storage_unavailable');
    expect(sync.status, 'Chưa đồng bộ đủ ảnh và PDF');
    await Future<void>.delayed(const Duration(seconds: 6));
    await until(() => !sync.busy && sync.phase == SyncPhase.synced);
    expect(api.uploads, 2);
    expect(sync.mediaPhase, SyncMediaPhase.idle);
  });

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
