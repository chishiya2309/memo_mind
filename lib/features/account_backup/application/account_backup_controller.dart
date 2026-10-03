import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../core/workspace/workspace_context.dart';
import '../data/backup_api_client.dart';
import '../data/snapshot_codec.dart';
import '../domain/auth_repository.dart';

class AccountBackupController extends ChangeNotifier {
  AccountBackupController({
    required this.auth,
    required this.workspaces,
    BackupApiClient? api,
    SnapshotCodec? codec,
  }) : api = api ?? BackupApiClient(auth: auth),
       codec = codec ?? SnapshotCodec() {
    _authChanges = auth.changes.listen((identity) {
      if (identity?.uid != _observedUid) {
        this.api.cancelTransfers();
        _observedUid = identity?.uid;
      }
      _publish();
    });
    _observedUid = auth.current?.uid;
    _watchStudyChanges();
  }
  final AuthRepository auth;
  final WorkspaceRepository workspaces;
  final BackupApiClient api;
  final SnapshotCodec codec;
  late final StreamSubscription<AccountIdentity?> _authChanges;
  String? _observedUid;
  StreamSubscription<void>? _studyChanges;
  bool _closed = false;
  void _publish() {
    if (!_closed) notifyListeners();
  }

  void _watchStudyChanges() {
    _studyChanges = workspace.database.studyChanges.listen((_) {
      unawaited(refreshLocal());
    });
  }

  Future<void> refreshLocal() async {
    if (busy || _closed) return;
    final generation = workspace.generation;
    try {
      final jobs = await _localJobs(workspace.record.id);
      final changed = await hasChanges();
      if (_closed || workspace.generation != generation || busy) return;
      status = jobs.any((j) => j['status'] == 'ready')
          ? (changed
                ? 'Có dữ liệu mới chưa sao lưu'
                : 'Dữ liệu đã được sao lưu')
          : 'Chưa sao lưu';
      _publish();
    } catch (_) {
      /* A workspace switch invalidates old handles. */
    }
  }

  Future<void> Function()? beforeSwitch;
  final _inFlight = <String>{};
  List<Map<String, dynamic>> backups = [];
  bool stale = false, cloudLoading = false;
  int accountScreens = 0;
  bool get accountScreenVisible => accountScreens > 0;
  String? message;
  String status = 'Chưa sao lưu';
  double progress = 0;
  WorkspaceContext get workspace => workspaces.current!;
  AccountIdentity? get account => auth.current;
  bool get accessAllowed =>
      workspace.record.ownerUid == null ||
      workspace.record.ownerUid == account?.uid;
  bool get busy => _inFlight.contains(workspace.record.id);
  bool get canBackup =>
      account?.emailVerified == true &&
      workspace.record.ownerUid == account?.uid &&
      !busy;

  Future<void> select(WorkspaceRecord record) async {
    if (record.ownerUid != null && record.ownerUid != account?.uid) {
      throw const AccountFailure(
        'wrong_workspace',
        'Kho thuộc tài khoản khác.',
      );
    }
    api.cancelTransfers();
    await workspaces.select(record, beforeRevoke: beforeSwitch);
    await _studyChanges?.cancel();
    backups = [];
    stale = false;
    cloudLoading = false;
    status = 'Chưa sao lưu';
    _watchStudyChanges();
    _publish();
  }

  Future<void> afterLogin({required bool attachGuest}) async {
    final uid = account!.uid;
    final old = workspace.record;
    if (attachGuest && old.ownerUid == null) {
      await attachGuestWorkspace(old.id, uid);
    } else if (account?.emailVerified != true && old.ownerUid == null) {
      _publish();
    } else {
      await select(await workspaces.preferred(uid));
    }
  }

  Future<void> attachGuestWorkspace(String id, String uid) async {
    if (account?.uid != uid || account?.emailVerified != true) {
      throw const AccountFailure(
        'email_unverified',
        'Xác minh email trước khi gắn kho với tài khoản.',
      );
    }
    final guest = await workspaces.get(id);
    final owned = await workspaces.attach(id, uid);
    try {
      await select(owned);
    } catch (_) {
      // Publication failed: retain the guest ownership visible before consent.
      if (workspaces.current?.record.id == guest.id &&
          workspaces.current?.record.ownerUid == null) {
        await workspaces.registry.update(
          'workspaces',
          {'owner_uid': null},
          where: 'workspace_id=? AND owner_uid=?',
          whereArgs: [id, uid],
        );
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    api.cancelTransfers();
    await auth.signOut();
    await select(await workspaces.preferred(null));
  }

  Future<List<Map<String, dynamic>>> _localJobs(String workspaceId) async =>
      (await workspaces.registry.query(
            'backup_jobs',
            where: 'workspace_id=?',
            whereArgs: [workspaceId],
          ))
          .map(
            (r) => jsonDecode(r['payload'] as String) as Map<String, dynamic>,
          )
          .toList();
  Future<bool> hasChanges() async {
    final db = await workspace.database.database;
    final revision = (await db.query('workspace_revision')).single['revision'];
    final jobs = (await _localJobs(workspace.record.id))
        .where((j) => j['status'] == 'ready')
        .toList();
    return !jobs.any((j) => j['snapshotRevision'] == revision);
  }

  Future<void> _save(Map<String, dynamic> job) async {
    await workspaces.registry.insert('backup_jobs', {
      'backup_id': job['backupId'],
      'owner_uid': job['ownerUid'],
      'workspace_id': job['workspaceId'],
      'payload': jsonEncode(job),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _cleanSnapshot(Map<String, dynamic> job) async {
    // Only remove the generated directory belonging to this local job.
    try {
      final record = await workspaces.get(job['workspaceId'] as String);
      final root = p.normalize(
        p.absolute(p.join(record.filesPath, '.backups')),
      );
      final folder = p.normalize(p.absolute(p.dirname(job['path'] as String)));
      if (p.dirname(folder) != root || p.basename(folder) != job['backupId']) {
        return;
      }
      final directory = Directory(folder);
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {
      // A cleanup error cannot undo cloud confirmation. Retry on reconciliation.
    }
  }

  bool _visible(WorkspaceContext source, String uid) =>
      workspace.generation == source.generation && account?.uid == uid;
  void _state(
    WorkspaceContext source,
    String uid,
    String value, [
    double? fraction,
  ]) {
    if (!_visible(source, uid)) return;
    status = value;
    if (fraction != null) progress = fraction;
    _publish();
  }

  Future<void> refreshCloud() async {
    await refreshLocal();
    final uid = account?.uid, generation = workspace.generation;
    if (uid == null || account?.emailVerified != true) return;
    cloudLoading = true;
    _publish();
    try {
      final response = await api.request('GET', '', uid: uid);
      final values = (response['backups'] as List).cast<Map<String, dynamic>>();
      await workspaces.registry.insert('app_settings', {
        'key': 'fr18.metadata.$uid',
        'value': jsonEncode(values),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (account?.uid == uid && workspace.generation == generation) {
        backups = values;
        stale = false;
        message = null;
      }
      await reconcile();
    } catch (error) {
      if (account?.uid == uid && workspace.generation == generation) {
        final cached = await workspaces.registry.query(
          'app_settings',
          where: 'key=?',
          whereArgs: ['fr18.metadata.$uid'],
        );
        if (cached.isNotEmpty) {
          backups = (jsonDecode(cached.single['value'] as String) as List)
              .cast<Map<String, dynamic>>();
        }
        stale = true;
        message = error is AccountFailure
            ? error.message
            : 'Không thể đọc metadata cloud.';
      }
    } finally {
      if (account?.uid == uid && workspace.generation == generation) {
        cloudLoading = false;
        _publish();
      }
    }
  }

  Future<void> reconcile() async {
    final uid = account?.uid;
    if (uid == null) return;
    for (final job in await _localJobs(workspace.record.id)) {
      if (job['ownerUid'] != uid || job['status'] == 'ready' || busy) continue;
      try {
        final response = await api.request(
          'GET',
          '/${job['backupId']}',
          uid: uid,
        );
        final cloud = response['backup'] as Map<String, dynamic>;
        if (cloud['status'] == 'ready') {
          job['status'] = 'ready';
          job['completedAt'] = cloud['completedAt'];
          await _save(job);
          await _cleanSnapshot(job);
        }
      } on AccountFailure catch (error) {
        if (error.code != 'backup_not_found') rethrow;
      }
    }
    if (!busy) {
      status = await hasChanges()
          ? 'Có dữ liệu mới chưa sao lưu'
          : 'Dữ liệu đã được sao lưu';
      _publish();
    }
  }

  Future<void> backup({bool retry = false}) async {
    if (!canBackup) {
      throw const AccountFailure(
        'backup_unavailable',
        'Xác minh email và chọn kho của tài khoản trước khi sao lưu.',
      );
    }
    final source = workspace, uid = account!.uid;
    if (!_inFlight.add(source.record.id)) return;
    Map<String, dynamic>? job;
    try {
      _state(source, uid, 'Đang chụp snapshot…', 0);
      final pending = (await _localJobs(source.record.id))
          .where(
            (j) =>
                j['ownerUid'] == uid &&
                j['status'] != 'ready' &&
                j['status'] != 'cancelled',
          )
          .toList();
      if (pending.isNotEmpty) {
        job = pending.last;
        final prior = await api
            .request('GET', '/${job['backupId']}', uid: uid)
            .catchError((Object e) {
              if (e is AccountFailure && e.code == 'backup_not_found') {
                return <String, dynamic>{};
              }
              throw e;
            });
        if ((prior['backup'] as Map?)?['status'] == 'ready') {
          job['status'] = 'ready';
          job['completedAt'] = (prior['backup'] as Map)['completedAt'];
          await _save(job);
          await _cleanSnapshot(job);
          _state(source, uid, 'Đã đối chiếu: sao lưu thành công');
          return;
        }
        if (!await File(job['path'] as String).exists()) {
          if (prior['backup'] != null) {
            await api.request('DELETE', '/${job['backupId']}', uid: uid);
          }
          job['status'] = 'cancelled';
          await _save(job);
          job = null;
        }
      }
      if (job == null) {
        final snapshot = await codec.capture(source, uid);
        job = {
          ...snapshot.request,
          'path': snapshot.path,
          'status': 'uploading',
          'retryCount': 0,
        };
        await _save(job);
      }
      job['retryCount'] = (job['retryCount'] as int) + 1;
      await _save(job);
      if (account?.uid != uid || !source.active) {
        throw const AccountFailure(
          'reauth_required',
          'Tài khoản hoặc kho đã thay đổi.',
        );
      }
      final response = await api.request('POST', '', uid: uid, body: job);
      var cloud = response['backup'] as Map<String, dynamic>;
      if (cloud['status'] != 'ready') {
        _state(source, uid, 'Đang tải lên…');
        await api.upload(
          File(job['path'] as String),
          response['upload'] as Map<String, dynamic>,
          (value) => _state(source, uid, 'Đang tải lên…', value),
        );
        _state(source, uid, 'Đang kiểm tra bản sao…');
        cloud =
            (await api.request(
                  'POST',
                  '/${job['backupId']}/finalize',
                  uid: uid,
                ))['backup']
                as Map<String, dynamic>;
      }
      if (cloud['status'] != 'ready') {
        throw const AccountFailure(
          'unconfirmed',
          'Chưa xác nhận bản sao hoàn tất.',
        );
      }
      job['status'] = 'ready';
      job['completedAt'] = cloud['completedAt'];
      job['cloudBackupId'] = cloud['backupId'];
      await _save(job);
      await _cleanSnapshot(job);
      if (_visible(source, uid)) {
        status = await hasChanges()
            ? 'Sao lưu thành công. Có dữ liệu mới chưa sao lưu'
            : 'Sao lưu thành công';
        backups.removeWhere((b) => b['backupId'] == cloud['backupId']);
        backups.insert(0, cloud);
        stale = false;
        _publish();
      }
    } catch (error) {
      if (job != null) {
        job['status'] = error is AccountFailure ? error.code : 'error';
        job['lastError'] = error is AccountFailure
            ? error.message
            : 'Không thể tạo bản sao. Kiểm tra tệp và bộ nhớ thiết bị.';
        await _save(job);
      }
      _state(
        source,
        uid,
        error is AccountFailure
            ? error.message
            : 'Không thể tạo bản sao. Kiểm tra tệp và bộ nhớ thiết bị.',
      );
      rethrow;
    } finally {
      _inFlight.remove(source.record.id);
      if (_visible(source, uid)) _publish();
    }
  }

  Future<void> deleteBackup(Map<String, dynamic> backup) async {
    final uid = account!.uid;
    await api.request('DELETE', '/${backup['backupId']}', uid: uid);
    for (final job in await _localJobs(backup['workspaceId'] as String)) {
      if (job['backupId'] == backup['backupId'] ||
          job['cloudBackupId'] == backup['backupId']) {
        job['status'] = 'cancelled';
        await _save(job);
      }
    }
    await refreshCloud();
  }

  Future<WorkspaceRecord> restore(Map<String, dynamic> backup) async {
    final uid = account!.uid;
    final generation = workspace.generation;
    final response = await api.request(
      'POST',
      '/${backup['backupId']}/download-url',
      uid: uid,
    );
    final root = Directory(
      p.join(
        workspace.record.filesPath,
        '.restore',
        backup['backupId'] as String,
      ),
    );
    await root.create(recursive: true);
    final file = File(p.join(root.path, 'snapshot.zip'));
    try {
      await api.download(response['url'] as String, file);
      if (account?.uid != uid) {
        throw const AccountFailure('reauth_required', 'Tài khoản đã thay đổi.');
      }
      final record = await codec.restore(
        file,
        response['backup'] as Map<String, dynamic>,
        uid,
        workspaces,
      );
      if (account?.uid != uid || workspace.generation != generation) {
        throw const AccountFailure(
          'reauth_required',
          'Tài khoản hoặc kho đã thay đổi; kho khôi phục được giữ riêng cho UID gốc.',
        );
      }
      return record;
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  }

  @override
  void dispose() {
    _closed = true;
    api.cancelTransfers();
    _authChanges.cancel();
    _studyChanges?.cancel();
    super.dispose();
  }
}
