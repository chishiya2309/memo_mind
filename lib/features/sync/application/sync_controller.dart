import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/workspace/workspace_context.dart';
import '../../account_backup/domain/auth_repository.dart';
import '../../account_backup/data/snapshot_codec.dart';
import '../data/local_sync_store.dart';
import '../data/sync_api_client.dart';

class SyncController extends ChangeNotifier {
  SyncController({
    required this.auth,
    required this.workspaces,
    SyncApiClient? api,
  }) : api = api ?? SyncApiClient(auth: auth) {
    _authChanges = auth.changes.listen((identity) {
      if (identity?.uid != _uid) {
        _epoch++;
        this.api.cancelTransfers();
        _retry?.cancel();
        _debounce?.cancel();
        _uid = identity?.uid;
        conflicts = [];
        lastSynced = null;
        needsMigration = false;
        error = null;
        mediaStatus = null;
        _failures = 0;
        status = identity == null
            ? 'Đăng nhập để đồng bộ'
            : 'Có thay đổi chưa đồng bộ';
        _notify();
      }
    });
    _uid = auth.current?.uid;
  }
  final AuthRepository auth;
  final WorkspaceRepository workspaces;
  final SyncApiClient api;
  late final StreamSubscription<AccountIdentity?> _authChanges;
  StreamSubscription<void>? _studyChanges;
  StreamSubscription<dynamic>? _connectivity;
  Timer? _dirtyPoll;
  Timer? _debounce, _retry;
  int _epoch = 0, _failures = 0;
  String? _uid;
  bool _disposed = false, _running = false;
  bool needsMigration = false;
  String status = 'Đăng nhập để đồng bộ';
  String? error, mediaStatus;
  DateTime? lastSynced;
  List<Map<String, dynamic>> conflicts = [];
  WorkspaceRecord? migrationSource;
  Future<void> Function({bool force})? checkpoint;
  bool get busy => _running;
  bool get available =>
      auth.current?.emailVerified == true &&
      workspaces.current?.record.ownerUid == auth.current?.uid;
  LocalSyncStore get store => LocalSyncStore(workspaces.current!);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> bind() async {
    final epoch = ++_epoch;
    api.cancelTransfers();
    _debounce?.cancel();
    _retry?.cancel();
    _dirtyPoll?.cancel();
    await _connectivity?.cancel();
    await _studyChanges?.cancel();
    if (_disposed || epoch != _epoch) return;
    lastSynced = null;
    conflicts = [];
    if (!available ||
        !await workspaces.isCanonical(workspaces.current!.record)) {
      return;
    }
    final context = workspaces.current!;
    if (_disposed || epoch != _epoch || !context.active) return;
    final local = LocalSyncStore(context);
    final last = await local.setting('lastSynced');
    lastSynced = last == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(int.parse(last));
    conflicts = await local.conflicts();
    if (_disposed || epoch != _epoch || !context.active) return;
    _studyChanges = context.database.studyChanges.listen((_) {
      if (!_running) {
        status = 'Có thay đổi chưa đồng bộ';
        _notify();
        if (_retry?.isActive != true) schedule();
      }
    });
    _dirtyPoll = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!_running &&
          _retry?.isActive != true &&
          _debounce?.isActive != true &&
          !needsMigration &&
          context.active &&
          await local.hasPending) {
        schedule(immediate: true);
      }
    });
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _connectivity = const EventChannel('memo_mind/connectivity')
          .receiveBroadcastStream()
          .listen(
            (value) {
              if (value == true) connectivityRestored();
            },
            onError: (_) {
              /* retries and resume remain available */
            },
          );
    }
    _notify();
    schedule(immediate: true);
  }

  /// A canonical workspace is created separately; legacy and guest data stay intact.
  Future<WorkspaceRecord> prepareAccount({WorkspaceRecord? guest}) async {
    final uid = auth.current!.uid;
    final previous = workspaces.current!.record;
    final canonical = await workspaces.canonical(uid);
    migrationSource =
        guest ??
        (previous.ownerUid == uid && previous.id != canonical.id
            ? previous
            : null);
    final context = WorkspaceContext(canonical, -1);
    try {
      final cloud = await api.request('GET', '/status', uid: uid);
      if (cloud['initialized'] == true) {
        if (guest != null) await _import(context, guest);
      } else {
        final cached = LocalSyncStore(context);
        final alreadyAccepted =
            await cached.setting('migrationAccepted') == '1';
        needsMigration = !alreadyAccepted;
        if (guest != null) {
          await _import(context, guest);
          await cached.setSetting('migrationAccepted', '1');
          await api.request(
            'POST',
            '/initialize',
            uid: uid,
            body: {'sourceId': guest.id},
          );
          needsMigration = false;
        } else if (alreadyAccepted) {
          await api.request(
            'POST',
            '/initialize',
            uid: uid,
            body: {'sourceId': canonical.id},
          );
        }
      }
    } on AccountFailure catch (e) {
      error = e.message;
      status = 'Đang offline';
      if (guest != null) {
        await _import(context, guest);
        await LocalSyncStore(context).setSetting('migrationAccepted', '1');
      }
    } finally {
      await context.revoke();
    }
    return canonical;
  }

  Future<void> _import(WorkspaceContext target, WorkspaceRecord source) async {
    final context = WorkspaceContext(source, -2);
    try {
      await LocalSyncStore(target).importWorkspace(context);
    } finally {
      await context.revoke();
    }
  }

  Future<void> acceptMigration({WorkspaceRecord? source}) async {
    if (!available || _running) return;
    final context = workspaces.current!,
        uid = auth.current!.uid,
        epoch = _epoch;
    if (source?.ownerUid != null && source!.ownerUid != uid) {
      throw const AccountFailure(
        'wrong_workspace',
        'Dữ liệu thuộc tài khoản khác.',
      );
    }
    await checkpoint?.call(force: true);
    _check(context, uid, epoch);
    if (source != null && source.id != context.record.id) {
      await _import(context, source);
    }
    _check(context, uid, epoch);
    final local = LocalSyncStore(context);
    await local.seed();
    _check(context, uid, epoch);
    await local.setSetting('migrationAccepted', '1');
    await api.request(
      'POST',
      '/initialize',
      uid: uid,
      body: {'sourceId': source?.id ?? context.record.id},
    );
    _check(context, uid, epoch);
    needsMigration = false;
    await syncNow();
  }

  void schedule({bool immediate = false}) {
    if (_disposed || !available || needsMigration) return;
    _debounce?.cancel();
    _debounce = Timer(
      immediate ? Duration.zero : const Duration(seconds: 3),
      () => unawaited(syncNow()),
    );
  }

  void resumed() => schedule(immediate: true);
  void connectivityRestored() => schedule(immediate: true);
  Future<bool> get hasPending async => available && await store.hasPending;

  bool _valid(WorkspaceContext context, String uid, int epoch) =>
      !_disposed &&
      _epoch == epoch &&
      auth.current?.uid == uid &&
      context.active &&
      identical(workspaces.current, context);
  void _check(WorkspaceContext context, String uid, int epoch) {
    if (!_valid(context, uid, epoch)) {
      throw const AccountFailure(
        'sync_cancelled',
        'Tài khoản hoặc thư viện đã thay đổi.',
      );
    }
  }

  Future<void> syncNow() async {
    if (_running || !available || _disposed) return;
    final context = workspaces.current!,
        uid = auth.current!.uid,
        epoch = _epoch;
    final local = LocalSyncStore(context);
    _running = true;
    _retry?.cancel();
    status = 'Đang đồng bộ';
    error = null;
    _notify();
    try {
      if (!await workspaces.isCanonical(context.record)) return;
      _check(context, uid, epoch);
      final cloud = await api.request('GET', '/status', uid: uid);
      _check(context, uid, epoch);
      if (cloud['initialized'] != true) {
        if (await local.setting('migrationAccepted') != '1') {
          needsMigration = true;
          status = 'Chọn dữ liệu ban đầu để đồng bộ';
          return;
        }
        await api.request(
          'POST',
          '/initialize',
          uid: uid,
          body: {'sourceId': context.record.id},
        );
      }
      needsMigration = false;
      await _pull(local, uid, context, epoch);
      while (true) {
        _check(context, uid, epoch);
        final packet = await local.nextPacket(
          WorkspaceRuntime.deviceId ?? 'device',
        );
        if (packet == null) break;
        Map<String, dynamic> result;
        try {
          result = await _pushPacket(packet, uid, context, epoch);
        } on AccountFailure catch (failure) {
          _check(context, uid, epoch);
          if (failure.code == 'conflict_changed' &&
              packet.body['resolveConflictId'] != null) {
            await local.requeueRejectedResolution(packet);
            continue;
          }
          rethrow;
        }
        _check(context, uid, epoch);
        await local.acknowledge(packet, result);
      }
      await _pull(local, uid, context, epoch);
      _check(context, uid, epoch);
      await local.materializeMirrors();
      if (!await local.hasPending) await local.setSetting('restoring', '0');
      final response = await api.request('GET', '/conflicts', uid: uid);
      _check(context, uid, epoch);
      await local.saveConflicts(response['conflicts'] as List);
      conflicts = await local.conflicts();
      mediaStatus = 'Đang đồng bộ ảnh và PDF';
      _notify();
      await _syncFiles(local, uid, context, epoch);
      _check(context, uid, epoch);
      mediaStatus = null;
      lastSynced = DateTime.now();
      await local.setSetting(
        'lastSynced',
        '${lastSynced!.millisecondsSinceEpoch}',
      );
      _failures = 0;
      status = conflicts.isEmpty
          ? 'Đã đồng bộ'
          : 'Đã đồng bộ · ${conflicts.length} mục cần chọn nội dung';
      // Recovery checkpoints cannot prevent study synchronization succeeding.
      try {
        await checkpoint?.call(force: false);
      } catch (_) {
        /* retried after next successful sync */
      }
    } catch (e) {
      if (_valid(context, uid, epoch)) {
        final failure = e is AccountFailure
            ? e
            : const AccountFailure(
                'waiting_network',
                'Chưa đồng bộ được. Dữ liệu được giữ trên thiết bị.',
              );
        error = failure.message;
        status = failure.code == 'reauth_required'
            ? 'Cần đăng nhập lại'
            : failure.code == 'email_unverified'
            ? 'Cần xác minh email'
            : ['waiting_network', 'unconfirmed'].contains(failure.code)
            ? 'Đang offline'
            : 'Chưa đồng bộ được';
        if (mediaStatus != null) mediaStatus = 'Ảnh và PDF chưa đồng bộ đầy đủ';
        if (![
          'reauth_required',
          'email_unverified',
          'sync_cancelled',
          'sync_limit',
          'invalid_sync',
          'incompatible_sync',
        ].contains(failure.code)) {
          final seconds = (5 * (1 << (_failures++).clamp(0, 6))).clamp(5, 300);
          _retry?.cancel();
          _retry = Timer(
            Duration(seconds: seconds),
            () => unawaited(syncNow()),
          );
        }
      }
    } finally {
      _running = false;
      _notify();
      if (!_disposed && _epoch != epoch) {
        schedule(immediate: true);
      } else if (_valid(context, uid, epoch) &&
          error == null &&
          await local.hasPending) {
        status = 'Có thay đổi chưa đồng bộ';
        schedule();
      }
    }
  }

  Future<Map<String, dynamic>> _pushPacket(
    SyncPacket packet,
    String uid,
    WorkspaceContext context,
    int epoch,
  ) async {
    final ops = (packet.body['operations'] as List).cast<Map>();
    if (ops.length <= 50 &&
        utf8.encode(jsonEncode(packet.body)).length < 950000) {
      return api.request(
        'POST',
        packet.body['resolveConflictId'] != null
            ? '/conflicts/${packet.body['resolveConflictId']}/resolve'
            : packet.body['restore'] == true
            ? '/restore'
            : '/push',
        uid: uid,
        body: packet.body,
      );
    }
    final parts = <List<Map>>[];
    var current = <Map>[];
    var bytes = 0;
    for (final op in ops) {
      final size = utf8.encode(jsonEncode(op)).length;
      if (current.length == 50 || bytes + size > 900000) {
        parts.add(current);
        current = [];
        bytes = 0;
      }
      current.add(op);
      bytes += size;
    }
    if (current.isNotEmpty) parts.add(current);
    for (var i = 0; i < parts.length; i++) {
      await api.request(
        'POST',
        '/stage',
        uid: uid,
        body: {
          'groupId': packet.body['groupId'],
          'deviceId': packet.body['deviceId'],
          'restore': packet.body['restore'] == true,
          'partIndex': i,
          'partsCount': parts.length,
          'operations': parts[i],
        },
      );
      _check(context, uid, epoch);
    }
    return api.request(
      'POST',
      '/commit',
      uid: uid,
      body: {'groupId': packet.body['groupId']},
    );
  }

  Future<void> _pull(
    LocalSyncStore local,
    String uid,
    WorkspaceContext context,
    int epoch,
  ) async {
    while (true) {
      final response = await api.request(
        'GET',
        '/changes?cursor=${await local.readCursor}&limit=100',
        uid: uid,
      );
      _check(context, uid, epoch);
      await local.applyChanges(response);
      if (response['hasMore'] != true) break;
    }
  }

  Future<void> _syncFiles(
    LocalSyncStore local,
    String uid,
    WorkspaceContext context,
    int epoch,
  ) async {
    for (final ref in await local.files()) {
      _check(context, uid, epoch);
      final hash = ref['sha256'] as String, key = ref['fileKey'] as String;
      final file = File(
        p.joinAll([context.record.filesPath, ...key.split('/')]),
      );
      final stat = await file.stat();
      final signature =
          '$hash:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
      if (stat.type == FileSystemEntityType.file &&
          stat.size == ref['sizeBytes'] &&
          await local.setting('verified.$key') == signature &&
          await local.setting('uploaded.$hash') == '1') {
        continue;
      }
      if (await file.exists() &&
          await file.length() == ref['sizeBytes'] &&
          await fileHash(file) == hash) {
        if (await local.setting('uploaded.$hash') == '1') {
          await local.setSetting('verified.$key', signature);
          continue;
        }
        final result = await api.request(
          'POST',
          '/files/$hash',
          uid: uid,
          body: {'sizeBytes': ref['sizeBytes'], 'mimeType': ref['mimeType']},
        );
        _check(context, uid, epoch);
        if (result['ready'] != true) {
          await api.upload(
            file,
            Map<String, dynamic>.from(result['upload'] as Map),
            (_) {},
          );
          _check(context, uid, epoch);
          final verified = await api.request(
            'POST',
            '/files/$hash',
            uid: uid,
            body: {'sizeBytes': ref['sizeBytes'], 'mimeType': ref['mimeType']},
          );
          if (verified['ready'] != true) {
            throw const AccountFailure(
              'file_pending',
              'Tệp nguồn chưa được xác nhận.',
            );
          }
        }
        await local.setSetting('uploaded.$hash', '1');
        await local.setSetting('verified.$key', signature);
      } else {
        final result = await api.request('GET', '/files/$hash', uid: uid);
        _check(context, uid, epoch);
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.${const Uuid().v4()}.part');
        try {
          await api.download(result['url'] as String, temporary);
          _check(context, uid, epoch);
          if (await temporary.length() != ref['sizeBytes'] ||
              await fileHash(temporary) != hash) {
            throw const AccountFailure(
              'checksum_mismatch',
              'Ảnh hoặc PDF tải về bị hỏng.',
            );
          }
          if (await file.exists()) await file.delete();
          await temporary.rename(file.path);
          await local.setSetting('uploaded.$hash', '1');
          final received = await file.stat();
          await local.setSetting(
            'verified.$key',
            '$hash:${received.size}:${received.modified.microsecondsSinceEpoch}',
          );
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
      }
    }
  }

  Future<void> resolve(
    Map<String, dynamic> conflict,
    Map<String, dynamic> selected, {
    Map<String, dynamic>? edited,
  }) async {
    if (!available || _running) return;
    final data = edited ?? Map<String, dynamic>.from(selected['data'] as Map);
    await store.queueResolution(conflict, data, selected['deleted'] == true);
    await syncNow();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _debounce?.cancel();
    _retry?.cancel();
    api.cancelTransfers();
    _authChanges.cancel();
    _dirtyPoll?.cancel();
    _connectivity?.cancel();
    _studyChanges?.cancel();
    super.dispose();
  }
}
