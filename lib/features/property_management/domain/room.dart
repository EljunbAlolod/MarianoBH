import 'package:flutter/foundation.dart';

enum RoomStatus { active, inactive }

@immutable
class Room {
  const Room({
    required this.roomId,
    required this.roomName,
    required this.description,
    required this.status,
    required this.defaultMonthlyRentCentavos,
    required this.activeOccupancyCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String roomId;
  final String roomName;
  final String description;
  final RoomStatus status;
  final int? defaultMonthlyRentCentavos;
  final int activeOccupancyCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status == RoomStatus.active;
}
