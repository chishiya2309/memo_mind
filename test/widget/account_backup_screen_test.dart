import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:memo_mind/core/workspace/workspace_context.dart';
import 'package:memo_mind/features/account_backup/application/account_backup_controller.dart';
import 'package:memo_mind/features/account_backup/presentation/account_backup_screen.dart';

import '../support/account_backup_fakes.dart';

void main() {
  late Directory root;
  late WorkspaceRepository workspaces;
  late FakeAccountAuth auth;
  late AccountBackupController controller;
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
    controller = AccountBackupController(
      auth: auth,
      workspaces: workspaces,
      api: FakeBackupApi(auth),
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
}
