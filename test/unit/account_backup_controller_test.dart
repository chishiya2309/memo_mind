import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:memo_mind/core/workspace/workspace_context.dart';
import 'package:memo_mind/features/account_backup/application/account_backup_controller.dart';
import 'package:memo_mind/features/account_backup/domain/auth_repository.dart';
import 'package:memo_mind/features/deck_management/data/local_deck_repository.dart';

import '../support/account_backup_fakes.dart';

void main() {
  late Directory root;
  late WorkspaceRepository workspaces;
  late FakeAccountAuth auth;
  late FakeBackupApi api;
  late AccountBackupController controller;
  setUpAll(() {
    sqfliteFfiInit();
    sqlite.databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('fr18-controller-');
    workspaces = WorkspaceRepository(
      rootPath: p.join(root.path, 'files'),
      databaseRoot: p.join(root.path, 'db'),
    );
    await workspaces.initialize();
    await workspaces.select(
      await workspaces.attach(workspaces.current!.record.id, 'A'),
    );
    auth = FakeAccountAuth(
      identity: const AccountIdentity(
        uid: 'A',
        email: 'a@example.com',
        emailVerified: true,
      ),
    );
    api = FakeBackupApi(auth);
    controller = AccountBackupController(
      auth: auth,
      workspaces: workspaces,
      api: api,
    );
  });
  tearDown(() async {
    controller.dispose();
    await auth.updates.close();
    await workspaces.close();
    await root.delete(recursive: true);
  });
  test(
    'double tap creates one job; edits during upload remain local and dirty',
    () async {
      api.holdUpload = Completer<void>();
      final backup = controller.backup();
      await api.uploading.future;
      expect(controller.canBackup, isFalse);
      expect(controller.busy, isTrue);
      await expectLater(controller.backup(), throwsA(isA<AccountFailure>()));
      await LocalDeckRepository().createDeck(title: 'After snapshot');
      api.holdUpload!.complete();
      await backup;
      expect(api.begins, 1);
      expect(api.finalizes, 1);
      expect(await controller.hasChanges(), isTrue);
      expect(controller.status, contains('Có dữ liệu mới'));
      expect(
        (await LocalDeckRepository().getDecks()).single.title,
        'After snapshot',
      );
    },
  );
  test('late completion for A cannot appear as success for B', () async {
    api.holdFinalize = Completer<void>();
    final backup = controller.backup();
    await api.uploading.future;
    while (api.finalizes == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    auth.change(
      const AccountIdentity(
        uid: 'B',
        email: 'b@example.com',
        emailVerified: true,
      ),
    );
    await controller.select(await workspaces.preferred('B'));
    api.holdFinalize!.complete();
    await backup;
    expect(controller.workspace.record.ownerUid, 'B');
    expect(controller.backups, isEmpty);
    expect(controller.status, 'Chưa sao lưu');
    final jobs = await workspaces.registry.query('backup_jobs');
    expect(jobs.single['owner_uid'], 'A');
  });
  test('unverified and guest workspaces cannot begin cloud backup', () async {
    auth.change(
      const AccountIdentity(
        uid: 'A',
        email: 'a@example.com',
        emailVerified: false,
      ),
    );
    await expectLater(controller.backup(), throwsA(isA<AccountFailure>()));
    auth.change(
      const AccountIdentity(
        uid: 'A',
        email: 'a@example.com',
        emailVerified: true,
      ),
    );
    await controller.select(await workspaces.preferred(null));
    await expectLater(controller.backup(), throwsA(isA<AccountFailure>()));
    expect(api.begins, 0);
  });
}
