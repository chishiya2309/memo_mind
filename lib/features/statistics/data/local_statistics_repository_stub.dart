import '../../../core/database/memo_mind_database.dart';
import '../domain/statistics_models.dart';
import '../domain/statistics_repository.dart';

class LocalStatisticsRepository implements StatisticsRepository {
  LocalStatisticsRepository({
    MemoMindDatabase? database,
    DateTime Function()? clock,
    Future<String> Function()? timeZone,
  });

  @override
  Future<StatisticsSnapshot> loadSnapshot() async =>
      throw UnsupportedError('Thống kê học tập hiện hỗ trợ trên Android.');
}
