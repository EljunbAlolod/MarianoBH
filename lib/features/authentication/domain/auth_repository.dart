import 'app_user.dart';

abstract interface class AuthRepository {
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  Future<void> signIn({required String email, required String password});

  Future<void> signInWithGoogle();

  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  });

  Future<void> sendPasswordResetEmail(String email);

  Future<void> sendEmailVerification();

  Future<AppUser?> reloadCurrentUser();

  Future<void> signOut();
}

class AuthException implements Exception {
  const AuthException(this.message, {this.code = 'unknown'});

  final String code;
  final String message;

  @override
  String toString() => message;
}
