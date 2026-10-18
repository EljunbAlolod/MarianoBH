import '../../property_management/domain/boarder.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/domain/occupancy.dart';
import '../../property_management/domain/room.dart';

enum RentBillingMode { disabled, perBoarder, perRoom }

enum BillingAdjustmentType { charge, credit }

class RentSettings {
  const RentSettings({required this.mode});

  factory RentSettings.defaults() =>
      const RentSettings(mode: RentBillingMode.perBoarder);

  final RentBillingMode mode;
}

class BillingAdjustment {
  const BillingAdjustment({
    required this.adjustmentId,
    required this.boarderId,
    required this.type,
    required this.amountCentavos,
    required this.reason,
    required this.adjustmentDate,
  });

  final String adjustmentId;
  final String boarderId;
  final BillingAdjustmentType type;
  final int amountCentavos;
  final String reason;
  final BusinessDate adjustmentDate;

  int get signedCentavos => switch (type) {
    BillingAdjustmentType.charge => amountCentavos,
    BillingAdjustmentType.credit => -amountCentavos,
  };
}

class RoomBoarderRentShare {
  RoomBoarderRentShare({
    required this.boarderId,
    required this.boarderName,
    required List<String> occupancyIds,
    required this.occupancyDays,
    required this.rentCentavos,
  }) : occupancyIds = List.unmodifiable(occupancyIds);

  final String boarderId;
  final String boarderName;
  final List<String> occupancyIds;
  final int occupancyDays;
  final int rentCentavos;
}

class RoomRentAllocation {
  RoomRentAllocation({
    required this.roomId,
    required this.roomName,
    required this.monthlyRentCentavos,
    required this.occupiedDays,
    required this.personDays,
    required this.rentCentavos,
    required List<RoomBoarderRentShare> boarderShares,
  }) : boarderShares = List.unmodifiable(boarderShares);

  final String roomId;
  final String roomName;
  final int monthlyRentCentavos;
  final int occupiedDays;
  final int personDays;
  final int rentCentavos;
  final List<RoomBoarderRentShare> boarderShares;
}

class BoarderRentCharge {
  BoarderRentCharge({
    required this.boarderId,
    required this.boarderName,
    required List<String> occupancyIds,
    required List<String> roomIds,
    required this.occupancyDays,
    required this.rentCentavos,
    required this.adjustmentCentavos,
    required this.totalCentavos,
  }) : occupancyIds = List.unmodifiable(occupancyIds),
       roomIds = List.unmodifiable(roomIds);

  final String boarderId;
  final String boarderName;
  final List<String> occupancyIds;
  final List<String> roomIds;
  final int occupancyDays;
  final int rentCentavos;
  final int adjustmentCentavos;
  final int totalCentavos;
}

class RentCalculationInput {
  RentCalculationInput({
    required this.startDate,
    required this.endDateExclusive,
    required this.mode,
    required List<Room> rooms,
    required List<Boarder> boarders,
    required List<Occupancy> occupancies,
    List<BillingAdjustment> adjustments = const [],
  }) : rooms = List.unmodifiable(rooms),
       boarders = List.unmodifiable(boarders),
       occupancies = List.unmodifiable(occupancies),
       adjustments = List.unmodifiable(adjustments);

  final BusinessDate startDate;
  final BusinessDate endDateExclusive;
  final RentBillingMode mode;
  final List<Room> rooms;
  final List<Boarder> boarders;
  final List<Occupancy> occupancies;
  final List<BillingAdjustment> adjustments;
}

class RentCalculationResult {
  RentCalculationResult({
    required this.startDate,
    required this.endDateExclusive,
    required this.mode,
    required this.periodDays,
    required this.totalRentCentavos,
    required this.totalAdjustmentCentavos,
    required this.grandTotalCentavos,
    required List<RoomRentAllocation> roomAllocations,
    required List<BoarderRentCharge> boarderCharges,
    required List<BillingAdjustment> adjustments,
    required List<String> warnings,
  }) : roomAllocations = List.unmodifiable(roomAllocations),
       boarderCharges = List.unmodifiable(boarderCharges),
       adjustments = List.unmodifiable(adjustments),
       warnings = List.unmodifiable(warnings);

  final BusinessDate startDate;
  final BusinessDate endDateExclusive;
  final RentBillingMode mode;
  final int periodDays;
  final int totalRentCentavos;
  final int totalAdjustmentCentavos;
  final int grandTotalCentavos;
  final List<RoomRentAllocation> roomAllocations;
  final List<BoarderRentCharge> boarderCharges;
  final List<BillingAdjustment> adjustments;
  final List<String> warnings;
}

class RentBillingRecord extends RentCalculationResult {
  RentBillingRecord({
    required this.rentRecordId,
    required super.startDate,
    required super.endDateExclusive,
    required super.mode,
    required super.periodDays,
    required super.totalRentCentavos,
    required super.totalAdjustmentCentavos,
    required super.grandTotalCentavos,
    required super.roomAllocations,
    required super.boarderCharges,
    required super.adjustments,
    required super.warnings,
    required this.recordedAt,
  });

  factory RentBillingRecord.fromResult({
    required String rentRecordId,
    required RentCalculationResult result,
    required DateTime recordedAt,
  }) => RentBillingRecord(
    rentRecordId: rentRecordId,
    startDate: result.startDate,
    endDateExclusive: result.endDateExclusive,
    mode: result.mode,
    periodDays: result.periodDays,
    totalRentCentavos: result.totalRentCentavos,
    totalAdjustmentCentavos: result.totalAdjustmentCentavos,
    grandTotalCentavos: result.grandTotalCentavos,
    roomAllocations: result.roomAllocations,
    boarderCharges: result.boarderCharges,
    adjustments: result.adjustments,
    warnings: result.warnings,
    recordedAt: recordedAt,
  );

  final String rentRecordId;
  final DateTime recordedAt;
}
