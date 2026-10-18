import 'package:cloud_firestore/cloud_firestore.dart';

import '../../authentication/domain/app_user.dart';
import '../domain/owner_repository.dart';
import '../domain/owner_workspace.dart';

class FirestoreOwnerRepository implements OwnerRepository {
  FirestoreOwnerRepository(this._firestore);

  static const primaryHouseId = 'primary';

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _profile(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  DocumentReference<Map<String, dynamic>> _house(String uid) {
    return _firestore
        .collection('owners')
        .doc(uid)
        .collection('boardingHouses')
        .doc(primaryHouseId);
  }

  @override
  Future<OwnerWorkspace?> fetchWorkspace(AppUser user) async {
    try {
      // Server-only reads prevent an empty offline cache from being mistaken for
      // a brand-new owner account.
      final results = await Future.wait([
        _profile(user.id).get(const GetOptions(source: Source.server)),
        _house(user.id).get(const GetOptions(source: Source.server)),
      ]);
      final profile = results[0];
      final house = results[1];

      if (!profile.exists && !house.exists) return null;
      if (!profile.exists || !house.exists) {
        throw const OwnerRepositoryException(
          'The owner account is incomplete. Please contact support before making changes.',
          code: 'incomplete-workspace',
        );
      }
      return _workspaceFromDocuments(user, profile.data()!, house.data()!);
    } on FirebaseException catch (error) {
      throw _mapFirestoreException(error);
    }
  }

  @override
  Future<OwnerWorkspace> createWorkspace({
    required AppUser user,
    required String ownerName,
    required String houseName,
  }) async {
    if (!user.isEmailVerified) {
      throw const OwnerRepositoryException(
        'Verify your email address before setting up the boarding house.',
        code: 'email-not-verified',
      );
    }

    final cleanOwnerName = ownerName.trim();
    final cleanHouseName = houseName.trim();
    try {
      return await _firestore.runTransaction((transaction) async {
        final profileRef = _profile(user.id);
        final houseRef = _house(user.id);
        final profile = await transaction.get(profileRef);
        final house = await transaction.get(houseRef);

        if (profile.exists && house.exists) {
          return _workspaceFromDocuments(user, profile.data()!, house.data()!);
        }
        if (profile.exists || house.exists) {
          throw const OwnerRepositoryException(
            'The owner account is incomplete. Please contact support before making changes.',
            code: 'incomplete-workspace',
          );
        }

        final timestamp = FieldValue.serverTimestamp();
        transaction.set(profileRef, {
          'email': user.email,
          'displayName': cleanOwnerName,
          'primaryHouseId': primaryHouseId,
          'createdAt': timestamp,
          'updatedAt': timestamp,
        });
        transaction.set(houseRef, {
          'ownerUid': user.id,
          'name': cleanHouseName,
          'currencyCode': 'PHP',
          'businessTimeZone': 'Asia/Manila',
          'schemaVersion': 1,
          'createdAt': timestamp,
          'updatedAt': timestamp,
        });

        return OwnerWorkspace(
          ownerUid: user.id,
          ownerName: cleanOwnerName,
          ownerEmail: user.email,
          houseName: cleanHouseName,
        );
      });
    } on OwnerRepositoryException {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapFirestoreException(error);
    }
  }

  OwnerWorkspace _workspaceFromDocuments(
    AppUser user,
    Map<String, dynamic> profile,
    Map<String, dynamic> house,
  ) {
    if (house['ownerUid'] != user.id ||
        profile['primaryHouseId'] != primaryHouseId) {
      throw const OwnerRepositoryException(
        'The owner account failed an ownership check.',
        code: 'invalid-ownership',
      );
    }
    return OwnerWorkspace(
      ownerUid: user.id,
      ownerName: profile['displayName'] as String? ?? '',
      ownerEmail: profile['email'] as String? ?? user.email,
      houseName: house['name'] as String? ?? 'Boarding House',
      currencyCode: house['currencyCode'] as String? ?? 'PHP',
      businessTimeZone: house['businessTimeZone'] as String? ?? 'Asia/Manila',
    );
  }

  OwnerRepositoryException _mapFirestoreException(FirebaseException error) {
    final isOffline =
        error.code == 'unavailable' ||
        error.code == 'network-request-failed' ||
        error.code == 'deadline-exceeded';
    return OwnerRepositoryException(
      isOffline
          ? 'The owner record could not be checked while offline.'
          : 'The owner record could not be loaded. Please try again.',
      code: error.code,
      isOffline: isOffline,
    );
  }
}
