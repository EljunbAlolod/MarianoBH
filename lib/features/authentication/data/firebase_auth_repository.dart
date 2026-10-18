import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/app_user.dart';
import '../domain/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._firebaseAuth);

  final FirebaseAuth _firebaseAuth;
  Future<void>? _googleSignInInitialization;

  @override
  Stream<AppUser?> authStateChanges() {
    return _firebaseAuth.userChanges().map(_mapUser);
  }

  @override
  AppUser? get currentUser => _mapUser(_firebaseAuth.currentUser);

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw _friendlyException(error);
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    final GoogleSignInAccount account;
    try {
      await (_googleSignInInitialization ??=
          GoogleSignIn.instance.initialize());
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return;
      throw _googleSignInException(error);
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException(
        'Google did not return the details needed to sign in. '
        'Please try again or use your email and password.',
        code: 'google-missing-id-token',
      );
    }

    try {
      await _firebaseAuth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    } on FirebaseAuthException catch (error) {
      throw _friendlyException(error);
    }
  }

  @override
  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthException(
          'The account was created, but no signed-in user was returned.',
          code: 'missing-user',
        );
      }
      await user.updateDisplayName(displayName.trim());
      await user.sendEmailVerification();
      await user.reload();
    } on FirebaseAuthException catch (error) {
      throw _friendlyException(error);
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      // A reset response must not reveal whether an email address is registered.
      if (error.code == 'user-not-found') return;
      throw _friendlyException(error);
    }
  }

  @override
  Future<void> sendEmailVerification() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw const AuthException(
        'Your session has ended. Please sign in again.',
        code: 'signed-out',
      );
    }
    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (error) {
      throw _friendlyException(error);
    }
  }

  @override
  Future<AppUser?> reloadCurrentUser() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    try {
      await user.reload();
      final refreshed = _firebaseAuth.currentUser;
      await refreshed?.getIdToken(true);
      return _mapUser(refreshed);
    } on FirebaseAuthException catch (error) {
      throw _friendlyException(error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Firebase sign-out is the source of truth; clearing the cached Google
      // session is best-effort and unavailable on some platforms.
    }
    try {
      await _firebaseAuth.signOut();
    } on FirebaseAuthException catch (error) {
      throw _friendlyException(error);
    }
  }

  static AppUser? _mapUser(User? user) {
    if (user == null) return null;
    return AppUser(
      id: user.uid,
      email: user.email ?? '',
      isEmailVerified: user.emailVerified,
      displayName: user.displayName,
    );
  }

  static AuthException _friendlyException(FirebaseAuthException error) {
    final message = switch (error.code) {
      'invalid-email' => 'Enter a valid email address.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'The email or password is incorrect.',
      'email-already-in-use' =>
        'An account already uses this email address. Try signing in instead.',
      'account-exists-with-different-credential' =>
        'An account already uses this email with a password. '
            'Please sign in with your email and password instead.',
      'weak-password' => 'Use a stronger password with at least 8 characters.',
      'user-disabled' =>
        'This account has been disabled. Contact the app administrator.',
      'network-request-failed' =>
        'No internet connection. Check your connection and try again.',
      'too-many-requests' =>
        'Too many attempts were made. Wait a moment and try again.',
      'operation-not-allowed' =>
        'This sign-in method is not enabled for this Firebase project.',
      _ => 'Authentication could not be completed. Please try again.',
    };
    return AuthException(message, code: error.code);
  }

  static AuthException _googleSignInException(GoogleSignInException error) {
    final message = switch (error.code) {
      GoogleSignInExceptionCode.interrupted =>
        'Google sign-in was interrupted. Please try again.',
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Google sign-in is not set up correctly for this app. '
            'Please sign in with your email and password instead.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'The Google sign-in screen could not be opened right now. '
            'Please try again.',
      GoogleSignInExceptionCode.userMismatch =>
        'That Google account cannot be used right now. Please try again.',
      _ => 'Google sign-in could not be completed. Please try again.',
    };
    return AuthException(message, code: 'google-${error.code.name}');
  }
}
