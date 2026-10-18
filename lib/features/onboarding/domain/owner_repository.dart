import '../../authentication/domain/app_user.dart';
import 'owner_workspace.dart';

abstract interface class OwnerRepository {
  Future<OwnerWorkspace?> fetchWorkspace(AppUser user);

  Future<OwnerWorkspace> createWorkspace({
    required AppUser user,
    required String ownerName,
    required String houseName,
  });
}

class OwnerRepositoryException implements Exception {
  const OwnerRepositoryException(
    this.message, {
    this.code = 'unknown',
    this.isOffline = false,
  });

  final String code;
  final String message;
  final bool isOffline;

  @override
  String toString() => message;
}
