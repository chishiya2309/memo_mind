import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../review/domain/due_cards_source.dart';
import '../domain/notification_gateway.dart';
import '../domain/reminder_models.dart';
import '../domain/reminder_settings_repository.dart';

class ReminderCoordinator extends ChangeNotifier {
  ReminderCoordinator({
    required this.repository,
    required this.gateway,
    required this.dueCards,
    required this.timeZone,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final ReminderSettingsRepository repository;
  final NotificationGateway gateway;
  final DueCardsSource dueCards;
  final Future<String> Function() timeZone;
  final DateTime Function() clock;
  ReminderSettings settings = const ReminderSettings();
  ReminderStatus status = ReminderStatus.disabled;
  NotificationAccess? permission;
  DateTime? nextReminder;
  Future<void>? _tail;
  Future<void>? _refresh;
  bool _requested = false, _force = false, _disposed = false;
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = (_tail ?? Future<void>.value()).then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _publish(ReminderStatus value) {
    status = value;
    if (!_disposed) notifyListeners();
  }

  Future<void> reconcile({bool force = false}) {
    _requested = true;
    _force |= force;
    if (_refresh != null) return _refresh!;
    final future = _serial(() async {
      do {
        _requested = false;
        final mustRegister = _force;
        _force = false;
        await _reconcile(force: mustRegister);
      } while (_requested);
    });
    _refresh = future;
    future.then(
      (_) => _refresh = null,
      onError: (Object _, StackTrace _) {
        _refresh = null;
      },
    );
    return future;
  }

  Future<void> save(ReminderSettings value) => _serial(() async {
    value.validate();
    await repository.saveSettings(value);
    settings = value;
    await _reconcile();
  });
  Future<NotificationAccess> checkPermission() async {
    permission = await gateway.access();
    return permission!;
  }

  Future<void> requestPermission() async {
    await gateway.requestPermission();
    await checkPermission();
  }

  Future<void> _reconcile({bool force = false}) async {
    if (!gateway.supported) {
      _publish(ReminderStatus.unsupported);
      return;
    }
    _publish(ReminderStatus.updating);
    var old = const ReminderSchedulingState(needsReconcile: true);
    nextReminder = null;
    try {
      settings = await repository.readSettings();
      old = await repository.readState();
      await repository.saveState(old.dirty());
      NotificationAccess? access;
      if (settings.enabled) {
        access = await checkPermission();
      } else {
        try {
          access = await checkPermission();
        } catch (_) {
          permission = null;
        }
      }
      final pending = await gateway.pendingIds();
      final managed = pending.where(ReminderOccurrence.ownsId).toSet()
        ..addAll(
          old.occurrences.map((o) => o.id).where(ReminderOccurrence.ownsId),
        );
      if (!settings.enabled || access?.allowed != true) {
        managed.addAll(
          (await gateway.activeIds()).where(ReminderOccurrence.ownsId),
        );
        for (final id in managed) {
          await gateway.cancel(id);
        }
        await repository.complete(settings, const ReminderSchedulingState());
        _publish(
          settings.enabled ? ReminderStatus.blocked : ReminderStatus.disabled,
        );
        return;
      }
      final zone = await timeZone();
      final window = reminderWindow(settings, clock(), tz.getLocation(zone));
      final cards = await dueCards.getDueCards(window.endAt);
      final wanted = window.occurrences
          .where(
            (o) => cards.any((c) => !c.card.dueDate.isAfter(o.scheduledAt)),
          )
          .toList();
      final wantedIds = wanted.map((o) => o.id).toSet();
      for (final id in managed.difference(wantedIds)) {
        await gateway.cancel(id);
      }
      final registered = <ReminderOccurrence>[];
      for (final occurrence in wanted) {
        if (!occurrence.scheduledAt.isAfter(clock())) {
          await gateway.cancel(occurrence.id);
          continue;
        }
        final previous = old.occurrences
            .where((o) => o.id == occurrence.id)
            .firstOrNull;
        if (force ||
            old.needsReconcile ||
            old.timeZone != zone ||
            !pending.contains(occurrence.id) ||
            previous?.scheduledAt != occurrence.scheduledAt) {
          await gateway.schedule(occurrence, zone);
        }
        registered.add(occurrence);
      }
      final confirmed = await gateway.pendingIds();
      if (!confirmed.containsAll(registered.map((o) => o.id))) {
        throw StateError('Lịch nhắc chưa được đăng ký đầy đủ.');
      }
      settings = settings.inZone(zone);
      await repository.complete(
        settings,
        ReminderSchedulingState(
          occurrences: registered,
          windowEndAt: window.endAt,
          timeZone: zone,
        ),
      );
      nextReminder = registered.firstOrNull?.scheduledAt;
      _publish(
        registered.isEmpty ? ReminderStatus.noDue : ReminderStatus.scheduled,
      );
    } catch (_) {
      try {
        await repository.saveState(old.dirty());
      } catch (_) {
        /* Retry on resume. */
      }
      _publish(ReminderStatus.needsReconcile);
    }
  }

  String get message {
    final hour = settings.hour?.toString().padLeft(2, '0') ?? '--';
    final minute = settings.minute?.toString().padLeft(2, '0') ?? '--';
    return switch (status) {
      ReminderStatus.disabled => 'Đã tắt nhắc học',
      ReminderStatus.updating => 'Đang cập nhật lịch nhắc…',
      ReminderStatus.blocked =>
        'Nhắc học chưa hoạt động vì chưa được cấp quyền',
      ReminderStatus.noDue =>
        'Đã bật nhắc học. Chưa có thẻ đến hạn trong 7 ngày tới',
      ReminderStatus.scheduled => 'Đã bật nhắc học lúc $hour:$minute',
      ReminderStatus.needsReconcile => 'Chưa cập nhật được lịch nhắc',
      ReminderStatus.unsupported => 'Nhắc học hiện hỗ trợ trên Android.',
    };
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
