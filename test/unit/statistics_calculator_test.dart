import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/statistics/domain/statistics_models.dart';
import 'package:memo_mind/features/review/domain/review_models.dart';
import 'package:memo_mind/features/statistics/data/statistics_time_zone.dart';
import 'package:timezone/timezone.dart' as tz;

import '../support/statistics_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 2, 8);
  test(
    'AC10 extreme timestamps that cannot form a local date are isolated',
    () {
      final data = statisticsSnapshot(
        at: now,
        zone: 'America/New_York',
        events: [
          statisticsEvent('valid', now),
          {
            ...statisticsEvent('extreme', now),
            'reviewed_at': -8640000000000000,
          },
        ],
      );
      expect(data.reviewCountToday, 1);
      expect(data.dataQualityStatus, StatisticsDataQuality.partial);
    },
  );
  test('AC01/02 empty store, due equality, past and future', () {
    expect(ScheduleState.hasValidStoredSchedule({}), false);
    final empty = statisticsSnapshot(at: now);
    expect(empty.dueCardCount, 0);
    expect(empty.reviewCountToday, 0);
    expect(empty.successRateToday, isNull);
    expect(empty.currentStreakDays, 0);
    final future = now.add(const Duration(seconds: 1));
    final data = statisticsSnapshot(
      at: now,
      cards: {
        'past': now.subtract(const Duration(days: 1)),
        'equal': now,
        'future': future,
      },
    );
    expect(data.dueCardCount, 2);
    expect(data.nextDueAt, future);
  });
  test(
    'AC03 four ratings and numeric mapping share the scheduler threshold',
    () {
      for (final ratings in [
        <Object>['again', 'hard', 'good', 'easy'],
        <Object>[1, 3, 4, 5],
      ]) {
        final data = statisticsSnapshot(
          at: now,
          events: [
            for (var i = 0; i < ratings.length; i++)
              statisticsEvent('e$i', now, ratings[i]),
          ],
        );
        expect(data.reviewCountToday, 4);
        expect(data.successfulReviewCountToday, 3);
        expect(data.successRateToday, 75);
      }
    },
  );
  test(
    'AC04 repeat card counts each distinct event, identical copies count once',
    () {
      final first = statisticsEvent('a', now, 'again');
      final data = statisticsSnapshot(
        at: now,
        events: [
          first,
          {...first, 'sequence': 99},
          statisticsEvent('b', now),
        ],
      );
      expect(data.reviewCountToday, 2);
      expect(data.successRateToday, 50);
      expect(data.dataQualityStatus, StatisticsDataQuality.complete);
    },
  );
  test('AC05 no reviews differs from all Again; percentages round once', () {
    expect(statisticsSnapshot(at: now).successRateToday, isNull);
    expect(
      statisticsSnapshot(
        at: now,
        events: [
          for (var i = 0; i < 3; i++) statisticsEvent('$i', now, 'again'),
        ],
      ).successRateToday,
      0,
    );
    expect(
      statisticsSnapshot(
        at: now,
        events: [
          statisticsEvent('1', now),
          statisticsEvent('2', now, 'again'),
          statisticsEvent('3', now, 'again'),
        ],
      ).successRateToday,
      33.3,
    );
  });
  test('AC06 streak anchors today or yesterday and stops at a gap', () {
    for (final (offsets, expected) in [
      ([0, 1, 2], 3),
      ([1, 2], 2),
      ([2], 0),
      ([0, 2], 1),
    ]) {
      final data = statisticsSnapshot(
        at: now,
        events: [
          for (final day in offsets)
            statisticsEvent('$day', now.subtract(Duration(days: day))),
        ],
      );
      expect(data.currentStreakDays, expected);
      expect(data.studiedToday, offsets.contains(0));
    }
    expect(
      statisticsSnapshot(
        at: now,
        events: [statisticsEvent('1', now), statisticsEvent('2', now)],
      ).currentStreakDays,
      1,
    );
  });
  test(
    'AC07 midnight equality and reinterpretation of all history in a new zone',
    () {
      final midnight = DateTime.utc(2026, 10, 1, 17);
      final events = [
        statisticsEvent(
          'before',
          midnight.subtract(const Duration(milliseconds: 1)),
        ),
        statisticsEvent('at', midnight),
      ];
      final local = statisticsSnapshot(at: now, events: events);
      expect(local.reviewCountToday, 1);
      expect(local.currentStreakDays, 2);
      final utc = statisticsSnapshot(at: now, zone: 'UTC', events: events);
      expect(utc.reviewCountToday, 0);
      expect(utc.currentStreakDays, 1);
      expect(
        statisticsSnapshot(
          at: midnight.subtract(const Duration(milliseconds: 1)),
          events: [events.first],
        ).reviewCountToday,
        1,
      );
    },
  );
  test(
    'AC07 DST calendar boundaries have 23/25 hours and consecutive civil dates',
    () {
      final zone = statisticsTimeZone('America/New_York');
      for (final (month, day, hours) in [(3, 8, 23), (11, 1, 25)]) {
        final start = tz.TZDateTime(zone, 2026, month, day);
        final at = tz.TZDateTime(zone, 2026, month, day, 23);
        final data = statisticsSnapshot(
          at: at,
          zone: zone.name,
          events: [
            statisticsEvent(
              'yesterday',
              tz.TZDateTime(zone, 2026, month, day - 1, 23),
            ),
            statisticsEvent('today', start),
          ],
        );
        expect(
          data.nextLocalMidnight.difference(start),
          Duration(hours: hours),
        );
        expect(data.currentStreakDays, 2);
        expect(data.reviewCountToday, 1);
      }
    },
  );
  test(
    'AC10 quarantine invalid/future events and all conflicting ID copies',
    () {
      final valid = statisticsEvent('conflict', now);
      final events = [
        statisticsEvent('ok', now),
        valid,
        {...valid, 'rating': 'again'},
        valid,
        statisticsEvent('future', now.add(const Duration(milliseconds: 1))),
        statisticsEvent('invalidRating', now, 2),
        {...statisticsEvent('invalidTime', now), 'reviewed_at': 'broken'},
        {...statisticsEvent('overflow', now), 'reviewed_at': 8640000000000001},
        {...statisticsEvent('missing', now), 'event_id': ''},
        {...statisticsEvent('missingCard', now), 'card_id': null},
      ];
      final data = statisticsSnapshot(at: now, events: events);
      expect(data.reviewCountToday, 1);
      expect(data.successRateToday, 100);
      expect(data.dataQualityStatus, StatisticsDataQuality.partial);
      expect(events.length, 10);
    },
  );
}
