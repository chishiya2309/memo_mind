import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/app/app.dart';
import 'package:memo_mind/app/startup_welcome_controller.dart';
import 'package:memo_mind/app/startup_welcome_gate.dart';
import 'package:memo_mind/app/welcome_screen.dart';
import 'package:memo_mind/core/workspace/workspace_context.dart';
import 'package:memo_mind/features/home/domain/home_dashboard_data.dart';
import 'package:memo_mind/features/home/presentation/home_screen.dart';
import 'package:memo_mind/features/reminders/domain/reminder_models.dart';
import 'package:memo_mind/features/review/presentation/due_cards_screen.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const native = MethodChannel('memo_mind/reminders');
  const timezone = MethodChannel('flutter_timezone');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  late Directory root;
  late WorkspaceRepository workspaces;
  late StartupWelcomeController welcome;
  late Completer<void> cacheReady;
  var coldNotification = false;
  var launchRead = false;
  var readyCount = 0;

  setUpAll(() {
    sqfliteFfiInit();
    sqlite.databaseFactory = databaseFactoryFfi;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    root = await Directory.systemTemp.createTemp('memo-startup-widget-');
    workspaces = WorkspaceRepository(
      rootPath: p.join(root.path, 'support'),
      databaseRoot: p.join(root.path, 'db'),
    );
    await workspaces.initialize();
    await Directory(p.join(root.path, 'cache')).create();
    welcome = StartupWelcomeController();
    cacheReady = Completer<void>();
    coldNotification = false;
    launchRead = false;
    readyCount = 0;
    messenger.setMockMethodCallHandler(paths, (call) async {
      if (call.method == 'getTemporaryDirectory') {
        await cacheReady.future;
        return p.join(root.path, 'cache');
      }
      return p.join(root.path, 'support');
    });
    messenger.setMockMethodCallHandler(native, (_) async => 36);
    messenger.setMockMethodCallHandler(
      timezone,
      (_) async => 'Asia/Ho_Chi_Minh',
    );
    messenger.setMockMethodCallHandler(permissions, (_) async => 1);
    messenger.setMockMethodCallHandler(notifications, (call) async {
      if (call.method == 'getNotificationAppLaunchDetails') launchRead = true;
      return switch (call.method) {
        'initialize' => true,
        'getNotificationAppLaunchDetails' => {
          'notificationLaunchedApp': coldNotification,
          'notificationResponse': {
            'notificationId': 180261002,
            'notificationResponseType': 0,
            'payload': reminderPayload,
          },
        },
        'areNotificationsEnabled' => true,
        'getNotificationChannels' ||
        'pendingNotificationRequests' ||
        'getActiveNotifications' => [],
        _ => null,
      };
    });
  });
  tearDown(() async {
    welcome.dispose();
    for (final channel in [
      paths,
      notifications,
      native,
      timezone,
      permissions,
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    debugDefaultTargetPlatformOverride = null;
    await workspaces.close();
    await root.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    });
    await tester.pumpWidget(
      StartupWelcomeGate(
        controller: welcome,
        onRetry: () {},
        child: MemoMindApp(
          startupRevealed: welcome.startupRevealed,
          onStartupReady: () {
            readyCount++;
            welcome.markReady();
          },
        ),
      ),
    );
  }

  Future<void> settleIo(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(ready(), isTrue, reason: 'Startup I/O did not settle');
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
    // Let reminder reconciliation finish before closing the temporary DB.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }

  testWidgets('readiness waits for recovery and reports once across resume', (
    tester,
  ) async {
    await open(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(readyCount, 0);
    expect(find.text('Đang chuẩn bị không gian học…'), findsOneWidget);
    cacheReady.complete();
    await settleIo(tester, () => readyCount == 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 251));
    await tester.pump();
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(
      tester.widget<HomeScreen>(find.byType(HomeScreen)).data.loadState,
      HomeLoadState.ready,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(readyCount, 1);
    await close(tester);
  });

  testWidgets('dashboard failure reveals the existing error UI', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await (await workspaces.current!.database.database).execute(
        'DROP TABLE decks',
      );
    });
    cacheReady.complete();
    await open(tester);
    await settleIo(tester, () => readyCount == 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 251));
    await tester.pump();
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(
      tester.widget<HomeScreen>(find.byType(HomeScreen)).data.loadState,
      HomeLoadState.error,
    );
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets(
    'notification cold launch opens due cards only after welcome closes',
    (tester) async {
      coldNotification = true;
      cacheReady.complete();
      await open(tester);
      await settleIo(tester, () => readyCount == 1 && launchRead);
      expect(find.byType(DueCardsScreen), findsNothing);
      expect(welcome.visible, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(DueCardsScreen), findsNothing);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 251));
      await settleIo(
        tester,
        () => find.text('Bạn chưa có thẻ đến hạn').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.byType(DueCardsScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      // Home starts fresh SQLite/statistics reads when its route becomes
      // visible. Finish the route animation, then allow real I/O to run.
      await tester.pump(const Duration(milliseconds: 350));
      await settleIo(
        tester,
        () => find.byType(HomeScreen).evaluate().isNotEmpty,
      );
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      await close(tester);
    },
  );
}
