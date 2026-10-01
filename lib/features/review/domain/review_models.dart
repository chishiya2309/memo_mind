import '../../deck_management/domain/deck_models.dart';

enum ReviewRating {
  again(1, 'Again'),
  hard(3, 'Hard'),
  good(4, 'Good'),
  easy(5, 'Easy');

  const ReviewRating(this.quality, this.label);
  final int quality;
  final String label;
}

class ScheduleState {
  const ScheduleState({
    this.repetitions = 0,
    this.intervalDays = 0,
    this.easeFactor = 2.5,
    required this.nextReviewAt,
  });
  final int repetitions, intervalDays;
  final double easeFactor;
  final DateTime nextReviewAt;

  factory ScheduleState.fromRow(Map<String, Object?> row, DateTime now) {
    final repetitions = row['repetitions'];
    final interval = row['interval_days'];
    final ef = row['ease_factor'];
    if (repetitions is! int ||
        repetitions < 0 ||
        interval is! int ||
        interval < 0 ||
        ef is! num ||
        !ef.isFinite ||
        ef < 1.3 ||
        (repetitions > 0 && interval == 0)) {
      return ScheduleState(nextReviewAt: now);
    }
    return ScheduleState(
      repetitions: repetitions,
      intervalDays: interval,
      easeFactor: ef.toDouble(),
      nextReviewAt: row['due_date'] is int
          ? DateTime.fromMillisecondsSinceEpoch(
              row['due_date'] as int,
              isUtc: true,
            )
          : now,
    );
  }
}

class ReviewEvent {
  const ReviewEvent({
    required this.eventId,
    required this.sessionId,
    required this.cardId,
    required this.deviceId,
    required this.reviewedAt,
    required this.rating,
    this.sequence,
  });
  final String eventId, sessionId, cardId, deviceId;
  final DateTime reviewedAt;
  final ReviewRating rating;
  final int? sequence;
}

class ReviewSession {
  ReviewSession({
    required this.id,
    this.deckId,
    required this.dueOnly,
    required List<String> queue,
    required List<String> learningQueue,
    required this.initialCount,
    this.status = 'active',
  }) : queue = List.unmodifiable(queue),
       learningQueue = List.unmodifiable(learningQueue);
  final String id;
  final String? deckId;
  final bool dueOnly;
  final List<String> queue, learningQueue;
  final int initialCount;
  final String status;
  bool get isActive => status == 'active';
  String? get currentCardId => queue.firstOrNull ?? learningQueue.firstOrNull;
  int get remaining => queue.length + learningQueue.length;
}

class ReviewSnapshot {
  const ReviewSnapshot(this.session, this.card, this.events);
  final ReviewSession session;
  final CardEntity? card;
  final List<ReviewEvent> events;
  int get reviewedCards => events.map((e) => e.cardId).toSet().length;
  int count(ReviewRating rating) =>
      events.where((e) => e.rating == rating).length;
}

class ReviewDeck {
  const ReviewDeck({
    required this.id,
    required this.title,
    required this.activeCount,
    required this.dueCount,
    this.learnedCount = 0,
  });
  final String id, title;
  final int activeCount, dueCount, learnedCount;
}
