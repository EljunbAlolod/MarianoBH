import 'package:flutter/foundation.dart';

import 'business_date.dart';

enum BoarderStatus { active, movedOut, inactive }

@immutable
class Boarder {
  const Boarder({
    required this.boarderId,
    required this.fullName,
    required this.contact,
    required this.notes,
    required this.status,
    required this.currentOccupancyId,
    required this.currentRoomId,
    required this.currentMoveInDate,
    required this.lastMoveOutDate,
    required this.createdAt,
    required this.updatedAt,
  });

  final String boarderId;
  final String fullName;
  final String? contact;
  final String? notes;
  final BoarderStatus status;
  final String? currentOccupancyId;
  final String? currentRoomId;
  final BusinessDate? currentMoveInDate;
  final BusinessDate? lastMoveOutDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasCurrentOccupancy =>
      currentOccupancyId != null && currentRoomId != null;
}
