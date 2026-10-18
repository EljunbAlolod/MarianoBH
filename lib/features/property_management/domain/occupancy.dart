import 'package:flutter/foundation.dart';

import 'business_date.dart';

/// A half-open room assignment: [moveInDate, moveOutDate).
///
/// The move-in date is billable. The move-out date is the first date that is
/// not billable for this room, allowing a same-date transfer without overlap.
@immutable
class Occupancy {
  const Occupancy({
    required this.occupancyId,
    required this.boarderId,
    required this.roomId,
    required this.moveInDate,
    required this.moveOutDate,
    required this.createdAt,
    required this.updatedAt,
  });

  final String occupancyId;
  final String boarderId;
  final String roomId;
  final BusinessDate moveInDate;
  final BusinessDate? moveOutDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCurrent => moveOutDate == null;

  bool contains(BusinessDate date) {
    return !date.isBefore(moveInDate) &&
        (moveOutDate == null || date.isBefore(moveOutDate!));
  }
}
