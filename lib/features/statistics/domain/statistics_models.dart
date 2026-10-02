enum StatisticsDataQuality { complete, partial }

class StatisticsSnapshot {
  const StatisticsSnapshot({
    required this.asOf,
    required this.timeZoneId,
    required this.localDate,
    required this.dueCardCount,
    required this.reviewCountToday,
    required this.successfulReviewCountToday,
    required this.successRateToday,
    required this.currentStreakDays,
    required this.studiedToday,
    required this.dataQualityStatus,
    required this.nextLocalMidnight,
    this.nextDueAt,
  });

  final DateTime asOf;
  final String timeZoneId;

  /// Civil date key (UTC midnight for year/month/day), not a review timestamp.
  final DateTime localDate;
  final int dueCardCount, reviewCountToday, successfulReviewCountToday;
  final double? successRateToday;
  final int currentStreakDays;
  final bool studiedToday;
  final StatisticsDataQuality dataQualityStatus;
  final DateTime nextLocalMidnight;
  final DateTime? nextDueAt;
}
