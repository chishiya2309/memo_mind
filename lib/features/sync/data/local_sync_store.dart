import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/sync_schema.dart';
import '../../../core/workspace/workspace_context.dart';
import '../../account_backup/data/snapshot_codec.dart';
import '../../account_backup/domain/auth_repository.dart';

const _localFields = {
  'cards': {'repetitions', 'interval_days', 'ease_factor', 'due_date'},
  'review_sessions': {'queue', 'learning_queue', 'is_local'},
  'review_events': {'sequence'},
};
const _derivedFields = {'updated_at', 'card_count', 'page_count'};

Map<String, dynamic> wireRow(String table, Map row) => {
  for (final entry in row.entries)
    if (!(_localFields[table]?.contains(entry.key) ?? false))
      entry.key as String: entry.value,
};

bool _newerSchedule(Map a, Map b) {
  final at = (a['reviewed_at'] as num).compareTo(b['reviewed_at'] as num);
  if (at != 0) return at > 0;
  final device = (a['device_id'] as String).compareTo(b['device_id'] as String);
  if (device != 0) return device > 0;
  return (a['event_id'] as String).compareTo(b['event_id'] as String) > 0;
}

List<String> changedFields(String table, Map? before, Map after) => [
  for (final field in after.keys.cast<String>())
    if (field != syncPrimaryKeys[table] &&
        !_derivedFields.contains(field) &&
        (before == null ||
            canonicalJson(before[field]) != canonicalJson(after[field])))
      field,
];

class SyncPacket {
  const SyncPacket(this.body, this.sequences);
  final Map<String, dynamic> body;
  final List<int> sequences;
}

class LocalSyncStore {
  LocalSyncStore(this.workspace);
  final WorkspaceContext workspace;
  Future<Database> get database => workspace.database.database;

  Future<String?> setting(String key) async {
    final rows = await (await database).query(
      'sync_state',
      where: 'key=?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> setSetting(String key, String value) async =>
      (await database).insert('sync_state', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<bool> get hasPending async =>
      (await (await database).query('sync_outbox', limit: 1)).isNotEmpty;
  Future<int> get cursor async => int.parse(await setting('cursor') ?? '0');
  Future<int> get readCursor async {
    final rows = await (await database).rawQuery(
      'SELECT MAX(version) AS version FROM sync_inbox',
    );
    return rows.single['version'] as int? ?? await cursor;
  }

  Future<T> _apply<T>(Future<T> Function(Transaction) action) async {
    final db = await database;
    return db.transaction((txn) async {
      await txn.execute('PRAGMA defer_foreign_keys=ON');
      await txn.update('sync_control', {'applying': 1}, where: 'id=1');
      final result = await action(txn);
      await txn.update('sync_control', {'applying': 0}, where: 'id=1');
      return result;
    });
  }

  Future<void> seed() async {
    await _apply((txn) async {
      final cardGroups = <String, String>{};
      if ((await txn.query('sync_state', where: "key='seeded'")).isNotEmpty) {
        return;
      }
      await txn.delete('sync_outbox');
      for (final entry in syncPrimaryKeys.entries) {
        for (final row in await txn.query(entry.key)) {
          await _enqueue(
            txn,
            entry.key,
            row,
            null,
            0,
            groupId: _cardGroup(cardGroups, entry.key, row),
          );
        }
      }
      await txn.insert('sync_state', {'key': 'seeded', 'value': '1'});
    });
  }

  Future<void> _enqueue(
    DatabaseExecutor db,
    String table,
    Map row,
    Map? before,
    int version, {
    bool? deleted,
    bool restore = false,
    String? groupId,
  }) async {
    final operationId = const Uuid().v4();
    await db.insert('sync_outbox', {
      'table_name': table,
      'entity_id': row[syncPrimaryKeys[table]],
      'group_id': groupId ?? const Uuid().v4(),
      'operation_id': operationId,
      'base_version': version,
      'before_data': before == null ? null : jsonEncode(before),
      'data': jsonEncode(row),
      'deleted': (deleted ?? row['status'] == 'deleted') ? 1 : 0,
    });
    if (restore) {
      await db.insert('sync_state', {
        'key': 'restore.$operationId',
        'value': '1',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  String? _cardGroup(Map<String, String> groups, String table, Map row) =>
      ['cards', 'card_schedules'].contains(table)
      ? groups.putIfAbsent(row['card_id'] as String, () => const Uuid().v4())
      : null;

  /// Freeze payloads on disk before network I/O. A retry sends identical bytes.
  Future<SyncPacket?> nextPacket(String deviceId) async {
    final db = await database;
    return db.transaction((txn) async {
      final saved = await txn.query('sync_packets', limit: 1);
      if (saved.isNotEmpty) {
        return SyncPacket(
          jsonDecode(saved.single['payload'] as String) as Map<String, dynamic>,
          (jsonDecode(saved.single['sequences'] as String) as List).cast<int>(),
        );
      }
      while (true) {
        final first = await txn.query(
          'sync_outbox',
          orderBy: 'sequence',
          limit: 1,
        );
        if (first.isEmpty) return null;
        final group = first.single['group_id'];
        final rows = (await txn.query(
          'sync_outbox',
          where: 'group_id=?',
          whereArgs: [group],
          orderBy: 'sequence',
        )).toList();
        final markers = (await txn.query(
          'sync_state',
          where: "key LIKE 'resolve.%' OR key LIKE 'restore.%'",
        )).map((r) => r['key'] as String).toSet();
        final restoring = rows.any(
          (r) => markers.contains('restore.${r['operation_id']}'),
        );
        bool resolving(List<Map<String, Object?>> values) =>
            values.any((r) => markers.contains('resolve.${r['operation_id']}'));
        var bytes = rows.fold<int>(
          0,
          (n, r) => n + utf8.encode(r['data'] as String).length,
        );
        if (!resolving(rows) && rows.length <= 50 && bytes < 850000) {
          final groups = await txn.rawQuery(
            'SELECT group_id FROM sync_outbox GROUP BY group_id ORDER BY MIN(sequence) LIMIT 50',
          );
          for (final candidate in groups.skip(1)) {
            final additional = await txn.query(
              'sync_outbox',
              where: 'group_id=?',
              whereArgs: [candidate['group_id']],
              orderBy: 'sequence',
            );
            final extraBytes = additional.fold<int>(
              0,
              (n, r) => n + utf8.encode(r['data'] as String).length,
            );
            if (resolving(additional) ||
                additional.any(
                      (r) => markers.contains('restore.${r['operation_id']}'),
                    ) !=
                    restoring ||
                rows.length + additional.length > 50 ||
                bytes + extraBytes > 850000) {
              break;
            }
            rows.addAll(additional);
            bytes += extraBytes;
          }
        }
        rows.sort(
          (a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int),
        );
        final compact = <String, Map<String, dynamic>>{};
        final selected = <int>[];
        for (final row in rows) {
          final table = row['table_name'] as String,
              id = row['entity_id'] as String;
          final key = '$table:$id';
          final data = wireRow(table, jsonDecode(row['data'] as String) as Map);
          final before = row['before_data'] == null
              ? null
              : wireRow(table, jsonDecode(row['before_data'] as String) as Map);
          final existing = compact[key];
          if (table == 'card_schedules' &&
              !restoring &&
              existing != null &&
              !_newerSchedule(data, existing['data'] as Map)) {
            selected.add(row['sequence'] as int);
            continue;
          }
          compact[key] = {
            'operationId': existing?['operationId'] ?? row['operation_id'],
            'table': table,
            'entityId': id,
            'baseVersion': existing?['baseVersion'] ?? row['base_version'],
            'deleted': row['deleted'] == 1,
            'data': data,
            'fields': {
              ...(existing?['fields'] as List? ?? []),
              ...changedFields(table, before, data),
            }.toList(),
          };
          selected.add(row['sequence'] as int);
        }
        final operations = compact.values
            .where(
              (op) =>
                  (op['fields'] as List).isNotEmpty || op['deleted'] == true,
            )
            .toList();
        if (operations.isEmpty) {
          for (final row in rows) {
            await txn.delete(
              'sync_state',
              where: 'key=?',
              whereArgs: ['restore.${row['operation_id']}'],
            );
          }
          await txn.delete(
            'sync_outbox',
            where:
                'sequence IN (${List.filled(selected.length, '?').join(',')})',
            whereArgs: selected,
          );
          continue;
        }
        // Parents precede children; physical deletions use the reverse order.
        final order = syncPrimaryKeys.keys.toList();
        operations.sort((a, b) {
          if (a['deleted'] != b['deleted']) {
            return a['deleted'] == true ? 1 : -1;
          }
          final comparison = order
              .indexOf(a['table'] as String)
              .compareTo(order.indexOf(b['table'] as String));
          return a['deleted'] == true ? -comparison : comparison;
        });
        final body = <String, dynamic>{
          'groupId': const Uuid().v4(),
          'deviceId': deviceId,
          'operations': operations,
        };
        if (operations.length == 1) {
          final resolution = await txn.query(
            'sync_state',
            where: 'key=?',
            whereArgs: ['resolve.${operations.single['operationId']}'],
          );
          if (resolution.isNotEmpty) {
            body['resolveConflictId'] = resolution.single['value'];
          }
        }
        if (restoring) {
          body['restore'] = true;
        }
        if (utf8.encode(jsonEncode(body)).length > 3 * 1024 * 1024) {
          throw const AccountFailure(
            'sync_limit',
            'Nhóm dữ liệu quá lớn để đồng bộ.',
          );
        }
        await txn.insert('sync_packets', {
          'group_id': body['groupId'],
          'payload': jsonEncode(body),
          'sequences': jsonEncode(selected),
        });
        return SyncPacket(body, selected);
      }
    });
  }

  Future<void> acknowledge(SyncPacket packet, Map response) async {
    final receipts = (response['receipts'] as List).cast<Map>();
    final operations = (packet.body['operations'] as List).cast<Map>();
    if (receipts.length != operations.length ||
        operations.any(
          (op) => !receipts.any((r) => r['operationId'] == op['operationId']),
        )) {
      throw const AccountFailure('unconfirmed', 'Chưa xác nhận đủ thay đổi.');
    }
    await _apply((txn) async {
      for (final op in operations) {
        final receipt = receipts.singleWhere(
          (r) => r['operationId'] == op['operationId'],
        );
        await txn.rawUpdate(
          'UPDATE sync_outbox SET base_version=? WHERE table_name=? AND entity_id=? AND sequence>? AND base_version<=?',
          [
            receipt['version'],
            op['table'],
            op['entityId'],
            packet.sequences.last,
            op['baseVersion'],
          ],
        );
        await txn.delete(
          'sync_state',
          where: 'key=?',
          whereArgs: ['resolve.${op['operationId']}'],
        );
      }
      for (final row in await txn.query(
        'sync_outbox',
        where:
            'sequence IN (${List.filled(packet.sequences.length, '?').join(',')})',
        whereArgs: packet.sequences,
      )) {
        await txn.delete(
          'sync_state',
          where: 'key=?',
          whereArgs: ['restore.${row['operation_id']}'],
        );
      }
      await txn.delete(
        'sync_outbox',
        where:
            'sequence IN (${List.filled(packet.sequences.length, '?').join(',')})',
        whereArgs: packet.sequences,
      );
      await txn.delete(
        'sync_packets',
        where: 'group_id=?',
        whereArgs: [packet.body['groupId']],
      );
    });
  }

  /// A stale resolution was explicitly rejected, so preserve its chosen content
  /// as a normal edit. It can become a fresh conflict without blocking other rows.
  Future<void> requeueRejectedResolution(SyncPacket packet) async {
    await (await database).transaction((txn) async {
      for (final op in (packet.body['operations'] as List).cast<Map>()) {
        await txn.update(
          'sync_outbox',
          {'operation_id': const Uuid().v4()},
          where: 'operation_id=?',
          whereArgs: [op['operationId']],
        );
        await txn.delete(
          'sync_state',
          where: 'key=?',
          whereArgs: ['resolve.${op['operationId']}'],
        );
      }
      await txn.delete(
        'sync_packets',
        where: 'group_id=?',
        whereArgs: [packet.body['groupId']],
      );
    });
  }

  Future<void> applyChanges(Map response) async {
    await _apply((txn) async {
      for (final raw in response['changes'] as List) {
        final change = raw as Map;
        await txn.insert('sync_inbox', {
          'version': change['version'],
          'payload': jsonEncode(change),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      final inbox = await txn.query('sync_inbox', orderBy: 'version');
      final complete = inbox.lastIndexWhere(
        (r) => (jsonDecode(r['payload'] as String) as Map)['groupEnd'] == true,
      );
      if (complete < 0) return;
      for (final item in inbox.take(complete + 1)) {
        final raw = jsonDecode(item['payload'] as String);
        final change = raw as Map,
            table = change['table'] as String,
            id = change['entityId'] as String;
        if (!syncPrimaryKeys.containsKey(table)) {
          throw const AccountFailure(
            'incompatible_sync',
            'Cần cập nhật ứng dụng để nhận dữ liệu.',
          );
        }
        final data = Map<String, dynamic>.from(change['data'] as Map);
        await txn.insert('sync_meta', {
          'table_name': table,
          'entity_id': id,
          'version': change['version'],
          'data': jsonEncode(data),
          'deleted': change['deleted'] == true ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        if ((await txn.query(
          'sync_outbox',
          where: 'table_name=? AND entity_id=?',
          whereArgs: [table, id],
          limit: 1,
        )).isEmpty) {
          await _materialize(txn, table, data, change['deleted'] == true);
        }
      }
      final appliedCursor = inbox[complete]['version'];
      await txn.delete(
        'sync_inbox',
        where: 'version<=?',
        whereArgs: [appliedCursor],
      );
      await txn.insert('sync_state', {
        'key': 'cursor',
        'value': '$appliedCursor',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _recount(txn);
    });
    workspace.database.notifyStudyChanged();
  }

  Future<void> materializeMirrors() async {
    await _apply((txn) async {
      for (final table in syncPrimaryKeys.keys) {
        final rows = await txn.rawQuery(
          '''SELECT * FROM sync_meta m WHERE table_name=? AND NOT EXISTS
          (SELECT 1 FROM sync_outbox o WHERE o.table_name=m.table_name AND o.entity_id=m.entity_id)''',
          [table],
        );
        for (final row in rows) {
          await _materialize(
            txn,
            table,
            jsonDecode(row['data'] as String) as Map,
            row['deleted'] == 1,
          );
        }
      }
      await _recount(txn);
    });
    workspace.database.notifyStudyChanged();
  }

  Future<void> _materialize(
    DatabaseExecutor db,
    String table,
    Map data,
    bool deleted,
  ) async {
    final row = Map<String, Object?>.from(data),
        pk = syncPrimaryKeys[table]!,
        id = row[pk];
    if (deleted) {
      if (['cards', 'decks', 'source_blocks'].contains(table)) {
        await db.update(
          table,
          {'status': 'deleted'},
          where: '$pk=? AND status!=?',
          whereArgs: [id, 'deleted'],
        );
        if (table == 'decks') {
          await db.update(
            'cards',
            {'status': 'deleted'},
            where: 'deck_id=? AND status!=?',
            whereArgs: [id, 'deleted'],
          );
        }
      } else {
        await db.delete(table, where: '$pk=?', whereArgs: [id]);
      }
      return;
    }
    final dependencies = switch (table) {
      'source_pages' => [('documents', 'document_id')],
      'page_normalizations' => [('source_pages', 'page_id')],
      'ocr_page_results' || 'source_blocks' => [
        ('documents', 'document_id'),
        ('source_pages', 'page_id'),
      ],
      _ => <(String, String)>[],
    };
    for (final dependency in dependencies) {
      final parent = await db.query(
        'sync_meta',
        where: 'table_name=? AND entity_id=?',
        whereArgs: [dependency.$1, row[dependency.$2]],
      );
      if (parent.isNotEmpty && parent.single['deleted'] == 1) return;
    }
    if (table == 'cards') {
      final schedule = await db.query(
        'card_schedules',
        where: 'card_id=?',
        whereArgs: [id],
      );
      row.addAll({
        'repetitions': schedule.isEmpty ? 0 : schedule.single['repetitions'],
        'interval_days': schedule.isEmpty
            ? 0
            : schedule.single['interval_days'],
        'ease_factor': schedule.isEmpty ? 2.5 : schedule.single['ease_factor'],
        'due_date': schedule.isEmpty
            ? row['created_at']
            : schedule.single['due_date'],
      });
      final parent = await db.query(
        'decks',
        where: 'deck_id=?',
        whereArgs: [row['deck_id']],
      );
      if (parent.isNotEmpty && parent.single['status'] == 'deleted') {
        row['status'] = 'deleted';
      }
    }
    if (table == 'review_sessions') {
      final existing = await db.query(table, where: '$pk=?', whereArgs: [id]);
      row.addAll({
        'queue': existing.isEmpty ? '[]' : existing.single['queue'],
        'learning_queue': existing.isEmpty
            ? '[]'
            : existing.single['learning_queue'],
        'is_local': existing.isEmpty ? 0 : existing.single['is_local'],
      });
    }
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.ignore);
    final existing = await db.query(table, where: '$pk=?', whereArgs: [id]);
    if (existing.isEmpty) {
      throw const AccountFailure(
        'sync_storage_conflict',
        'Chưa áp dụng được dữ liệu do xung đột lưu trữ. Dữ liệu và vị trí đồng bộ vẫn được giữ.',
      );
    }
    if (row.entries.any((e) => existing.single[e.key] != e.value)) {
      await db.update(table, row, where: '$pk=?', whereArgs: [id]);
    }
    if (table == 'card_schedules') {
      await db.update(
        'cards',
        {
          for (final f in [
            'repetitions',
            'interval_days',
            'ease_factor',
            'due_date',
          ])
            f: row[f],
        },
        where: 'card_id=? AND (repetitions!=? OR interval_days!=? OR ease_factor!=? OR due_date!=?)',
        whereArgs: [
          id,
          row['repetitions'],
          row['interval_days'],
          row['ease_factor'],
          row['due_date'],
        ],
      );
    }
  }

  Future<void> _recount(DatabaseExecutor db) async {
    await db.execute(
      "UPDATE decks SET card_count=(SELECT COUNT(*) FROM cards c WHERE c.deck_id=decks.deck_id AND c.status!='deleted') WHERE card_count!=(SELECT COUNT(*) FROM cards c WHERE c.deck_id=decks.deck_id AND c.status!='deleted')",
    );
    await db.execute(
      'UPDATE documents SET page_count=(SELECT COUNT(*) FROM source_pages p WHERE p.document_id=documents.document_id) WHERE page_count!=(SELECT COUNT(*) FROM source_pages p WHERE p.document_id=documents.document_id)',
    );
  }

  Future<void> saveConflicts(List values) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('sync_conflicts');
      for (final c in values.cast<Map>()) {
        await txn.insert('sync_conflicts', {
          'conflict_id': c['conflictId'],
          'payload': jsonEncode(c),
        });
      }
    });
  }

  Future<void> queueResolution(Map conflict, Map data, bool deleted) async {
    await _apply((txn) async {
      final operationId = const Uuid().v4();
      await txn.insert('sync_outbox', {
        'table_name': conflict['table'],
        'entity_id': conflict['entityId'],
        'group_id': const Uuid().v4(),
        'operation_id': operationId,
        'base_version': conflict['version'],
        'before_data': null,
        'data': jsonEncode(data),
        'deleted': deleted ? 1 : 0,
      });
      await txn.insert('sync_state', {
        'key': 'resolve.$operationId',
        'value': conflict['conflictId'],
      });
    });
  }

  Future<List<Map<String, dynamic>>> conflicts() async =>
      (await (await database).query('sync_conflicts'))
          .map(
            (r) => jsonDecode(r['payload'] as String) as Map<String, dynamic>,
          )
          .toList();

  Future<void> importWorkspace(
    WorkspaceContext source, {
    bool replace = false,
  }) async {
    final db = await database;
    if (!replace &&
        (await db.query(
          'sync_imports',
          where: 'source_id=?',
          whereArgs: [source.record.id],
        )).isNotEmpty) {
      return;
    }
    final sourceDb = await source.database.database;
    final tables = <String, List<Map<String, Object?>>>{};
    await sourceDb.transaction((txn) async {
      for (final table in syncPrimaryKeys.keys) {
        tables[table] = await txn.query(table);
      }
    });
    final remap = <String, String>{};
    for (final reference in fileReferences(tables)) {
      final oldKey = reference['fileKey'] as String;
      final input = File(
        p.joinAll([source.record.filesPath, ...oldKey.split('/')]),
      );
      if (!await input.exists() ||
          await fileHash(input) != reference['sha256']) {
        throw const AccountFailure(
          'missing_source',
          'Nguồn chuyển đổi thiếu hoặc hỏng.',
        );
      }
      var targetKey = oldKey;
      final target = File(
        p.joinAll([workspace.record.filesPath, ...targetKey.split('/')]),
      );
      if (await target.exists() &&
          await fileHash(target) != reference['sha256']) {
        targetKey =
            'documents/imported/${reference['sha256']}${p.extension(oldKey)}';
      }
      final output = File(
        p.joinAll([workspace.record.filesPath, ...targetKey.split('/')]),
      );
      await output.parent.create(recursive: true);
      if (!await output.exists()) await input.copy(output.path);
      if (await fileHash(output) != reference['sha256']) {
        throw const AccountFailure(
          'corrupt_source',
          'Nguồn thay đổi trong lúc chuyển đổi. Hãy thử lại.',
        );
      }
      remap[oldKey] = targetKey;
    }
    await _apply((txn) async {
      if (replace) {
        final cardGroups = <String, String>{};
        for (final table in syncPrimaryKeys.keys.toList().reversed) {
          if (['review_events', 'review_sessions'].contains(table)) continue;
          final keep = tables[table]!
              .map((r) => r[syncPrimaryKeys[table]])
              .toSet();
          for (final row in await txn.query(table)) {
            if (!keep.contains(row[syncPrimaryKeys[table]])) {
              final meta = await txn.query(
                'sync_meta',
                where: 'table_name=? AND entity_id=?',
                whereArgs: [table, row[syncPrimaryKeys[table]]],
              );
              await _enqueue(
                txn,
                table,
                row,
                row,
                meta.isEmpty ? 0 : meta.single['version'] as int,
                deleted: true,
                restore: true,
                groupId: _cardGroup(cardGroups, table, row),
              );
              await _materialize(txn, table, row, true);
            }
          }
        }
      }
      final cardGroups = <String, String>{};
      for (final table in syncPrimaryKeys.keys) {
        for (final raw in tables[table]!) {
          final row = Map<String, Object?>.from(raw);
          for (final f in row.keys.toList()) {
            if (f.endsWith('relative_path') && row[f] != null) {
              row[f] = remap[row[f]] ?? row[f];
            }
          }
          final id = row[syncPrimaryKeys[table]];
          final old = await txn.query(
            table,
            where: '${syncPrimaryKeys[table]}=?',
            whereArgs: [id],
          );
          if (old.isNotEmpty && !replace) {
            if (canonicalJson(wireRow(table, old.single)) !=
                canonicalJson(wireRow(table, row))) {
              await _enqueue(
                txn,
                table,
                row,
                null,
                0,
                groupId: _cardGroup(cardGroups, table, row),
              );
            }
            continue;
          }
          final meta = await txn.query(
            'sync_meta',
            where: 'table_name=? AND entity_id=?',
            whereArgs: [table, id],
          );
          await _materialize(
            txn,
            table,
            wireRow(table, row),
            row['status'] == 'deleted',
          );
          await _enqueue(
            txn,
            table,
            row,
            old.isEmpty ? null : old.single,
            meta.isEmpty ? 0 : meta.single['version'] as int,
            restore: replace,
            groupId: _cardGroup(cardGroups, table, row),
          );
        }
      }
      await txn.insert('sync_imports', {
        'source_id': source.record.id,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await _recount(txn);
    });
    workspace.database.notifyStudyChanged();
  }

  Future<List<Map<String, Object?>>> files() async {
    final db = await database;
    final tables = {
      for (final table in ['documents', 'source_pages', 'page_normalizations'])
        table: await db.query(table),
    };
    return fileReferences(tables);
  }
}

List<Map<String, Object?>> fileReferences(
  Map<String, List<Map<String, Object?>>> tables,
) {
  final result = <String, Map<String, Object?>>{};
  void add(Object? path, Object? hash, Object? bytes, Object? mime) {
    if (path == null) return;
    final key = path as String;
    if (!safeFileKey(key) || !key.startsWith('documents/')) {
      throw const AccountFailure(
        'invalid_file',
        'Đường dẫn nguồn không hợp lệ.',
      );
    }
    result[key] = {
      'fileKey': key,
      'sha256': hash,
      'sizeBytes': bytes,
      'mimeType': mime,
    };
  }

  for (final row in tables['documents'] ?? []) {
    add(
      row['original_file_relative_path'],
      row['original_file_sha256'],
      row['original_file_size_bytes'],
      row['original_file_mime_type'],
    );
  }
  for (final row in tables['source_pages'] ?? []) {
    add(
      row['data_relative_path'],
      row['sha256'],
      row['file_size_bytes'],
      row['mime_type'],
    );
  }
  for (final row in tables['page_normalizations'] ?? []) {
    add(
      row['normalized_relative_path'],
      row['sha256'],
      row['file_size_bytes'],
      row['mime_type'],
    );
  }
  return result.values.toList();
}
