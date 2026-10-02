import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this.auth);
  final FirebaseAuth auth;
  bool _googleInitialized = false;
  AccountIdentity? _map(User? u) => u == null
      ? null
      : AccountIdentity(
          uid: u.uid,
          email: u.email ?? '',
          emailVerified: u.emailVerified,
          providers: u.providerData.map((p) => p.providerId).toList(),
        );
  @override
  AccountIdentity? get current => _map(auth.currentUser);
  @override
  Stream<AccountIdentity?> get changes => auth.userChanges().map(_map);
  Future<T> _call<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      throw AccountFailure(e.code, switch (e.code) {
        'network-request-failed' =>
          'Cần kết nối mạng. Bạn vẫn có thể học trên thiết bị.',
        'too-many-requests' => 'Quá nhiều yêu cầu. Vui lòng đợi rồi thử lại.',
        'user-disabled' => 'Tài khoản đã bị vô hiệu hóa.',
        'requires-recent-login' => 'Cần xác thực lại trước thao tác này.',
        'credential-already-in-use' ||
        'account-exists-with-different-credential' => 'Phương thức này thuộc tài khoản khác. Hãy đăng nhập bằng phương thức hiện có; dữ liệu sẽ không được gộp.',
        'weak-password' =>
          'Mật khẩu mới phải đạt chính sách tối thiểu 8 ký tự.',
        'email-already-in-use' => 'Không thể tạo tài khoản với email này. Hãy thử đăng nhập hoặc đặt lại mật khẩu.',
        _ => 'Không thể thực hiện yêu cầu với thông tin đã cung cấp.',
      });
    }
  }

  Future<AuthCredential?> _googleCredential() async {
    if (!_googleInitialized) {
      const clientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
      await GoogleSignIn.instance.initialize(
        serverClientId: clientId.isEmpty ? null : clientId,
      );
      _googleInitialized = true;
    }
    try {
      final user = await GoogleSignIn.instance.authenticate();
      return GoogleAuthProvider.credential(
        idToken: user.authentication.idToken,
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw const AccountFailure(
        'google_failed',
        'Không thể đăng nhập Google. Kiểm tra mạng và cấu hình ứng dụng.',
      );
    }
  }

  @override
  Future<AccountIdentity?> signInGoogle() => _call(() async {
    final credential = await _googleCredential();
    if (credential == null) return null;
    return _map((await auth.signInWithCredential(credential)).user);
  });
  @override
  Future<AccountIdentity> signInEmail(String email, String password) => _call(
    () async => _map(
      (await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      )).user,
    )!,
  );
  @override
  Future<AccountIdentity> register(String email, String password) => _call(
    () async => _map(
      (await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      )).user,
    )!,
  );
  @override
  Future<void> sendVerification() =>
      _call(() async => auth.currentUser!.sendEmailVerification());
  @override
  Future<void> refresh() => _call(() async {
    await auth.currentUser?.reload();
    await auth.currentUser?.getIdToken(true);
  });
  @override
  Future<void> resetPassword(String email) => _call(() async {
    try {
      await auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      if (e.code != 'user-not-found') rethrow;
    }
  });
  @override
  Future<String> token({bool refresh = false}) => _call(() async {
    final value = await auth.currentUser?.getIdToken(refresh);
    if (value == null)
      throw const AccountFailure('reauth_required', 'Cần đăng nhập lại.');
    return value;
  });
  @override
  Future<void> signOut() async {
    await auth.signOut();
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        /* Firebase sign-out is authoritative. */
      }
    }
  }

  @override
  Future<void> linkGoogle() => _call(() async {
    final credential = await _googleCredential();
    if (credential == null) return;
    await auth.currentUser!.linkWithCredential(credential);
    await refresh();
  });
  @override
  Future<void> linkEmail(String email, String password) => _call(() async {
    await auth.currentUser!.linkWithCredential(
      EmailAuthProvider.credential(email: email.trim(), password: password),
    );
    await refresh();
  });
  @override
  Future<void> reauthenticate({String? password}) => _call(() async {
    final user = auth.currentUser!;
    final credential = password == null
        ? await _googleCredential()
        : EmailAuthProvider.credential(email: user.email!, password: password);
    if (credential == null)
      throw const AccountFailure('cancelled', 'Đã hủy xác thực lại.');
    await user.reauthenticateWithCredential(credential);
  });
}

class UnconfiguredAuthRepository implements AuthRepository {
  const UnconfiguredAuthRepository();
  @override
  AccountIdentity? get current => null;
  @override
  Stream<AccountIdentity?> get changes => const Stream.empty();
  Never _fail() => throw const AccountFailure(
    'auth_not_configured',
    'Firebase chưa được cấu hình. Bạn vẫn có thể học trên thiết bị.',
  );
  @override
  Future<AccountIdentity?> signInGoogle() async => _fail();
  @override
  Future<AccountIdentity> signInEmail(String email, String password) async =>
      _fail();
  @override
  Future<AccountIdentity> register(String email, String password) async =>
      _fail();
  @override
  Future<void> sendVerification() async => _fail();
  @override
  Future<void> refresh() async => _fail();
  @override
  Future<void> resetPassword(String email) async => _fail();
  @override
  Future<String> token({bool refresh = false}) async => _fail();
  @override
  Future<void> signOut() async {}
  @override
  Future<void> linkGoogle() async => _fail();
  @override
  Future<void> linkEmail(String email, String password) async => _fail();
  @override
  Future<void> reauthenticate({String? password}) async => _fail();
}
