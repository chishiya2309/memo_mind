import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/notification_gateway.dart';
import '../domain/reminder_models.dart';

class AndroidNotificationGateway implements NotificationGateway {
  AndroidNotificationGateway({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;
  void Function()? _onReviewDue;
  bool _launchConsumed = false;
  int? _sdkInt;
  static const _platform = MethodChannel('memo_mind/reminders');
  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  AndroidFlutterLocalNotificationsPlugin get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()!;

  Future<void> _configure() async {
    _sdkInt = await _platform.invokeMethod<int>('getSdkInt');
    if (_sdkInt == null) {
      throw StateError('Chưa kiểm tra được phiên bản Android.');
    }
    tzdata.initializeTimeZones();
    final initialized = await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_reminder'),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == reminderPayload) _onReviewDue?.call();
      },
    );
    if (initialized != true) throw StateError('Chưa khởi tạo được thông báo.');
    await _android.createNotificationChannel(
      const AndroidNotificationChannel(
        reminderChannelId,
        'Nhắc học',
        description: 'Thông báo nhắc ôn các thẻ đến hạn',
        importance: Importance.defaultImportance,
      ),
    );
  }

  Future<void> _ensure() async {
    if (!supported) {
      throw UnsupportedError('Nhắc học hiện hỗ trợ trên Android.');
    }
    _ready ??= _configure();
    try {
      await _ready;
    } catch (_) {
      _ready = null;
      rethrow;
    }
  }

  @override
  Future<bool> initialize(void Function() onReviewDue) async {
    _onReviewDue = onReviewDue;
    if (!supported) return false;
    await _ensure();
    if (_launchConsumed) return false;
    final launch = await _plugin.getNotificationAppLaunchDetails();
    _launchConsumed = true;
    return launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse?.payload == reminderPayload;
  }

  @override
  Future<NotificationAccess> access() async {
    await _ensure();
    final appAllowed = await _android.areNotificationsEnabled();
    final channels = await _android.getNotificationChannels();
    if (appAllowed == null || channels == null) {
      throw StateError('Chưa kiểm tra được quyền thông báo.');
    }
    final channel = channels
        .where((c) => c.id == reminderChannelId)
        .firstOrNull;
    if (_sdkInt! >= 26 && channel == null) {
      throw StateError('Chưa tìm thấy kênh nhắc học.');
    }
    final permission = await Permission.notification.status;
    return NotificationAccess(
      appAllowed: appAllowed,
      channelAllowed: _sdkInt! < 26 || channel!.importance != Importance.none,
      canRequest: _sdkInt! >= 33 && !appAllowed && permission.isDenied,
    );
  }

  @override
  Future<void> requestPermission() async {
    await _ensure();
    await _android.requestNotificationsPermission();
  }

  @override
  Future<void> openSettings() async {
    await _ensure();
    if (await _android.openAppNotificationSettings() != true) {
      throw StateError('Không thể mở cài đặt thiết bị.');
    }
  }

  @override
  Future<Set<int>> pendingIds() async {
    await _ensure();
    return (await _plugin.pendingNotificationRequests())
        .map((n) => n.id)
        .toSet();
  }

  @override
  Future<Set<int>> activeIds() async {
    await _ensure();
    return (await _plugin.getActiveNotifications())
        .map((n) => n.id)
        .whereType<int>()
        .toSet();
  }

  @override
  Future<void> cancel(int id) async {
    await _ensure();
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> schedule(ReminderOccurrence occurrence, String timeZone) async {
    await _ensure();
    await _plugin.zonedSchedule(
      id: occurrence.id,
      title: 'Đến giờ ôn tập',
      body: 'Mở MemoMind để xem các thẻ đến hạn',
      payload: reminderPayload,
      scheduledDate: tz.TZDateTime.from(
        occurrence.scheduledAt,
        tz.getLocation(timeZone),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          reminderChannelId,
          'Nhắc học',
          channelDescription: 'Thông báo nhắc ôn các thẻ đến hạn',
          icon: 'ic_stat_reminder',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          autoCancel: true,
        ),
      ),
    );
  }

  static Future<String> deviceTimeZone() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;
}
