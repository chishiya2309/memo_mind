import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/memo_mind_database.dart';

class WorkspaceRecord {
  const WorkspaceRecord({
    required this.id,
    required this.databasePath,
    required this.filesPath,
    this.ownerUid,
    this.name = 'Kho học',
    this.status = 'ready',
  });
  final String id, databasePath, filesPath, name, status;
  final String? ownerUid;
  factory WorkspaceRecord.fromRow(Map<String, Object?> r) => WorkspaceRecord(
    id: r['workspace_id'] as String,
    ownerUid: r['owner_uid'] as String?,
    databasePath: r['database_path'] as String,
    filesPath: r['files_path'] as String,
    name: r['name'] as String,
    status: r['status'] as String,
  );
}

/// Immutable binding captured by repositories. Revoked handles cannot reopen.
class WorkspaceContext {
  WorkspaceContext(this.record, this.generation)
    : database = MemoMindDatabase.atPath(record.databasePath);
  final WorkspaceRecord record;
  final int generation;
  final MemoMindDatabase database;
  bool active = true;
  Future<Directory> directory() async {
    if (!active) throw StateError('Kho đã được chuyển.');
    return Directory(record.filesPath);
  }

  Future<void> revoke() async {
    active = false;
    await database.revoke();
  }
}

class WorkspaceRuntime {
  static WorkspaceContext? current;
  static String? deviceId;
  static MemoMindDatabase? deviceSettings;
  static MemoMindDatabase get database =>
      current?.database ?? MemoMindDatabase.instance;
  static Future<Directory> Function() captureDirectory() =>
      current?.directory ?? getApplicationSupportDirectory;
}

class WorkspaceRepository {
  WorkspaceRepository({this.rootPath, this.databaseRoot});
  final String? rootPath, databaseRoot;
  late Database registry;
  late String _support, _databases;
  int _generation = 0;
  WorkspaceContext? current;

  Future<void> initialize({String? uid}) async {
    _support = rootPath ?? (await getApplicationSupportDirectory()).path;
    _databases = databaseRoot ?? await getDatabasesPath();
    await Directory(_support).create(recursive: true);
    await Directory(_databases).create(recursive: true);
    registry = await openDatabase(
      p.join(_databases, 'workspace_registry.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE workspaces(workspace_id TEXT PRIMARY KEY, owner_uid TEXT, name TEXT NOT NULL, database_path TEXT NOT NULL UNIQUE, files_path TEXT NOT NULL, status TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE selections(owner_key TEXT PRIMARY KEY, workspace_id TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE app_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE backup_jobs(backup_id TEXT PRIMARY KEY, owner_uid TEXT NOT NULL, workspace_id TEXT NOT NULL, payload TEXT NOT NULL)',
        );
      },
    );
    if ((await registry.query('workspaces')).isEmpty) {
      final legacyPath = p.join(_databases, 'memo_mind.db');
      final legacy = MemoMindDatabase.atPath(legacyPath);
      final db = await legacy.database;
      for (final setting in await db.query('app_settings')) {
        await registry.insert(
          'app_settings',
          setting,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await legacy.close();
      await registry.insert('workspaces', {
        'workspace_id': const Uuid().v4(),
        'owner_uid': null,
        'name': 'Kho trên thiết bị',
        'database_path': legacyPath,
        'files_path': _support,
        'status': 'ready',
      });
    }
    await registry.insert('app_settings', {
      'key': 'device_id',
      'value': const Uuid().v4(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    WorkspaceRuntime.deviceId =
        (await registry.query(
              'app_settings',
              where: 'key=?',
              whereArgs: ['device_id'],
            )).single['value']
            as String;
    WorkspaceRuntime.deviceSettings = MemoMindDatabase.forTesting(registry);
    await select(await preferred(uid));
  }

  Future<List<WorkspaceRecord>> available(String? uid) async =>
      (await registry.query(
        'workspaces',
        where: uid == null
            ? "owner_uid IS NULL AND status='ready'"
            : "(owner_uid IS NULL OR owner_uid=?) AND status='ready'",
        whereArgs: uid == null ? null : [uid],
        orderBy: 'rowid',
      )).map(WorkspaceRecord.fromRow).toList();
  Future<WorkspaceRecord> preferred(String? uid) async {
    final records = (await available(uid))
        .where((r) => r.ownerUid == uid)
        .toList();
    if (records.isEmpty) return create(uid);
    final saved = await registry.query(
      'selections',
      where: 'owner_key=?',
      whereArgs: [uid ?? 'guest'],
    );
    final id = saved.isEmpty ? null : saved.single['workspace_id'];
    return records.firstWhere((r) => r.id == id, orElse: () => records.first);
  }

  Future<WorkspaceRecord> create(
    String? uid, {
    String name = 'Kho học',
    String status = 'ready',
  }) async {
    final id = const Uuid().v4();
    final files = p.join(_support, 'workspaces', id);
    final databasePath = p.join(_databases, 'workspaces', '$id.db');
    await Directory(files).create(recursive: true);
    await Directory(p.dirname(databasePath)).create(recursive: true);
    final db = MemoMindDatabase.atPath(databasePath);
    await db.database;
    await db.close();
    await registry.insert('workspaces', {
      'workspace_id': id,
      'owner_uid': uid,
      'name': name,
      'database_path': databasePath,
      'files_path': files,
      'status': status,
    });
    return WorkspaceRecord(
      id: id,
      ownerUid: uid,
      name: name,
      status: status,
      databasePath: databasePath,
      filesPath: files,
    );
  }

  Future<WorkspaceRecord> attach(String workspaceId, String uid) async {
    await registry.transaction((txn) async {
      final count = await txn.update(
        'workspaces',
        {'owner_uid': uid},
        where: "workspace_id=? AND owner_uid IS NULL AND status='ready'",
        whereArgs: [workspaceId],
      );
      if (count != 1) throw StateError('Chỉ kho khách mới được gắn tài khoản.');
    });
    return get(workspaceId);
  }

  Future<WorkspaceRecord> get(String id) async => WorkspaceRecord.fromRow(
    (await registry.query(
      'workspaces',
      where: 'workspace_id=?',
      whereArgs: [id],
    )).single,
  );
  Future<void> select(
    WorkspaceRecord record, {
    Future<void> Function()? beforeRevoke,
  }) async {
    if (record.status != 'ready') throw StateError('Kho chưa sẵn sàng.');
    if (!await File(record.databasePath).exists()) {
      throw StateError('Không tìm thấy database của kho.');
    }
    final next = WorkspaceContext(record, ++_generation);
    try {
      await next.database.database;
      await registry.insert('selections', {
        'owner_key': record.ownerUid ?? 'guest',
        'workspace_id': record.id,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await beforeRevoke?.call();
      await current?.revoke();
      current = next;
      WorkspaceRuntime.current = next;
    } catch (_) {
      await next.revoke();
      rethrow;
    }
  }

  Future<void> publish(String id) async {
    await registry.update(
      'workspaces',
      {'status': 'ready'},
      where: 'workspace_id=?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    await current?.revoke();
    if (identical(WorkspaceRuntime.current, current)) {
      WorkspaceRuntime.current = null;
    }
    WorkspaceRuntime.deviceSettings = null;
    WorkspaceRuntime.deviceId = null;
    await registry.close();
  }
}
