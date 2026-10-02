import 'package:timezone/timezone.dart' as tz;

import '../../review/domain/review_models.dart';
import 'statistics_models.dart';

/// Input cards have already passed the shared review eligibility predicate.
class StatisticsCalculator {
  const StatisticsCalculator();

  StatisticsSnapshot calculate({
    required DateTime asOf,
    required tz.Location timeZone,
    required Map<String, DateTime> cardSchedules,
    required Iterable<Map<String, Object?>> events,
  }) {
    final now = tz.TZDateTime.from(asOf, timeZone);
    final today = tz.TZDateTime(timeZone, now.year, now.month, now.day);
    final midnight = tz.TZDateTime(timeZone, now.year, now.month, now.day + 1);
    var dueCount = 0;
    DateTime? nextDue;
    for (final due in cardSchedules.values) {
      if (!due.isAfter(asOf)) {
        dueCount++;
      } else if (nextDue == null || due.isBefore(nextDue)) {
        nextDue = due;
      }
    }

    // Compare semantic payloads, ignoring the local auto-increment sequence.
    // Keep every payload before validation so an invalid duplicate cannot hide
    // a conflict with a valid copy of the same event.
    final byId = <String, Map<String, Object?>>{};
    final conflicts = <String>{};
    var partial = false;
    const fields = [
      'event_id',
      'session_id',
      'card_id',
      'device_id',
      'reviewed_at',
      'rating',
    ];
    for (final row in events) {
      final id = row['event_id'];
      if (id is! String || id.trim().isEmpty) {
        partial = true;
        continue;
      }
      final previous = byId[id];
      if (previous != null && fields.any((key) => previous[key] != row[key])) {
        conflicts.add(id);
        partial = true;
      } else {
        byId[id] = row;
      }
    }

    var reviews = 0;
    var successes = 0;
    final days = <DateTime>{};
    for (final entry in byId.entries) {
      if (conflicts.contains(entry.key)) continue;
      final row = entry.value;
      final timestamp = row['reviewed_at'];
      final rating = _rating(row['rating']);
      final validIds = ['session_id', 'card_id', 'device_id'].every((key) {
        final value = row[key];
        return value is String && value.trim().isNotEmpty;
      });
      if (!validIds ||
          timestamp is! int ||
          timestamp.abs() > 8640000000000000 ||
          rating == null) {
        partial = true;
        continue;
      }
      final reviewed = DateTime.fromMillisecondsSinceEpoch(
        timestamp,
        isUtc: true,
      );
      if (reviewed.isAfter(asOf)) {
        partial = true;
        continue;
      }
      try {
        final local = tz.TZDateTime.from(reviewed, timeZone);
        // Calendar keys deliberately have no timezone; no duration arithmetic.
        days.add(DateTime.utc(local.year, local.month, local.day));
      } on ArgumentError {
        // An extreme UTC timestamp can overflow after applying a zone offset.
        partial = true;
        continue;
      }
      if (!reviewed.isBefore(today)) {
        reviews++;
        if (rating.quality >= 3) successes++;
      }
    }
    final todayKey = DateTime.utc(now.year, now.month, now.day);
    final studiedToday = days.contains(todayKey);
    var cursor = studiedToday
        ? todayKey
        : DateTime.utc(now.year, now.month, now.day - 1);
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      try {
        cursor = DateTime.utc(cursor.year, cursor.month, cursor.day - 1);
      } on ArgumentError {
        break;
      }
    }
    return StatisticsSnapshot(
      asOf: asOf.toUtc(),
      timeZoneId: timeZone.name,
      localDate: todayKey,
      dueCardCount: dueCount,
      reviewCountToday: reviews,
      successfulReviewCountToday: successes,
      successRateToday: reviews == 0
          ? null
          : (successes * 1000 / reviews).round() / 10,
      currentStreakDays: streak,
      studiedToday: studiedToday,
      dataQualityStatus: partial
          ? StatisticsDataQuality.partial
          : StatisticsDataQuality.complete,
      nextLocalMidnight: midnight.toUtc(),
      nextDueAt: nextDue?.toUtc(),
    );
  }

  ReviewRating? _rating(Object? value) {
    for (final rating in ReviewRating.values) {
      if (value == rating.name || value == rating.quality) return rating;
    }
    return null;
  }
}
