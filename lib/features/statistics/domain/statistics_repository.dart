import 'statistics_models.dart';

abstract class StatisticsRepository {
  Future<StatisticsSnapshot> loadSnapshot();
}
