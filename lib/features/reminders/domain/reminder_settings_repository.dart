import 'reminder_models.dart';

abstract class ReminderSettingsRepository {
  Future<ReminderSettings> readSettings();
  Future<ReminderSchedulingState> readState();
  Future<void> saveSettings(ReminderSettings settings);
  Future<void> saveState(ReminderSchedulingState state);
  Future<void> complete(
    ReminderSettings settings,
    ReminderSchedulingState state,
  );
}
