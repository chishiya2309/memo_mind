import 'dart:math' as math;

import 'review_models.dart';

/// Pure SM-2 variant. Interval uses the OLD EF, rounded to the nearest day.
class Sm2Scheduler {
  const Sm2Scheduler();
  ScheduleState schedule(
    ScheduleState previous,
    ReviewRating rating,
    DateTime reviewedAt,
  ) {
    final valid =
        previous.repetitions >= 0 &&
        previous.intervalDays >= 0 &&
        previous.easeFactor.isFinite &&
        previous.easeFactor >= 1.3 &&
        (previous.repetitions == 0 || previous.intervalDays > 0);
    final old = valid ? previous : ScheduleState(nextReviewAt: reviewedAt);
    final q = rating.quality;
    final repetitions = q < 3 ? 0 : old.repetitions + 1;
    final interval = q < 3 || repetitions == 1
        ? 1
        : repetitions == 2
        ? 6
        : math.max(1, (old.intervalDays * old.easeFactor).round());
    // EF' = EF + 0.1 - (5-q) * (0.08 + (5-q) * 0.02).
    final delta = 5 - q;
    final ef = math.max(
      1.3,
      old.easeFactor + 0.1 - delta * (0.08 + delta * 0.02),
    );
    return ScheduleState(
      repetitions: repetitions,
      intervalDays: interval,
      easeFactor: ef,
      nextReviewAt: reviewedAt.toUtc().add(Duration(days: interval)),
    );
  }
}
