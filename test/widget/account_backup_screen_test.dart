import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:memo_mind/core/workspace/workspace_context.dart';
import 'package:memo_mind/features/account_backup/application/account_backup_controller.dart';
import 'package:memo_mind/features/account_backup/presentation/account_backup_screen.dart';
import 'package:memo_mind/features/account_backup/domain/auth_repository.dart';
import 'package:memo_mind/features/account_backup/data/snapshot_codec.dart';

import '../support/account_backup_fakes.dart';

void main() {
  late Directory root;
  late WorkspaceRepository workspaces;
  late FakeAccountAuth auth;
  late AccountBackupController controller;
  late FakeBackupApi api;
  setUpAll(() {
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
    for (var i = 0; i < 15; i++) {
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
      expect(find.text('Xác minh email để sao lưu'), findsOneWidget);
      expect(find.textContaining('Tài khoản đã tạo.'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Gắn kho này với tài khoản'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Tôi đã xác minh'));
      await settleIo(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('a@example.com\n0 deck'), findsOneWidget);
      await tester.tap(find.text('Gắn và tiếp tục'));
      await settleIo(tester);
      expect(workspaces.current!.record.id, guest.id);
      expect(workspaces.current!.record.ownerUid, 'A');
      expect(auth.registrations, 1);
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
              find.widgetWithText(FilledButton, 'Sao lưu ngay / Thử lại'),
            )
            .onPressed,
        isNull,
      );
      final logout = find.widgetWithText(TextButton, 'Đăng xuất');
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(logout);
      await settleIo(tester);
      expect(find.text('Có dữ liệu chưa sao lưu'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng xuất'));
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
    'ready archive restores into a new vault only after switch confirmation',
    (tester) async {
      auth.change(
        const AccountIdentity(
          uid: 'A',
          email: 'a@example.com',
          emailVerified: true,
        ),
      );
      await tester.runAsync(
        () async => controller.select(await workspaces.preferred('A')),
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
      final menu = find.byType(PopupMenuButton<String>);
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Khôi phục'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.widgetWithText(FilledButton, 'Khôi phục vào kho mới'),
      );
      await settleIo(tester);
      for (
        var i = 0;
        i < 20 && find.text('Đã khôi phục').evaluate().isEmpty;
        i++
      ) {
        await settleIo(tester);
      }
      expect(find.text('Đã khôi phục'), findsOneWidget);
      expect(controller.workspace.record.id, original.id);
      await tester.tap(find.text('Chuyển kho'));
      await settleIo(tester);
      expect(controller.workspace.record.id, isNot(original.id));
      expect(
        (await tester.runAsync(() => workspaces.get(original.id)))!.status,
        'ready',
      );
    },
  );
}
