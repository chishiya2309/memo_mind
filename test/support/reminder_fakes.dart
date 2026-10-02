import 'dart:async';

import 'package:memo_mind/features/deck_management/domain/deck_models.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/reminders/domain/notification_gateway.dart';
import 'package:memo_mind/features/reminders/domain/reminder_models.dart';
import 'package:memo_mind/features/reminders/domain/reminder_settings_repository.dart';
import 'package:memo_mind/features/review/domain/due_cards_source.dart';

class FakeReminderRepository implements ReminderSettingsRepository {
  ReminderSettings settings = const ReminderSettings();
  ReminderSchedulingState state = const ReminderSchedulingState();
  bool failSave = false, failState = false;
  bool failRead = false;
  @override
  Future<ReminderSettings> readSettings() async {
    if (failRead) throw StateError('Read failure');
    return settings;
  }

  @override
  Future<ReminderSchedulingState> readState() async => state;
  @override
  Future<void> saveSettings(ReminderSettings value) async {
    if (failSave) throw StateError('Storage failure');
    settings = value;
    state = state.dirty();
  }

  @override
  Future<void> saveState(ReminderSchedulingState value) async {
    if (failState) throw StateError('State failure');
    state = value;
  }

  @override
  Future<void> complete(
    ReminderSettings value,
    ReminderSchedulingState scheduling,
  ) async {
    if (failState) throw StateError('State failure');
    settings = value;
    state = scheduling;
  }
}

class FakeNotificationGateway implements NotificationGateway {
  @override
  bool supported = true;
  NotificationAccess permission = const NotificationAccess(
    appAllowed: true,
    channelAllowed: true,
  );
  final pending = <int, ReminderOccurrence>{};
  final active = <int>{};
  final calls = <String>[];
  bool failSchedule = false, failCancel = false, failAccess = false;
  Completer<void>? scheduleBarrier;
  VoidCallback? onTap;
  bool coldLaunch = false;
  @override
  Future<bool> initialize(void Function() onReviewDue) async {
    onTap = onReviewDue;
    final launch = coldLaunch;
    coldLaunch = false;
    return launch;
  }

  @override
  Future<NotificationAccess> access() async {
    if (failAccess) throw StateError('Access failure');
    return permission;
  }

  @override
  Future<void> requestPermission() async {
    calls.add('request');
  }

  @override
  Future<void> openSettings() async {
    calls.add('settings');
  }

  @override
  Future<Set<int>> pendingIds() async => pending.keys.toSet();
  @override
  Future<Set<int>> activeIds() async => active;
  @override
  Future<void> schedule(ReminderOccurrence occurrence, String timeZone) async {
    if (scheduleBarrier != null) await scheduleBarrier!.future;
    if (failSchedule) throw StateError('Alarm failure');
    calls.add('schedule:${occurrence.id}');
    pending[occurrence.id] = occurrence;
  }

  @override
  Future<void> cancel(int id) async {
    if (failCancel) throw StateError('Cancel failure');
    calls.add('cancel:$id');
    pending.remove(id);
    active.remove(id);
  }
}

typedef VoidCallback = void Function();

class FakeDueCardsSource implements DueCardsSource {
  bool activeSession = false;
  @override
  Future<bool> hasActiveSession() async => activeSession;
  List<DueCard> cards = [];
  bool fail = false;
  DateTime? requestedAt;
  @override
  Future<List<DueCard>> getDueCards(DateTime at) async {
    requestedAt = at;
    if (fail) throw StateError('Read failure');
    return cards.where((c) => !c.card.dueDate.isAfter(at)).toList();
  }
}

DueCard dueCard(DateTime at, {String id = 'c'}) => DueCard(
  CardEntity(
    id: id,
    deckId: 'd',
    type: CardType.basic,
    front: 'Câu hỏi $id',
    back: 'Đáp án',
    dueDate: at,
    createdAt: at,
    updatedAt: at,
  ),
  'Bộ thẻ',
);
