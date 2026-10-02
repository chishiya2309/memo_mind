import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/reminders/data/android_notification_gateway.dart';
import 'package:memo_mind/features/reminders/domain/reminder_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  const platform = MethodChannel('memo_mind/reminders');
  var sdk = 34;
  late List<MethodCall> calls;
  late AndroidNotificationGateway gateway;
  var appAllowed = true, channelAllowed = true, coldLaunch = false;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    sdk = 34;
    messenger.setMockMethodCallHandler(platform, (_) async => sdk);
    calls = [];
    appAllowed = true;
    channelAllowed = true;
    coldLaunch = false;
    gateway = AndroidNotificationGateway();
    messenger.setMockMethodCallHandler(
      permissions,
      (call) async => appAllowed ? 1 : 0,
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'initialize' => true,
        'getNotificationAppLaunchDetails' => {
          'notificationLaunchedApp': coldLaunch,
          'notificationResponse': {
            'notificationId': 180261002,
            'notificationResponseType': 0,
            'payload': reminderPayload,
          },
        },
        'areNotificationsEnabled' => appAllowed,
        'getNotificationChannels' =>
          sdk < 26
              ? []
              : [
                  {
                    'id': reminderChannelId,
                    'name': 'Nhắc học',
                    'description': '',
                    'importance': channelAllowed ? 3 : 0,
                    'playSound': true,
                    'enableVibration': true,
                    'showBadge': true,
                    'enableLights': false,
                    'bypassDnd': false,
                    'ledColor': 0,
                  },
                ],
        'pendingNotificationRequests' => [
          {
            'id': 180261002,
            'title': 'Đến giờ ôn tập',
            'body': 'Mở MemoMind để xem các thẻ đến hạn',
            'payload': reminderPayload,
          },
        ],
        'getActiveNotifications' => [
          {'id': 180261002},
        ],
        'requestNotificationsPermission' ||
        'openAppNotificationSettings' => true,
        _ => null,
      };
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(permissions, null);
    messenger.setMockMethodCallHandler(platform, null);
  });
  test(
    'one-shot native arguments use inexact idle mode and routing-only payload',
    () async {
      await gateway.initialize(() {});
      await gateway.schedule(
        ReminderOccurrence(
          id: 180261002,
          key: 'review_due:2026-10-02',
          scheduledAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
        'Asia/Ho_Chi_Minh',
      );
      final call = calls.singleWhere((c) => c.method == 'zonedSchedule');
      final args = call.arguments as Map;
      expect(args['payload'], reminderPayload);
      expect(args['title'], 'Đến giờ ôn tập');
      expect(args['body'], 'Mở MemoMind để xem các thẻ đến hạn');
      expect(args.containsKey('matchDateTimeComponents'), isFalse);
      expect(args['timeZoneName'], 'Asia/Ho_Chi_Minh');
      expect(
        (args['platformSpecifics'] as Map)['scheduleMode'],
        AndroidScheduleMode.inexactAllowWhileIdle.name,
      );
      expect(await gateway.pendingIds(), {180261002});
      expect(await gateway.activeIds(), {180261002});
      await gateway.cancel(180261002);
      expect(calls.last.method, 'cancel');
      expect(calls.any((c) => c.method.contains('ExactAlarm')), isFalse);
      expect(
        calls.any((c) => c.method == 'requestNotificationsPermission'),
        isFalse,
      );
    },
  );
  test('channel blocking is independent from application permission', () async {
    expect((await gateway.access()).allowed, isTrue);
    channelAllowed = false;
    final blocked = await gateway.access();
    expect(blocked.appAllowed, isTrue);
    expect(blocked.allowed, isFalse);
    appAllowed = false;
    expect((await gateway.access()).canRequest, isTrue);
    await gateway.openSettings();
    expect(calls.last.method, 'openAppNotificationSettings');
  });
  test('Android 7 has no channels or runtime notification dialog', () async {
    sdk = 24;
    expect((await gateway.access()).allowed, isTrue);
    appAllowed = false;
    expect((await gateway.access()).canRequest, isFalse);
  });
  test('cold launch consumed once; running callback routes only review_due payload', () async {
    coldLaunch = true;
    var taps = 0;
    expect(await gateway.initialize(() => taps++), isTrue);
    expect(await gateway.initialize(() => taps++), isFalse);
    Future<void> tap(String payload) async {
      final done = Completer<void>();
      ServicesBinding.instance.channelBuffers.push(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('didReceiveNotificationResponse', {
            'notificationId': 180261002,
            'notificationResponseType': 0,
            'payload': payload,
          }),
        ),
        (_) => done.complete(),
      );
      await done.future;
    }

    await tap('other');
    expect(taps, 0);
    await tap(reminderPayload);
    expect(taps, 1);
  });
}
