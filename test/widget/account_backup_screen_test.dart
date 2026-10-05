import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:memo_mind/core/workspace/workspace_context.dart';
import 'package:memo_mind/features/account_backup/application/account_backup_controller.dart';
import 'package:memo_mind/features/account_backup/presentation/account_backup_screen.dart';
import 'package:memo_mind/features/account_backup/domain/auth_repository.dart';
import 'package:memo_mind/features/account_backup/data/snapshot_codec.dart';
import 'package:memo_mind/features/sync/application/sync_controller.dart';

import '../support/account_backup_fakes.dart';

void main() {
  late Directory root;
  late WorkspaceRepository workspaces;
  late FakeAccountAuth auth;
  late AccountBackupController controller;
  late FakeBackupApi api;
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('memo_mind/connectivity'),
          (_) async => null,
        );
    sqfliteFfiInit();
    sqlite.databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('fr18-widget-');
    workspaces = WorkspaceRepository(
      rootPath: p.join(root.path, 'files'),
      databaseRoot: p.join(root.path, 'db'),
    );
    await workspaces.initialize();
    auth = FakeAccountAuth();
    api = FakeBackupApi(auth);
    controller = AccountBackupController(
      auth: auth,
      workspaces: workspaces,
      api: api,
      syncController: SyncController(
        auth: auth,
        workspaces: workspaces,
        api: FakeSyncApi(auth),
      ),
    );
  });
  tearDown(() async {
    controller.dispose();
    await auth.updates.close();
    await workspaces.close();
    await root.delete(recursive: true);
  });
  Future<void> open(WidgetTester tester) async => tester.pumpWidget(
    MaterialApp(home: AccountBackupScreen(controller: controller)),
  );
  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('required and invalid fields do not send login', (tester) async {
    await open(tester);
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập email hợp lệ'), findsOneWidget);
    expect(find.text('Nhập mật khẩu'), findsOneWidget);
    expect(auth.logins, 0);
    await tester.enterText(find.byType(TextFormField).first, 'invalid');
    await tester.enterText(find.byType(TextFormField).last, 'password');
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();
    expect(auth.logins, 0);
  });
  testWidgets(
    'registration validates length and confirmation before Firebase',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Tạo tài khoản'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'a@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'short');
      await tester.enterText(find.byType(TextFormField).at(2), 'short');
      await tester.tap(find.widgetWithText(FilledButton, 'Tạo tài khoản'));
      await tester.pumpAndSettle();
      expect(find.text('Mật khẩu mới tối thiểu 8 ký tự'), findsOneWidget);
      expect(auth.registrations, 0);
      await tester.enterText(find.byType(TextFormField).at(1), ' password ');
      await tester.enterText(find.byType(TextFormField).at(2), 'password');
      await tester.tap(find.widgetWithText(FilledButton, 'Tạo tài khoản'));
      await tester.pumpAndSettle();
      expect(find.text('Mật khẩu xác nhận không khớp'), findsOneWidget);
      expect(auth.registrations, 0);
    },
  );
  testWidgets('cancelled Google leaves guest ownership and data unchanged', (
    tester,
  ) async {
    final before = workspaces.current;
    await open(tester);
    await tester.tap(find.text('Đăng nhập bằng Google'));
    await tester.pumpAndSettle();
    expect(workspaces.current, same(before));
    expect(workspaces.current!.record.ownerUid, isNull);
    expect(auth.current, isNull);
    expect(find.text('Sao lưu thành công'), findsNothing);
  });
  testWidgets(
    'verification delivery failure keeps one account; attach needs verified consent',
    (tester) async {
      auth.verificationFails = true;
      final guest = workspaces.current!.record;
      await tester.runAsync(() async {
        final guestDb = await workspaces.current!.database.database;
        await guestDb.insert('decks', {
          'deck_id': 'guest-deck',
          'title': 'Guest lesson',
          'created_at': 1,
          'updated_at': 1,
        });
      });
      await open(tester);
      await tester.tap(find.text('Tạo tài khoản'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'a@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), ' password ');
      await tester.enterText(find.byType(TextFormField).at(2), ' password ');
      await tester.tap(find.widgetWithText(FilledButton, 'Tạo tài khoản'));
      await settleIo(tester);
      expect(auth.registrations, 1);
      expect(auth.suppliedPassword, ' password ');
      expect(workspaces.current!.record.ownerUid, isNull);
      expect(find.text('Xác minh email để đồng bộ'), findsOneWidget);
      expect(find.textContaining('Tài khoản đã tạo.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Đồng bộ ngay'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Tôi đã xác minh'));
      await settleIo(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('a@example.com\n1 bộ thẻ'), findsOneWidget);
      await tester.tap(find.text('Thêm vào tài khoản'));
      await settleIo(tester);
      expect(workspaces.current!.record.id, isNot(guest.id));
      expect(workspaces.current!.record.ownerUid, 'A');
      expect(
        (await tester.runAsync(() => workspaces.get(guest.id)))!.ownerUid,
        isNull,
      );
      expect(auth.registrations, 1);
      await tester.runAsync(() => controller.sync.bind());
    },
  );
  testWidgets(
    'unverified cloud is disabled; logout confirmation opens a guest vault',
    (tester) async {
      auth.change(
        const AccountIdentity(
          uid: 'A',
          email: 'a@example.com',
          emailVerified: false,
        ),
      );
      await tester.runAsync(
        () async => controller.select(await workspaces.preferred('A')),
      );
      final ownedId = controller.workspace.record.id;
      await open(tester);
      await settleIo(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Đồng bộ ngay'),
            )
            .onPressed,
        isNull,
      );
      final logout = find.widgetWithText(TextButton, 'Đăng xuất');
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(logout);
      await settleIo(tester);
      expect(auth.current, isNull);
      expect(controller.workspace.record.ownerUid, isNull);
      expect(
        (await tester.runAsync(() => workspaces.get(ownedId)))!.ownerUid,
        'A',
      );
    },
  );
  testWidgets(
    'recovery history is advanced; restore preview warns about other devices without changing the library',
    (tester) async {
      auth.change(
        const AccountIdentity(
          uid: 'A',
          email: 'a@example.com',
          emailVerified: true,
        ),
      );
      await tester.runAsync(
        () async => controller.select(await workspaces.canonical('A')),
      );
      final original = controller.workspace.record;
      final snapshot = (await tester.runAsync(
        () => SnapshotCodec().capture(controller.workspace, 'A'),
      ))!;
      api.registered = {...snapshot.request};
      api.jobStatus = 'ready';
      api.downloadArchive = File(snapshot.path);
      await open(tester);
      await settleIo(tester);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      await tester.ensureVisible(find.text('Nâng cao'));
      await tester.tap(find.text('Nâng cao'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Lịch sử khôi phục'));
      await tester.tap(find.text('Lịch sử khôi phục'));
      await settleIo(tester);
      final menu = find.byType(PopupMenuButton<String>);
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xem và khôi phục'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.textContaining('đồng bộ sang các thiết bị khác'),
        findsOneWidget,
      );
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(controller.workspace.record.id, original.id);
      expect(
        (await tester.runAsync(() => workspaces.get(original.id)))!.status,
        'ready',
      );
    },
  );
}
