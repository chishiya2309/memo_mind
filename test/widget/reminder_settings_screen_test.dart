import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/reminders/application/reminder_coordinator.dart';
import 'package:memo_mind/features/reminders/domain/reminder_models.dart';
import 'package:memo_mind/features/reminders/presentation/profile_settings_screen.dart';
import 'package:memo_mind/features/reminders/presentation/reminder_settings_screen.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import '../support/reminder_fakes.dart';

void main() {
  tzdata.initializeTimeZones();
  late FakeReminderRepository repository;
  late FakeNotificationGateway gateway;
  late FakeDueCardsSource source;
  late ReminderCoordinator coordinator;
  setUp(() {
    repository = FakeReminderRepository();
    gateway = FakeNotificationGateway();
    source = FakeDueCardsSource();
    coordinator = ReminderCoordinator(
      repository: repository,
      gateway: gateway,
      dueCards: source,
      timeZone: () async => 'Asia/Ho_Chi_Minh',
      clock: () => DateTime.utc(2026, 10, 2, 1),
    );
  });
  tearDown(() => coordinator.dispose());
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ReminderSettingsScreen(coordinator: coordinator)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Lưu'));
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
  }

  testWidgets('default is off with no time; enabling requires a time', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Chưa chọn giờ'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await save(tester);
    expect(
      find.text('Vui lòng chọn giờ trong khoảng 00:00–23:59.'),
      findsOneWidget,
    );
    expect(repository.settings.enabled, isFalse);
  });
  testWidgets(
    'time picker changes draft, save persists and displays next occurrence',
    (tester) async {
      repository.settings = const ReminderSettings(hour: 9, minute: 0);
      source.cards = [dueCard(DateTime.utc(2026, 10, 2))];
      await pump(tester);
      await tester.tap(find.text('Giờ nhắc hằng ngày'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '10');
      await tester.enterText(fields.at(1), '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(repository.settings.hour, 9);
      await tester.tap(find.byType(SwitchListTile));
      await save(tester);
      expect(repository.settings.hour, 10);
      expect(repository.settings.minute, 30);
      expect(repository.settings.enabled, isTrue);
      expect(find.text('Đã bật nhắc học lúc 10:30'), findsWidgets);
      expect(find.textContaining('Lần nhắc tiếp theo:'), findsOneWidget);
    },
  );
  testWidgets('leave without saving preserves configuration and alarms', (
    tester,
  ) async {
    repository.settings = const ReminderSettings(hour: 9, minute: 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    ReminderSettingsScreen(coordinator: coordinator),
              ),
            ),
            child: const Text('Mở'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.ensureVisible(find.text('Hủy'));
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(repository.settings.enabled, isFalse);
    expect(repository.settings.hour, 9);
    expect(gateway.pending, isEmpty);
  });
  testWidgets(
    'denied permission saves intention; returning from settings reschedules',
    (tester) async {
      repository.settings = const ReminderSettings(hour: 9, minute: 0);
      gateway.permission = const NotificationAccess(
        appAllowed: false,
        channelAllowed: true,
        canRequest: true,
      );
      source.cards = [dueCard(DateTime.utc(2026, 10, 2))];
      await pump(tester);
      expect(gateway.calls, isNot(contains('request')));
      await tester.tap(find.byType(SwitchListTile));
      await save(tester);
      expect(find.text('Cho phép nhắc học'), findsOneWidget);
      await tester.tap(find.text('Để sau'));
      await tester.pumpAndSettle();
      expect(repository.settings.enabled, isTrue);
      expect(gateway.pending, isEmpty);
      expect(
        find.text('Nhắc học chưa hoạt động vì chưa được cấp quyền'),
        findsWidgets,
      );
      await tester.ensureVisible(find.text('Mở cài đặt thiết bị'));
      await tester.tap(find.text('Mở cài đặt thiết bị'));
      await tester.pumpAndSettle();
      expect(gateway.calls, contains('settings'));
      gateway.permission = const NotificationAccess(
        appAllowed: true,
        channelAllowed: true,
      );
      await coordinator.reconcile(force: true);
      await tester.pumpAndSettle();
      expect(gateway.pending.length, 7);
      expect(gateway.calls, isNot(contains('request')));
    },
  );
  testWidgets(
    'explicit consent requests permission once; no due has truthful status',
    (tester) async {
      repository.settings = const ReminderSettings(hour: 9, minute: 0);
      gateway.permission = const NotificationAccess(
        appAllowed: false,
        channelAllowed: true,
        canRequest: true,
      );
      await pump(tester);
      await tester.tap(find.byType(SwitchListTile));
      await save(tester);
      gateway.permission = const NotificationAccess(
        appAllowed: true,
        channelAllowed: true,
      );
      await tester.tap(find.text('Tiếp tục'));
      await tester.pumpAndSettle();
      expect(gateway.calls.where((c) => c == 'request').length, 1);
      expect(coordinator.status, ReminderStatus.noDue);
      expect(gateway.pending, isEmpty);
    },
  );
  testWidgets('save and scheduling errors do not show success', (tester) async {
    repository.settings = const ReminderSettings(hour: 9, minute: 0);
    repository.failSave = true;
    await pump(tester);
    await tester.tap(find.byType(SwitchListTile));
    await save(tester);
    expect(find.text('Chưa lưu được cài đặt nhắc học'), findsOneWidget);
    expect(repository.settings.enabled, isFalse);
    repository.failSave = false;
    gateway.failSchedule = true;
    source.cards = [dueCard(DateTime.utc(2026, 10, 2))];
    await save(tester);
    expect(find.text('Chưa cập nhật được lịch nhắc'), findsWidgets);
    expect(repository.settings.enabled, isTrue);
  });
  testWidgets('profile opens settings then reminders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileSettingsScreen(coordinator: coordinator)),
    );
    await tester.tap(find.text('Cài đặt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhắc học'));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsOneWidget);
  });
  testWidgets('unsupported platform shows explanation', (tester) async {
    gateway.supported = false;
    await pump(tester);
    expect(find.text('Nhắc học hiện hỗ trợ trên Android.'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
  });
  testWidgets(
    'failed settings read cannot overwrite saved intention with defaults',
    (tester) async {
      repository.settings = const ReminderSettings(
        enabled: true,
        hour: 9,
        minute: 0,
      );
      repository.failRead = true;
      await pump(tester);
      expect(find.text('Không thể tải cài đặt nhắc học'), findsOneWidget);
      expect(find.text('Lưu'), findsNothing);
      repository.failRead = false;
      await tester.tap(find.text('Thử tải lại'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(repository.settings.enabled, isTrue);
    },
  );
}
