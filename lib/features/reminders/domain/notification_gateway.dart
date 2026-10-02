import 'reminder_models.dart';

abstract class NotificationGateway {
  bool get supported;
  Future<bool> initialize(void Function() onReviewDue);
  Future<NotificationAccess> access();
  Future<void> requestPermission();
  Future<void> openSettings();
  Future<Set<int>> pendingIds();
  Future<Set<int>> activeIds();
  Future<void> schedule(ReminderOccurrence occurrence, String timeZone);
  Future<void> cancel(int id);
}
