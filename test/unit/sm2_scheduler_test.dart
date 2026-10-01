import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/review/domain/review_models.dart';
import 'package:memo_mind/features/review/domain/sm2_scheduler.dart';

void main() {
  const scheduler = Sm2Scheduler();
  final now = DateTime.utc(2026, 9, 30, 8, 30);
  test('ratings map to 1, 3, 4, 5', () {
    expect(ReviewRating.values.map((r) => r.quality), [1, 3, 4, 5]);
  });
  for (final entry in {
    ReviewRating.again: 1.96,
    ReviewRating.hard: 2.36,
    ReviewRating.good: 2.5,
    ReviewRating.easy: 2.6,
  }.entries) {
    test('${entry.key.name} updates EF and repetitions', () {
      final next = scheduler.schedule(
        ScheduleState(nextReviewAt: now),
        entry.key,
        now,
      );
      expect(next.easeFactor, closeTo(entry.value, 0.000001));
      expect(next.repetitions, entry.key == ReviewRating.again ? 0 : 1);
      expect(next.intervalDays, 1);
      expect(next.nextReviewAt, DateTime.utc(2026, 10, 1, 8, 30));
    });
  }
  test('successful intervals use old EF; third interval rounds nearest', () {
    var state = ScheduleState(nextReviewAt: now);
    state = scheduler.schedule(state, ReviewRating.easy, now);
    state = scheduler.schedule(
      state,
      ReviewRating.easy,
      now.add(const Duration(days: 1)),
    );
    expect(state.repetitions, 2);
    expect(state.intervalDays, 6);
    expect(state.easeFactor, closeTo(2.7, 0.000001));
    state = scheduler.schedule(
      state,
      ReviewRating.easy,
      now.add(const Duration(days: 7)),
    );
    expect(state.intervalDays, 16); // 6 * 2.7, not 6 * 2.8.
    expect(state.nextReviewAt, now.add(const Duration(days: 23)));
  });
  test('Again resets a mature card and EF never drops below 1.3', () {
    var state = ScheduleState(
      repetitions: 8,
      intervalDays: 100,
      easeFactor: 1.4,
      nextReviewAt: now,
    );
    for (var i = 0; i < 5; i++) {
      state = scheduler.schedule(state, ReviewRating.again, now);
      expect(state.easeFactor, 1.3);
      expect(state.repetitions, 0);
      expect(state.intervalDays, 1);
    }
    state = scheduler.schedule(state, ReviewRating.good, now);
    expect(state.repetitions, 1);
    expect(state.intervalDays, 1);
  });
  test('invalid or missing state resets to a consistent starting state', () {
    for (final invalid in [
      ScheduleState(repetitions: -1, nextReviewAt: now),
      ScheduleState(easeFactor: double.nan, nextReviewAt: now),
      ScheduleState(intervalDays: -1, nextReviewAt: now),
      ScheduleState(repetitions: 2, intervalDays: 0, nextReviewAt: now),
      ScheduleState.fromRow({}, now),
    ]) {
      final next = scheduler.schedule(invalid, ReviewRating.good, now);
      expect(next.easeFactor, 2.5);
      expect(next.repetitions, 1);
      expect(next.intervalDays, 1);
    }
  });
  test('replaying a timestamped sequence produces the same schedule', () {
    ScheduleState replay() {
      var state = ScheduleState(nextReviewAt: now);
      for (final (i, rating) in [
        ReviewRating.good,
        ReviewRating.hard,
        ReviewRating.easy,
        ReviewRating.again,
        ReviewRating.good,
      ].indexed) {
        state = scheduler.schedule(state, rating, now.add(Duration(days: i)));
      }
      return state;
    }

    final a = replay(), b = replay();
    expect(a.nextReviewAt, b.nextReviewAt);
    expect(a.easeFactor, b.easeFactor);
    expect(a.repetitions, b.repetitions);
    expect(a.intervalDays, b.intervalDays);
  });
}
