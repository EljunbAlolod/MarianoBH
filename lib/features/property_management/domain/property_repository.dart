import 'boarder.dart';
import 'business_date.dart';
import 'occupancy.dart';
import 'room.dart';

abstract class PropertyRepository {
  Stream<List<Room>> watchRooms(String ownerId);

  Stream<List<Boarder>> watchBoarders(String ownerId);

  Stream<List<Occupancy>> watchOccupancies(String ownerId, String boarderId);

  Stream<List<Occupancy>> watchAllOccupancies(String ownerId);

  Future<String> createRoom({
    required String ownerId,
    required String roomName,
    String description = '',
    int? defaultMonthlyRentCentavos,
  });

  Future<void> updateRoom({
    required String ownerId,
    required String roomId,
    required String roomName,
    String description = '',
    int? defaultMonthlyRentCentavos,
  });

  Future<void> deactivateRoom({
    required String ownerId,
    required String roomId,
  });

  Future<void> reactivateRoom({
    required String ownerId,
    required String roomId,
  });

  Future<String> createBoarder({
    required String ownerId,
    required String fullName,
    String? contact,
    String? notes,
    required String roomId,
    required BusinessDate moveInDate,
  });

  Future<void> updateBoarder({
    required String ownerId,
    required String boarderId,
    required String fullName,
    String? contact,
    String? notes,
  });

  Future<void> deactivateBoarder({
    required String ownerId,
    required String boarderId,
  });

  Future<void> moveOut({
    required String ownerId,
    required String boarderId,
    required BusinessDate moveOutDate,
  });

  Future<void> moveIn({
    required String ownerId,
    required String boarderId,
    required String roomId,
    required BusinessDate moveInDate,
  });

  Future<void> transfer({
    required String ownerId,
    required String boarderId,
    required String toRoomId,
    required BusinessDate transferDate,
  });
}

class PropertyRepositoryException implements Exception {
  const PropertyRepositoryException(
    this.message, {
    required this.code,
    this.isOffline = false,
    this.isConflict = false,
  });

  final String message;
  final String code;
  final bool isOffline;
  final bool isConflict;

  @override
  String toString() => 'PropertyRepositoryException($code): $message';
}

abstract final class PropertyValidation {
  static const roomNameMaxLength = 80;
  static const roomDescriptionMaxLength = 500;
  static const boarderNameMaxLength = 120;
  static const contactMaxLength = 120;
  static const notesMaxLength = 1000;

  static String requiredText(
    String value, {
    required String label,
    required int maxLength,
  }) {
    final clean = value.trim();
    if (clean.isEmpty) {
      throw PropertyRepositoryException(
        '$label is required.',
        code: 'invalid-argument',
      );
    }
    if (clean.length > maxLength) {
      throw PropertyRepositoryException(
        '$label must be $maxLength characters or fewer.',
        code: 'invalid-argument',
      );
    }
    return clean;
  }

  static String limitedText(
    String value, {
    required String label,
    required int maxLength,
  }) {
    final clean = value.trim();
    if (clean.length > maxLength) {
      throw PropertyRepositoryException(
        '$label must be $maxLength characters or fewer.',
        code: 'invalid-argument',
      );
    }
    return clean;
  }

  static String? optionalText(
    String? value, {
    required String label,
    required int maxLength,
  }) {
    if (value == null) return null;
    final clean = limitedText(value, label: label, maxLength: maxLength);
    return clean.isEmpty ? null : clean;
  }

  static int? rentCentavos(int? value) {
    if (value != null && value < 0) {
      throw const PropertyRepositoryException(
        'Monthly rent cannot be negative.',
        code: 'invalid-argument',
      );
    }
    return value;
  }

  static BusinessDate recordedDate(
    BusinessDate value, {
    DateTime? now,
    String label = 'Date',
  }) {
    final today = BusinessDate.todayInManila(instant: now);
    if (value.isAfter(today)) {
      throw PropertyRepositoryException(
        '$label cannot be in the future.',
        code: 'future-date',
      );
    }
    return value;
  }
}
