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

enum SyncPhase {
  signedOut,
  ready,
  pending,
  syncing,
  synced,
  migration,
  reauthenticate,
  verifyEmail,
  blocked,
  failed,
}

enum SyncMediaPhase { idle, syncing, pending }

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
        mediaPhase = SyncMediaPhase.idle;
        _failures = 0;
        automatic = false;
        pendingChanges = false;
        failureCode = null;
        phase = identity == null ? SyncPhase.signedOut : SyncPhase.ready;
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
  SyncPhase phase = SyncPhase.signedOut;
  bool automatic = false, pendingChanges = false;
  String? failureCode;
  bool get requiresAuthentication => phase == SyncPhase.reauthenticate;
  bool get accountBlocked =>
      const ['account_disabled', 'account_deleted'].contains(failureCode);
  bool get _retryable =>
      failureCode == null ||
      const [
        'waiting_network',
        'unconfirmed',
        'auth_service_unavailable',
        'file_pending',
        'download_failed',
        'checksum_mismatch',
        'service_unavailable',
        'server_error',
        'too-many-requests',
      ].contains(failureCode);
  String get status => switch (phase) {
    SyncPhase.signedOut => 'Đăng nhập để đồng bộ',
    SyncPhase.ready => 'Đồng bộ để tải thư viện',
    SyncPhase.pending => 'Có thay đổi chưa đồng bộ',
    SyncPhase.syncing => 'Đang đồng bộ',
    SyncPhase.synced =>
      conflicts.isEmpty
          ? 'Đã đồng bộ'
          : 'Đã đồng bộ · ${conflicts.length} mục cần chọn nội dung',
    SyncPhase.migration => 'Chọn dữ liệu ban đầu để đồng bộ',
    SyncPhase.reauthenticate => 'Xác thực lại để đồng bộ',
    SyncPhase.verifyEmail => 'Cần xác minh email',
    SyncPhase.blocked => 'Đồng bộ đang tạm dừng',
    SyncPhase.failed => 'Chưa kết nối được dịch vụ',
  };
  String? error;
  SyncMediaPhase mediaPhase = SyncMediaPhase.idle;
  String? get mediaStatus => switch (mediaPhase) {
    SyncMediaPhase.idle => null,
    SyncMediaPhase.syncing => 'Đang đồng bộ ảnh và PDF',
    SyncMediaPhase.pending => 'Ảnh và PDF chưa đồng bộ đầy đủ',
  };
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
    automatic = false;
    pendingChanges = false;
    error = null;
    failureCode = null;
    mediaPhase = SyncMediaPhase.idle;
    needsMigration = false;
    phase = auth.current == null
        ? SyncPhase.signedOut
        : auth.current!.emailVerified
        ? SyncPhase.ready
        : SyncPhase.verifyEmail;
    if (!available ||
        !await workspaces.isCanonical(workspaces.current!.record)) {
      _notify();
      return;
    }
    final context = workspaces.current!;
    if (_disposed || epoch != _epoch || !context.active) return;
    final local = LocalSyncStore(context);
    final last = await local.setting('lastSynced');
    final savedConflicts = await local.conflicts();
    final savedAutomatic = await local.setting('automaticSync') == '1';
    final savedPending = await local.hasPending;
    final mediaPending = await local.setting('mediaPending') == '1';
    if (_disposed || epoch != _epoch || !context.active) return;
    lastSynced = last == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(int.parse(last));
    conflicts = savedConflicts;
    automatic = savedAutomatic;
    pendingChanges = savedPending;
    mediaPhase = mediaPending ? SyncMediaPhase.pending : SyncMediaPhase.idle;
    phase = pendingChanges
        ? SyncPhase.pending
        : lastSynced == null
        ? SyncPhase.ready
        : SyncPhase.synced;
    _studyChanges = context.database.studyChanges.listen((_) {
      if (!_running) {
        unawaited(_refreshPending(context, epoch));
      }
    });
    _dirtyPoll = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!_running &&
          _retry?.isActive != true &&
          _debounce?.isActive != true &&
          !needsMigration &&
          context.active &&
          epoch == _epoch) {
        await _refreshPending(context, epoch);
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

  Future<void> _refreshPending(WorkspaceContext context, int epoch) async {
    try {
      final pending = await LocalSyncStore(context).hasPending;
      if (_disposed || epoch != _epoch || !context.active) return;
      pendingChanges = pending;
      if (!_running && failureCode == null && !needsMigration) {
        phase = pending
            ? SyncPhase.pending
            : lastSynced == null
            ? SyncPhase.ready
            : SyncPhase.synced;
      }
      _notify();
      if (pending && _retry?.isActive != true) schedule();
    } catch (_) {
      // A workspace may be revoked while its local status is being read.
    }
  }

  Future<void> setAutomatic(bool value) async {
    if (!available) return;
    final context = workspaces.current!, epoch = _epoch;
    await LocalSyncStore(context)
        .setSetting('automaticSync', value ? '1' : '0');
    if (_disposed || epoch != _epoch || !context.active) return;
    automatic = value;
    _debounce?.cancel();
    _retry?.cancel();
    _notify();
    if (value) schedule(immediate: true);
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
      // Cloud discovery belongs to an explicit sync, not signing in.
      needsMigration = false;
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
    if (_disposed ||
        !automatic ||
        !available ||
        needsMigration ||
        !_retryable ||
        _running) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(
      immediate ? Duration.zero : const Duration(seconds: 3),
      () => unawaited(syncNow()),
    );
  }

  void resumed() => schedule(immediate: true);
  void connectivityRestored() => schedule(immediate: true);
  Future<bool> get hasPending async =>
      auth.current != null &&
      workspaces.current?.record.ownerUid == auth.current!.uid &&
      (await store.hasPending || await store.setting('mediaPending') == '1');

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
    _debounce?.cancel();
    _retry?.cancel();
    phase = SyncPhase.syncing;
    failureCode = null;
    error = null;
    _notify();
    try {
      if (!await workspaces.isCanonical(context.record)) {
        throw const AccountFailure(
          'wrong_workspace',
          'Mở thư viện của tài khoản trước khi đồng bộ.',
        );
      }
      _check(context, uid, epoch);
      final cloud = await api.request('GET', '/status', uid: uid);
      _check(context, uid, epoch);
      if (cloud['initialized'] != true) {
        if (await local.setting('migrationAccepted') != '1') {
          needsMigration = true;
          phase = SyncPhase.migration;
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
      final currentConflicts = await local.conflicts();
      _check(context, uid, epoch);
      conflicts = currentConflicts;
      lastSynced = DateTime.now();
      await local.setSetting(
        'lastSynced',
        '${lastSynced!.millisecondsSinceEpoch}',
      );
      _check(context, uid, epoch);
      await local.setSetting('mediaPending', '1');
      _check(context, uid, epoch);
      mediaPhase = SyncMediaPhase.syncing;
      _notify();
      await _syncFiles(local, uid, context, epoch);
      _check(context, uid, epoch);
      await local.setSetting('mediaPending', '0');
      _check(context, uid, epoch);
      mediaPhase = SyncMediaPhase.idle;
      _failures = 0;
      phase = SyncPhase.synced;
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
                'sync_failed',
                'Chưa đồng bộ được. Dữ liệu được giữ trên thiết bị.',
              );
        error = failure.message;
        failureCode = failure.code;
        phase = failure.code == 'reauth_required'
            ? SyncPhase.reauthenticate
            : failure.code == 'email_unverified'
            ? SyncPhase.verifyEmail
            : _retryable
            ? SyncPhase.failed
            : SyncPhase.blocked;
        if (mediaPhase == SyncMediaPhase.syncing) {
          mediaPhase = SyncMediaPhase.pending;
        }
        if (automatic && _retryable) {
          final seconds = (5 * (1 << (_failures++).clamp(0, 6))).clamp(5, 300);
          _retry?.cancel();
          _retry = Timer(
            Duration(seconds: seconds),
            () => unawaited(syncNow()),
          );
        }
      }
    } finally {
      try {
        if (_valid(context, uid, epoch)) {
          final pending = await local.hasPending;
          if (_valid(context, uid, epoch)) {
            pendingChanges = pending;
            if (error == null && pending && !needsMigration) {
              phase = SyncPhase.pending;
            }
          }
        }
      } catch (_) {
        // Status reads can race with workspace revocation; the next bind reloads them.
      } finally {
        _running = false;
        _notify();
        if (!_disposed && _epoch != epoch) {
          schedule(immediate: true);
        } else if (_valid(context, uid, epoch) &&
            error == null &&
            pendingChanges) {
          schedule();
        }
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
