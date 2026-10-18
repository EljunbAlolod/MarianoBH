import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../onboarding/domain/owner_repository.dart';
import '../domain/auth_repository.dart';
import 'app_session_controller.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  throw StateError('authRepositoryProvider must be overridden at startup.');
});

final ownerRepositoryProvider = Provider<OwnerRepository>((ref) {
  throw StateError('ownerRepositoryProvider must be overridden at startup.');
});

final appSessionProvider = Provider<AppSessionController>((ref) {
  final controller = AppSessionController(
    ref.watch(authRepositoryProvider),
    ref.watch(ownerRepositoryProvider),
  )..start();
  ref.onDispose(controller.dispose);
  return controller;
});
