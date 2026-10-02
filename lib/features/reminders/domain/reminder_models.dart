import 'package:timezone/timezone.dart' as tz;

const reminderPayload = 'action=review_due';
const reminderChannelId = 'memo_mind_due_reminders';

class ReminderSettings {
  const ReminderSettings({
    this.enabled = false,
    this.hour,
    this.minute,
    this.lastKnownTimeZone,
    this.updatedAt,
  });
  final bool enabled;
  final int? hour, minute;
  final String? lastKnownTimeZone;
  final DateTime? updatedAt;
  void validate() {
    if ((enabled || hour != null || minute != null) &&
        (hour == null ||
            minute == null ||
            hour! < 0 ||
            hour! > 23 ||
            minute! < 0 ||
            minute! > 59)) {
      throw const FormatException(
        'Vui lòng chọn giờ trong khoảng 00:00–23:59.',
      );
    }
  }

  ReminderSettings inZone(String zone) => ReminderSettings(
    enabled: enabled,
    hour: hour,
    minute: minute,
    lastKnownTimeZone: zone,
    updatedAt: updatedAt,
  );
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
    'lastKnownTimeZone': lastKnownTimeZone,
    'updatedAt': updatedAt?.toUtc().millisecondsSinceEpoch,
  };
  factory ReminderSettings.fromJson(Map<String, dynamic> json) {
    final settings = ReminderSettings(
      enabled: json['enabled'] as bool,
      hour: json['hour'] as int?,
      minute: json['minute'] as int?,
      lastKnownTimeZone: json['lastKnownTimeZone'] as String?,
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              json['updatedAt'] as int,
              isUtc: true,
            ),
    );
    settings.validate();
    return settings;
  }
}

class ReminderOccurrence {
  const ReminderOccurrence({
    required this.id,
    required this.key,
    required this.scheduledAt,
  });
  final int id;
  final String key;
  final DateTime scheduledAt;
  // Reserve this range exclusively for FR16 (civil YYYYMMDD + namespace).
  static bool ownsId(int id) => id >= 160000000 && id < 260000000;
  Map<String, Object?> toJson() => {
    'id': id,
    'key': key,
    'scheduledAt': scheduledAt.toUtc().millisecondsSinceEpoch,
  };
  factory ReminderOccurrence.fromJson(Map<String, dynamic> json) =>
      ReminderOccurrence(
        id: json['id'] as int,
        key: json['key'] as String,
        scheduledAt: DateTime.fromMillisecondsSinceEpoch(
          json['scheduledAt'] as int,
          isUtc: true,
        ),
      );
}

class ReminderSchedulingState {
  const ReminderSchedulingState({
    this.needsReconcile = false,
    this.occurrences = const [],
    this.windowEndAt,
    this.timeZone,
  });
  final bool needsReconcile;
  final List<ReminderOccurrence> occurrences;
  final DateTime? windowEndAt;
  final String? timeZone;
  ReminderSchedulingState dirty() => ReminderSchedulingState(
    needsReconcile: true,
    occurrences: occurrences,
    windowEndAt: windowEndAt,
    timeZone: timeZone,
  );
  Map<String, Object?> toJson() => {
    'needsReconcile': needsReconcile,
    'occurrences': occurrences.map((o) => o.toJson()).toList(),
    'windowEndAt': windowEndAt?.toUtc().millisecondsSinceEpoch,
    'timeZone': timeZone,
  };
  factory ReminderSchedulingState.fromJson(Map<String, dynamic> json) =>
      ReminderSchedulingState(
        needsReconcile: json['needsReconcile'] as bool,
        occurrences: (json['occurrences'] as List)
            .map((o) => ReminderOccurrence.fromJson(o as Map<String, dynamic>))
            .toList(),
        timeZone: json['timeZone'] as String?,
        windowEndAt: json['windowEndAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                json['windowEndAt'] as int,
                isUtc: true,
              ),
      );
}

enum ReminderStatus {
  disabled,
  updating,
  blocked,
  noDue,
  scheduled,
  needsReconcile,
  unsupported,
}

class NotificationAccess {
  const NotificationAccess({
    required this.appAllowed,
    required this.channelAllowed,
    this.canRequest = false,
  });
  final bool appAllowed, channelAllowed, canRequest;
  bool get allowed => appAllowed && channelAllowed;
}

class ReminderWindow {
  const ReminderWindow(this.occurrences, this.endAt);
  final List<ReminderOccurrence> occurrences;
  final DateTime endAt;
}

ReminderWindow reminderWindow(
  ReminderSettings settings,
  DateTime now,
  tz.Location location,
) {
  settings.validate();
  final local = tz.TZDateTime.from(now, location);
  final end = tz.TZDateTime(location, local.year, local.month, local.day + 7);
  if (!settings.enabled) return ReminderWindow(const [], end.toUtc());
  final result = <ReminderOccurrence>[];
  for (var day = 0; day < 7; day++) {
    final date = tz.TZDateTime(
      location,
      local.year,
      local.month,
      local.day + day,
    );
    final at = tz.TZDateTime(
      location,
      date.year,
      date.month,
      date.day,
      settings.hour!,
      settings.minute!,
    );
    if (!at.isAfter(now)) continue;
    final key =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    result.add(
      ReminderOccurrence(
        id: 160000000 + date.year * 10000 + date.month * 100 + date.day,
        key: 'review_due:$key',
        scheduledAt: at.toUtc(),
      ),
    );
  }
  return ReminderWindow(result, end.toUtc());
}
