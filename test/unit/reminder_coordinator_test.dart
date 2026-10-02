import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/reminders/application/reminder_coordinator.dart';
import 'package:memo_mind/features/reminders/application/reminder_tap_router.dart';
import 'package:memo_mind/features/reminders/domain/reminder_models.dart';
import 'package:timezone/data/latest_all.dart' as data;
import 'package:timezone/timezone.dart' as tz;

import '../support/reminder_fakes.dart';

void main() {
  data.initializeTimeZones();
  final initialNow = DateTime.utc(2026, 10, 2, 1);
  const settings = ReminderSettings(enabled: true, hour: 9, minute: 0);
  late DateTime now;
  late String zone;
  late FakeReminderRepository repository;
  late FakeNotificationGateway gateway;
  late FakeDueCardsSource source;
  late ReminderCoordinator coordinator;
  setUp(() {
    now = initialNow;
    zone = 'Asia/Ho_Chi_Minh';
    repository = FakeReminderRepository();
    gateway = FakeNotificationGateway();
    source = FakeDueCardsSource()..cards = [dueCard(now)];
    coordinator = ReminderCoordinator(
      repository: repository,
      gateway: gateway,
      dueCards: source,
      timeZone: () async => zone,
      clock: () => now,
    );
  });
  tearDown(() => coordinator.dispose());

  test('seven civil days; equality and passed times never register', () {
    final location = tz.getLocation(zone);
    final window = reminderWindow(settings, now, location);
    expect(window.occurrences.length, 7);
    expect(window.occurrences.first.key, 'review_due:2026-10-02');
    expect(window.occurrences.last.key, 'review_due:2026-10-08');
    expect(window.occurrences.first.scheduledAt, DateTime.utc(2026, 10, 2, 2));
    expect(
      reminderWindow(
        settings,
        DateTime.utc(2026, 10, 2, 2),
        location,
      ).occurrences.length,
      6,
    );
    expect(window.endAt, DateTime.utc(2026, 10, 8, 17));
  });
  test('DST uses calendar construction, not 24-hour arithmetic', () {
    final location = tz.getLocation('America/New_York');
    final occurrences = reminderWindow(
      settings,
      DateTime.utc(2026, 10, 31, 1),
      location,
    ).occurrences;
    expect(
      occurrences[1].scheduledAt.difference(occurrences[0].scheduledAt),
      const Duration(hours: 25),
    );
    expect(
      occurrences.map((o) => tz.TZDateTime.from(o.scheduledAt, location).hour),
      everyElement(9),
    );
    final spring = reminderWindow(
      settings,
      DateTime.utc(2026, 3, 7),
      location,
    ).occurrences;
    expect(
      spring[1].scheduledAt.difference(spring[0].scheduledAt),
      const Duration(hours: 23),
    );
  });
  test('validation accepts extremes; rejects missing and invalid time', () {
    expect(
      () => const ReminderSettings(enabled: true).validate(),
      throwsFormatException,
    );
    expect(
      () =>
          const ReminderSettings(enabled: true, hour: 24, minute: 0).validate(),
      throwsFormatException,
    );
    const ReminderSettings(enabled: true, hour: 0, minute: 0).validate();
    const ReminderSettings(enabled: true, hour: 23, minute: 59).validate();
  });
  test('idempotent reconciles keep seven reminders and stable keys', () async {
    await coordinator.save(settings);
    expect(coordinator.status, ReminderStatus.scheduled);
    expect(gateway.pending.length, 7);
    final ids = gateway.pending.keys.toSet();
    final calls = gateway.calls.length;
    await coordinator.reconcile();
    expect(gateway.pending.keys.toSet(), ids);
    expect(gateway.calls.length, calls);
    expect(repository.state.needsReconcile, isFalse);
    expect(repository.settings.lastKnownTimeZone, zone);
    expect(gateway.calls, isNot(contains('request')));
  });
  test(
    'predicted equality counts; later cards do not trigger earlier dates',
    () async {
      source.cards = [dueCard(DateTime.utc(2026, 10, 5, 2))];
      await coordinator.save(settings);
      expect(gateway.pending.length, 4);
      expect(repository.state.occurrences.first.key, 'review_due:2026-10-05');
    },
  );
  test(
    'no due cancels stale alarms; overdue cards remain predicted every day',
    () async {
      await coordinator.save(settings);
      source.cards = [];
      await coordinator.reconcile();
      expect(coordinator.status, ReminderStatus.noDue);
      expect(repository.settings.enabled, isTrue);
      expect(gateway.pending, isEmpty);
      source.cards = [dueCard(now.subtract(const Duration(days: 40)))];
      await coordinator.reconcile();
      expect(gateway.pending.length, 7);
    },
  );
  test(
    'change time replaces, disable cancels pending and displayed only FR16',
    () async {
      await coordinator.save(settings);
      final ids = gateway.pending.keys.toList();
      gateway.active.addAll([ids.first, 99]);
      gateway.pending[99] = ReminderOccurrence(
        id: 99,
        key: 'other',
        scheduledAt: now,
      );
      await coordinator.save(
        const ReminderSettings(enabled: true, hour: 10, minute: 30),
      );
      expect(
        gateway.pending[ids.first]!.scheduledAt,
        DateTime.utc(2026, 10, 2, 3, 30),
      );
      await coordinator.save(const ReminderSettings(hour: 10, minute: 30));
      expect(coordinator.status, ReminderStatus.disabled);
      expect(gateway.pending.keys, [99]);
      expect(gateway.active, {99});
    },
  );
  for (final appBlocked in [true, false]) {
    test(
      'blocked ${appBlocked ? 'app' : 'channel'} keeps intention without alarms',
      () async {
        await coordinator.save(settings);
        gateway.permission = NotificationAccess(
          appAllowed: !appBlocked,
          channelAllowed: appBlocked,
          canRequest: appBlocked,
        );
        await coordinator.reconcile(force: true);
        expect(coordinator.status, ReminderStatus.blocked);
        expect(repository.settings.enabled, isTrue);
        expect(gateway.pending, isEmpty);
        expect(gateway.calls, isNot(contains('request')));
        gateway.permission = const NotificationAccess(
          appAllowed: true,
          channelAllowed: true,
        );
        await coordinator.reconcile(force: true);
        expect(coordinator.status, ReminderStatus.scheduled);
      },
    );
  }
  test(
    'storage failure leaves previous settings and OS schedule unchanged',
    () async {
      await coordinator.save(settings);
      final alarms = Map.of(gateway.pending);
      repository.failSave = true;
      await expectLater(
        coordinator.save(const ReminderSettings()),
        throwsStateError,
      );
      expect(repository.settings.enabled, isTrue);
      expect(gateway.pending, alarms);
    },
  );
  test(
    'alarm and cancel failures stay dirty; next reconcile repairs',
    () async {
      gateway.failSchedule = true;
      await coordinator.save(settings);
      expect(coordinator.status, ReminderStatus.needsReconcile);
      expect(repository.state.needsReconcile, isTrue);
      expect(repository.settings.enabled, isTrue);
      gateway.failSchedule = false;
      await coordinator.reconcile(force: true);
      expect(gateway.pending.length, 7);
      gateway.failCancel = true;
      await coordinator.save(const ReminderSettings());
      expect(coordinator.status, ReminderStatus.needsReconcile);
      expect(repository.settings.enabled, isFalse);
      gateway.failCancel = false;
      await coordinator.reconcile(force: true);
      expect(coordinator.status, ReminderStatus.disabled);
      expect(gateway.pending, isEmpty);
    },
  );
  test('serialized save cannot be overwritten by an older reconcile', () async {
    await coordinator.save(settings);
    gateway.scheduleBarrier = Completer<void>();
    final refreshing = coordinator.reconcile(force: true);
    await Future<void>.delayed(Duration.zero);
    final disabling = coordinator.save(const ReminderSettings());
    final additional = coordinator.reconcile();
    gateway.scheduleBarrier!.complete();
    await Future.wait([refreshing, disabling, additional]);
    expect(repository.settings.enabled, isFalse);
    expect(coordinator.status, ReminderStatus.disabled);
    expect(gateway.pending, isEmpty);
  });
  test(
    'clock and zone changes rebuild future alarms; no backfill on reopen',
    () async {
      await coordinator.save(settings);
      final old = coordinator.nextReminder;
      zone = 'America/New_York';
      await coordinator.reconcile(force: true);
      expect(coordinator.nextReminder, isNot(old));
      now = now.add(const Duration(days: 12));
      gateway.pending
          .clear(); // Model force-stop/reboot with lost alarm registrations.
      await coordinator.reconcile(force: true);
      expect(gateway.pending.length, 6); // Local 09:00 has already passed.
      expect(
        gateway.pending.values.every((o) => o.scheduledAt.isAfter(now)),
        isTrue,
      );
    },
  );
  test(
    'platform/access/source/state failures never report scheduled success',
    () async {
      gateway.failAccess = true;
      await coordinator.save(settings);
      expect(coordinator.status, ReminderStatus.needsReconcile);
      gateway.failAccess = false;
      source.fail = true;
      await coordinator.reconcile();
      expect(coordinator.status, ReminderStatus.needsReconcile);
      source.fail = false;
      repository.failState = true;
      await coordinator.reconcile();
      expect(coordinator.status, ReminderStatus.needsReconcile);
      gateway.supported = false;
      await coordinator.reconcile();
      expect(coordinator.status, ReminderStatus.unsupported);
    },
  );
  test(
    'tap waits for readiness, deduplicates and refreshes an open route',
    () async {
      final ready = Completer<void>(), closed = Completer<void>();
      var opened = 0, refreshed = 0;
      final router = ReminderTapRouter(
        ready: () => ready.future,
        open: () async {
          opened++;
          await closed.future;
        },
        refresh: () => refreshed++,
        onError: (_) => fail('Unexpected navigation error'),
      );
      final first = router.handle();
      router.handle();
      expect(opened, 0);
      ready.complete();
      await Future<void>.delayed(Duration.zero);
      expect(opened, 1);
      router.handle();
      expect(refreshed, 1);
      closed.complete();
      await first;
    },
  );
  test('failed initialization/navigation is retryable', () async {
    var attempts = 0, errors = 0, opens = 0;
    final router = ReminderTapRouter(
      ready: () async {
        if (attempts++ == 0) throw StateError('Database unavailable');
      },
      open: () async {
        opens++;
      },
      refresh: () {},
      onError: (_) => errors++,
    );
    await router.handle();
    await router.handle();
    expect(errors, 1);
    expect(opens, 1);
  });
}
