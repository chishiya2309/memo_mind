import 'dart:async';
import 'dart:io';

import 'package:memo_mind/features/account_backup/domain/auth_repository.dart';
import 'package:memo_mind/features/account_backup/data/backup_api_client.dart';

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
    if (verificationFails)
      throw const AccountFailure('too-many-requests', 'Chưa gửi được email');
  }

  @override
  Future<void> refresh() async {
    if (current != null)
      change(
        AccountIdentity(
          uid: current!.uid,
          email: current!.email,
          emailVerified: true,
          providers: current!.providers,
        ),
      );
  }

  @override
  Future<void> resetPassword(String email) async {}
  @override
  Future<String> token({bool refresh = false}) async => 'fake-token';
  @override
  Future<void> signOut() async => change(null);
  @override
  Future<void> linkGoogle() async {}
  @override
  Future<void> linkEmail(String email, String password) async {}
  @override
  Future<void> reauthenticate({String? password}) async {}
}

class FakeBackupApi extends BackupApiClient {
  FakeBackupApi(AuthRepository auth)
    : super(auth: auth, baseUrl: 'https://configured.example');
  Map<String, dynamic>? registered;
  final uploading = Completer<void>();
  Completer<void>? holdUpload;
  Completer<void>? holdFinalize;
  int begins = 0, finalizes = 0;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String suffix, {
    Map<String, Object?>? body,
    required String uid,
  }) async {
    if (auth.current?.uid != uid)
      throw const AccountFailure('reauth_required', 'Account changed');
    if (method == 'GET' && suffix.isEmpty)
      return {'backups': <Map<String, dynamic>>[]};
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
    if (!uploading.isCompleted) uploading.complete();
    progress(0.5);
    await holdUpload?.future;
    progress(1);
  }
}
