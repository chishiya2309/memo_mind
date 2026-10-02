import '../../../core/workspace/workspace_context.dart';

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/memo_mind_database.dart';
import '../domain/reminder_models.dart';
import '../domain/reminder_settings_repository.dart';

class LocalReminderSettingsRepository implements ReminderSettingsRepository {
  LocalReminderSettingsRepository({MemoMindDatabase? database})
    : _database =
          database ??
          WorkspaceRuntime.deviceSettings ??
          WorkspaceRuntime.database;
  final MemoMindDatabase _database;
  static const settingsKey = 'fr16.reminder_settings';
  static const stateKey = 'fr16.reminder_scheduling';
  Future<Map<String, dynamic>?> _read(String key) async {
    final rows = await (await _database.database).query(
      'app_settings',
      where: 'key=?',
      whereArgs: [key],
    );
    return rows.isEmpty
        ? null
        : jsonDecode(rows.single['value'] as String) as Map<String, dynamic>;
  }

  @override
  Future<ReminderSettings> readSettings() async {
    final json = await _read(settingsKey);
    return json == null
        ? const ReminderSettings()
        : ReminderSettings.fromJson(json);
  }

  @override
  Future<ReminderSchedulingState> readState() async {
    final json = await _read(stateKey);
    return json == null
        ? const ReminderSchedulingState()
        : ReminderSchedulingState.fromJson(json);
  }

  Future<void> _write(
    DatabaseExecutor db,
    String key,
    Map<String, Object?> json,
  ) async => db
      .insert('app_settings', {
        'key': key,
        'value': jsonEncode(json),
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});
  @override
  Future<void> saveSettings(ReminderSettings settings) async {
    settings.validate();
    await (await _database.database).transaction((txn) async {
      final rows = await txn.query(
        'app_settings',
        where: 'key=?',
        whereArgs: [stateKey],
      );
      final state = rows.isEmpty
          ? const ReminderSchedulingState()
          : ReminderSchedulingState.fromJson(
              jsonDecode(rows.single['value'] as String)
                  as Map<String, dynamic>,
            );
      await _write(txn, settingsKey, settings.toJson());
      await _write(txn, stateKey, state.dirty().toJson());
    });
  }

  @override
  Future<void> saveState(ReminderSchedulingState state) async =>
      _write(await _database.database, stateKey, state.toJson());
  @override
  Future<void> complete(
    ReminderSettings settings,
    ReminderSchedulingState state,
  ) async {
    await (await _database.database).transaction((txn) async {
      await _write(txn, settingsKey, settings.toJson());
      await _write(txn, stateKey, state.toJson());
    });
  }
}
