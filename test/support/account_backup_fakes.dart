import 'dart:async';
import 'dart:io';

import 'package:memo_mind/features/account_backup/domain/auth_repository.dart';
import 'package:memo_mind/features/account_backup/data/backup_api_client.dart';
import 'package:memo_mind/features/sync/data/sync_api_client.dart';

class FakeSyncApi extends SyncApiClient {
  FakeSyncApi(AuthRepository auth)
    : super(auth: auth, baseUrl: 'https://configured.example');
  int revision = 0;
  final requests = <String>[];
  AccountFailure? failure;
  Completer<void>? holdRequest;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String suffix, {
    Map<String, Object?>? body,
    required String uid,
  }) async {
    requests.add('$method $suffix');
    await holdRequest?.future;
    if (failure != null) throw failure!;
    if (suffix == '/status' || suffix == '/initialize') {
      return {'initialized': true, 'revision': revision};
    }
    if (suffix.startsWith('/changes')) {
      return {'changes': <Map>[], 'cursor': revision, 'hasMore': false};
    }
    if (suffix == '/conflicts') return {'conflicts': <Map>[]};
    if (suffix == '/push') {
      return {
        'receipts': [
          for (final op in body!['operations'] as List)
            {'operationId': (op as Map)['operationId'], 'version': ++revision},
        ],
        'revision': revision,
      };
    }
    throw const AccountFailure('fake_unsupported', 'Unsupported test route');
  }
}

class FakeAccountAuth implements AuthRepository {
  FakeAccountAuth({AccountIdentity? identity}) : current = identity;
  @override
  AccountIdentity? current;
  final updates = StreamController<AccountIdentity?>.broadcast();
  @override
  Stream<AccountIdentity?> get changes => updates.stream;
  int registrations = 0, logins = 0;
  bool verificationFails = false;
  String? suppliedPassword;
  final tokenRefreshes = <bool>[];
  Future<void> Function(bool)? onToken;
  AccountFailure? reauthenticationFailure;
  int reauthentications = 0;
  void change(AccountIdentity? identity) {
    current = identity;
    updates.add(identity);
  }

  @override
  Future<AccountIdentity?> signInGoogle() async => null;
  @override
  Future<AccountIdentity> signInEmail(String email, String password) async {
    logins++;
    suppliedPassword = password;
    current = AccountIdentity(
      uid: 'A',
      email: email,
      emailVerified: true,
      providers: ['password'],
    );
    updates.add(current);
    return current!;
  }

  @override
  Future<AccountIdentity> register(String email, String password) async {
    registrations++;
    suppliedPassword = password;
    current = AccountIdentity(
      uid: 'A',
      email: email,
      emailVerified: false,
      providers: ['password'],
    );
    updates.add(current);
    return current!;
  }

  @override
  Future<void> sendVerification() async {
    if (verificationFails) {
      throw const AccountFailure('too-many-requests', 'Chưa gửi được email');
    }
  }

  @override
  Future<void> refresh() async {
    if (current != null) {
      change(
        AccountIdentity(
          uid: current!.uid,
          email: current!.email,
          emailVerified: true,
          providers: current!.providers,
        ),
      );
    }
  }

  @override
  Future<void> resetPassword(String email) async {}
  @override
  Future<String> token({bool refresh = false}) async {
    tokenRefreshes.add(refresh);
    await onToken?.call(refresh);
    return refresh ? 'refreshed-token' : 'fake-token';
  }

  @override
  Future<void> signOut() async => change(null);
  @override
  Future<void> linkGoogle() async {}
  @override
  Future<void> linkEmail(String email, String password) async {}
  @override
  Future<void> reauthenticate({String? password}) async {
    reauthentications++;
    suppliedPassword = password;
    if (reauthenticationFailure != null) throw reauthenticationFailure!;
  }
}

class FakeBackupApi extends BackupApiClient {
  FakeBackupApi(AuthRepository auth)
    : super(auth: auth, baseUrl: 'https://configured.example');
  Map<String, dynamic>? registered;
  final uploading = Completer<void>();
  Completer<void>? holdUpload;
  Completer<void>? holdFinalize;
  int begins = 0, finalizes = 0;
  String jobStatus = 'uploading';
  bool failNextUpload = false;
  bool loseNextFinalizeResponse = false;
  File? downloadArchive;
  AccountFailure? listFailure;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String suffix, {
    Map<String, Object?>? body,
    required String uid,
  }) async {
    if (auth.current?.uid != uid) {
      throw const AccountFailure('reauth_required', 'Account changed');
    }
    final cloud = registered == null
        ? null
        : {
            ...registered!,
            'status': jobStatus,
            'completedAt': jobStatus == 'ready' ? 300 : null,
          };
    if (method == 'GET' && suffix.isEmpty) {
      if (listFailure != null) {
        throw listFailure!;
      }
      return {
        'backups': <Map<String, dynamic>>[
          if (cloud != null && jobStatus == 'ready') cloud,
        ],
      };
    }
    if (method == 'POST' && suffix.endsWith('/download-url')) {
      return {'backup': cloud!, 'url': 'https://s3.example/fixture'};
    }
    if (method == 'GET' && cloud != null && suffix == '/${cloud['backupId']}') {
      return {'backup': cloud};
    }
    if (method == 'POST' && suffix.isEmpty) {
      begins++;
      registered = {...body!};
      return {
        'backup': {...registered!, 'status': 'uploading'},
        'upload': <String, dynamic>{},
      };
    }
    if (suffix.endsWith('/finalize')) {
      finalizes++;
      await holdFinalize?.future;
      jobStatus = 'ready';
      if (loseNextFinalizeResponse) {
        loseNextFinalizeResponse = false;
        throw const AccountFailure('unconfirmed', 'Lost response');
      }
      return {
        'backup': {...registered!, 'status': 'ready', 'completedAt': 300},
      };
    }
    throw const AccountFailure('backup_not_found', 'Not found');
  }

  @override
  Future<void> upload(
    File file,
    Map<String, dynamic> upload,
    void Function(double) progress,
  ) async {
    if (!uploading.isCompleted) {
      uploading.complete();
    }
    progress(0.5);
    if (failNextUpload) {
      failNextUpload = false;
      throw const AccountFailure('waiting_network', 'Network unavailable');
    }
    await holdUpload?.future;
    progress(1);
  }

  @override
  Future<void> download(String url, File destination) async {
    await downloadArchive!.copy(destination.path);
  }
}
