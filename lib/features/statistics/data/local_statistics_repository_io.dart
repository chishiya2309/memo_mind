import '../../../core/workspace/workspace_context.dart';
import '../../../core/database/memo_mind_database.dart';
import '../../review/data/local_due_cards_source_io.dart';
import '../domain/statistics_calculator.dart';
import '../domain/statistics_models.dart';
import '../domain/statistics_repository.dart';
import 'statistics_time_zone.dart';

class LocalStatisticsRepository implements StatisticsRepository {
  LocalStatisticsRepository({
    MemoMindDatabase? database,
    DateTime Function()? clock,
    Future<String> Function()? timeZone,
  }) : _database = database ?? WorkspaceRuntime.database,
       _clock = clock ?? DateTime.now,
       _timeZone = timeZone ?? deviceStatisticsTimeZone;

  final MemoMindDatabase _database;
  final DateTime Function() _clock;
  final Future<String> Function() _timeZone;

  @override
  Future<StatisticsSnapshot> loadSnapshot() async {
    final zone = statisticsTimeZone(await _timeZone());
    final db = await _database.database;
    return db.transaction((txn) async {
      final asOf = _clock().toUtc();
      final cards = await LocalDueCardsSource.query(txn);
      final events = await txn.query('review_events');
      return const StatisticsCalculator().calculate(
        asOf: asOf,
        timeZone: zone,
        cardSchedules: {
          for (final item in cards) item.card.id: item.card.dueDate,
        },
        events: events,
      );
    });
  }
}
