class AccountIdentity {
  const AccountIdentity({
    required this.uid,
    required this.email,
    required this.emailVerified,
    this.providers = const [],
  });
  final String uid, email;
  final bool emailVerified;
  final List<String> providers;
}

class AccountFailure implements Exception {
  const AccountFailure(
    this.code,
    this.message, {
    this.httpStatus,
    this.storageCode,
    this.requestId,
    this.missingParents = const [],
  });
  final String code, message;
  final int? httpStatus;
  final String? storageCode, requestId;
  final List<Map<String, String>> missingParents;
  @override
  String toString() => message;
}

abstract class AuthRepository {
  AccountIdentity? get current;
  Stream<AccountIdentity?> get changes;
  Future<AccountIdentity?> signInGoogle();
  Future<AccountIdentity> signInEmail(String email, String password);
  Future<AccountIdentity> register(String email, String password);
  Future<void> sendVerification();
  Future<void> refresh();
  Future<void> resetPassword(String email);
  Future<String> token({bool refresh = false});
  Future<void> signOut();
  Future<void> linkGoogle();
  Future<void> linkEmail(String email, String password);
  Future<void> reauthenticate({String? password});
}
