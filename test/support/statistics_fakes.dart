import 'dart:async';

import 'package:memo_mind/features/statistics/data/statistics_time_zone.dart';
import 'package:memo_mind/features/statistics/domain/statistics_calculator.dart';
import 'package:memo_mind/features/statistics/domain/statistics_models.dart';
import 'package:memo_mind/features/statistics/domain/statistics_repository.dart';

Map<String, Object?> statisticsEvent(
  String id,
  DateTime at, [
  Object rating = 'good',
]) => {
  'event_id': id,
  'session_id': 'session',
  'card_id': 'card',
  'device_id': 'device',
  'reviewed_at': at.millisecondsSinceEpoch,
  'rating': rating,
};

StatisticsSnapshot statisticsSnapshot({
  DateTime? at,
  String zone = 'Asia/Ho_Chi_Minh',
  Map<String, DateTime> cards = const {},
  List<Map<String, Object?>> events = const [],
}) => const StatisticsCalculator().calculate(
  asOf: at ?? DateTime.utc(2026, 10, 2, 8),
  timeZone: statisticsTimeZone(zone),
  cardSchedules: cards,
  events: events,
);

class FakeStatisticsRepository implements StatisticsRepository {
  StatisticsSnapshot data = statisticsSnapshot();
  Object? error;
  int calls = 0;
  final List<Completer<StatisticsSnapshot>> pending = [];
  bool delayed = false;

  @override
  Future<StatisticsSnapshot> loadSnapshot() async {
    calls++;
    if (delayed) {
      final task = Completer<StatisticsSnapshot>();
      pending.add(task);
      return task.future;
    }
    if (error != null) throw error!;
    return data;
  }
}
