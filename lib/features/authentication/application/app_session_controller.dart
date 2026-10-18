import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../onboarding/domain/owner_repository.dart';
import '../../onboarding/domain/owner_workspace.dart';
import '../domain/app_user.dart';
import '../domain/auth_repository.dart';

enum AppSessionStatus {
  loading,
  signedOut,
  emailUnverified,
  onboardingRequired,
  ready,
  offline,
  failure,
}

@immutable
class AppSessionState {
  const AppSessionState({
    required this.status,
    this.user,
    this.workspace,
    this.message,
  });

  const AppSessionState.loading() : this(status: AppSessionStatus.loading);

  final AppSessionStatus status;
  final AppUser? user;
  final OwnerWorkspace? workspace;
  final String? message;
}

class AppSessionController extends ChangeNotifier {
  AppSessionController(this._authRepository, this._ownerRepository);

  final AuthRepository _authRepository;
  final OwnerRepository _ownerRepository;
  StreamSubscription<AppUser?>? _authSubscription;
  AppSessionState _state = const AppSessionState.loading();
  int _resolutionId = 0;
  String? _intendedLocation;

  AppSessionState get state => _state;

  void start() {
    _authSubscription ??= _authRepository.authStateChanges().listen(
      _resolveUser,
      onError: (Object error, StackTrace stackTrace) {
        _setState(
          const AppSessionState(
            status: AppSessionStatus.failure,
            message: 'Your session could not be checked. Please try again.',
          ),
        );
      },
    );
  }

  Future<void> _resolveUser(AppUser? user) async {
    final resolutionId = ++_resolutionId;
    if (user == null) {
      _setState(const AppSessionState(status: AppSessionStatus.signedOut));
      return;
    }
    if (!user.isEmailVerified) {
      _setState(
        AppSessionState(status: AppSessionStatus.emailUnverified, user: user),
      );
      return;
    }

    _setState(AppSessionState(status: AppSessionStatus.loading, user: user));
    try {
      final workspace = await _ownerRepository.fetchWorkspace(user);
      if (resolutionId != _resolutionId) return;
      _setState(
        AppSessionState(
          status: workspace == null
              ? AppSessionStatus.onboardingRequired
              : AppSessionStatus.ready,
          user: user,
          workspace: workspace,
        ),
      );
    } on OwnerRepositoryException catch (error) {
      if (resolutionId != _resolutionId) return;
      _setState(
        AppSessionState(
          status: error.isOffline
              ? AppSessionStatus.offline
              : AppSessionStatus.failure,
          user: user,
          message: error.message,
        ),
      );
    } catch (_) {
      if (resolutionId != _resolutionId) return;
      _setState(
        AppSessionState(
          status: AppSessionStatus.failure,
          user: user,
          message: 'The owner account could not be loaded. Please try again.',
        ),
      );
    }
  }

  Future<void> refreshUser() async {
    _setState(
      AppSessionState(status: AppSessionStatus.loading, user: state.user),
    );
    try {
      final user = await _authRepository.reloadCurrentUser();
      await _resolveUser(user);
    } on AuthException catch (error) {
      _setState(
        AppSessionState(
          status: AppSessionStatus.failure,
          user: state.user,
          message: error.message,
        ),
      );
    }
  }

  Future<void> workspaceCreated(OwnerWorkspace workspace) async {
    final user = state.user;
    if (user == null) return;
    _setState(
      AppSessionState(
        status: AppSessionStatus.ready,
        user: user,
        workspace: workspace,
      ),
    );
  }

  Future<void> retry() => _resolveUser(_authRepository.currentUser);

  void rememberIntendedLocation(String location) {
    if (location == '/dashboard' || location == '/settings') {
      _intendedLocation = location;
    }
  }

  String takeIntendedLocation() {
    final location = _intendedLocation ?? '/dashboard';
    _intendedLocation = null;
    return location;
  }

  void _setState(AppSessionState value) {
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _resolutionId++;
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }
}
