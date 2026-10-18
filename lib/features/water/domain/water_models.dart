import '../../electricity/domain/electricity_models.dart';
import '../../property_management/domain/boarder.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/domain/occupancy.dart';
import '../../property_management/domain/room.dart';
import 'water_selection.dart';

enum WaterBillingMethod {
  personDays,
  roomDays,
  electricityPercentage,
  selectedBoarders,
}

enum SummerElectricityBasis { roomElectricityCharge, roomConsumption }

class WaterSettings {
  WaterSettings({
    required this.defaultMethod,
    required this.summerBasis,
    required List<int> summerMonths,
    required this.allowManualMethodOverride,
  }) : summerMonths = List.unmodifiable(summerMonths);

  factory WaterSettings.defaults() => WaterSettings(
    defaultMethod: WaterBillingMethod.selectedBoarders,
    summerBasis: SummerElectricityBasis.roomElectricityCharge,
    summerMonths: const [3, 4, 5],
    allowManualMethodOverride: true,
  );

  final WaterBillingMethod defaultMethod;
  final SummerElectricityBasis summerBasis;
  final List<int> summerMonths;
  final bool allowManualMethodOverride;

  bool isSummerMonth(BusinessDate date) => summerMonths.contains(date.month);

  WaterBillingMethod methodFor(BusinessDate date) {
    if (isSummerMonth(date)) {
      return WaterBillingMethod.electricityPercentage;
    }
    return defaultMethod;
  }
}

class RoomBoarderWaterShare {
  RoomBoarderWaterShare({
    required this.boarderId,
    required this.boarderName,
    required List<String> occupancyIds,
    required this.occupancyDays,
    required this.amountCentavos,
  }) : occupancyIds = List.unmodifiable(occupancyIds);

  final String boarderId;
  final String boarderName;
  final List<String> occupancyIds;
  final int occupancyDays;
  final int amountCentavos;
}

class BoarderWaterShare {
  BoarderWaterShare({
    required this.boarderId,
    required this.boarderName,
    required List<String> occupancyIds,
    required List<String> roomIds,
    required this.occupancyDays,
    required this.amountCentavos,
  }) : occupancyIds = List.unmodifiable(occupancyIds),
       roomIds = List.unmodifiable(roomIds);

  final String boarderId;
  final String boarderName;
  final List<String> occupancyIds;
  final List<String> roomIds;
  final int occupancyDays;
  final int amountCentavos;
}

class WaterRoomAllocation {
  WaterRoomAllocation({
    required this.roomId,
    required this.roomName,
    required this.electricityBasisValue,
    required this.occupancyDays,
    required this.roomChargeCentavos,
    required this.allocatedCentavos,
    required this.unallocatedCentavos,
    required List<RoomBoarderWaterShare> boarderShares,
  }) : boarderShares = List.unmodifiable(boarderShares);

  final String roomId;
  final String roomName;

  /// Base electricity centavos or Wh, depending on the selected summer basis.
  final int electricityBasisValue;
  final int occupancyDays;
  final int roomChargeCentavos;
  final int allocatedCentavos;
  final int unallocatedCentavos;
  final List<RoomBoarderWaterShare> boarderShares;
}

class WaterCalculationInput {
  WaterCalculationInput({
    required this.startDate,
    required this.endDateExclusive,
    required this.waterBillCentavos,
    required this.method,
    required this.summerBasis,
    required List<Room> rooms,
    required List<Boarder> boarders,
    required List<Occupancy> occupancies,
    this.electricityRecord,
    this.decisions = const [],
  }) : rooms = List.unmodifiable(rooms),
       boarders = List.unmodifiable(boarders),
       occupancies = List.unmodifiable(occupancies);

  final BusinessDate startDate;
  final BusinessDate endDateExclusive;
  final int waterBillCentavos;
  final WaterBillingMethod method;
  final SummerElectricityBasis summerBasis;
  final List<Room> rooms;
  final List<Boarder> boarders;
  final List<Occupancy> occupancies;
  final ElectricityBillingRecord? electricityRecord;
  final List<WaterBoarderDecision> decisions;
}

class WaterCalculationResult {
  WaterCalculationResult({
    required this.startDate,
    required this.endDateExclusive,
    required this.waterBillCentavos,
    required this.method,
    required this.summerBasis,
    required this.electricityRecordId,
    required this.totalPersonDays,
    required this.totalElectricityBasis,
    required this.totalAllocatedCentavos,
    required this.totalUnallocatedCentavos,
    required List<WaterRoomAllocation> roomAllocations,
    required List<BoarderWaterShare> boarderShares,
    required List<String> warnings,
    List<WaterBoarderDecision> decisions = const [],
  }) : roomAllocations = List.unmodifiable(roomAllocations),
       boarderShares = List.unmodifiable(boarderShares),
       warnings = List.unmodifiable(warnings),
       decisions = List.unmodifiable(decisions);

  final BusinessDate startDate;
  final BusinessDate endDateExclusive;
  final int waterBillCentavos;
  final WaterBillingMethod method;
  final SummerElectricityBasis summerBasis;
  final String? electricityRecordId;
  final int totalPersonDays;

  /// For [WaterBillingMethod.roomDays], this stores unique occupied room-days.
  /// The field name is retained for backward-compatible Firestore snapshots.
  int get totalAllocationDays => totalPersonDays;
  final int totalElectricityBasis;
  final int totalAllocatedCentavos;
  final int totalUnallocatedCentavos;
  final List<WaterRoomAllocation> roomAllocations;
  final List<BoarderWaterShare> boarderShares;
  final List<String> warnings;
  final List<WaterBoarderDecision> decisions;
  int get includedBoarderCount =>
      decisions.where((d) => d.inclusion == WaterInclusion.included).length;
}

class WaterBillingRecord extends WaterCalculationResult {
  WaterBillingRecord({
    required this.waterRecordId,
    required super.startDate,
    required super.endDateExclusive,
    required super.waterBillCentavos,
    required super.method,
    required super.summerBasis,
    required super.electricityRecordId,
    required super.totalPersonDays,
    required super.totalElectricityBasis,
    required super.totalAllocatedCentavos,
    required super.totalUnallocatedCentavos,
    required super.roomAllocations,
    required super.boarderShares,
    required super.warnings,
    required this.recordedAt,
  });

  factory WaterBillingRecord.fromResult({
    required String waterRecordId,
    required WaterCalculationResult result,
    required DateTime recordedAt,
  }) {
    return WaterBillingRecord(
      waterRecordId: waterRecordId,
      startDate: result.startDate,
      endDateExclusive: result.endDateExclusive,
      waterBillCentavos: result.waterBillCentavos,
      method: result.method,
      summerBasis: result.summerBasis,
      electricityRecordId: result.electricityRecordId,
      totalPersonDays: result.totalPersonDays,
      totalElectricityBasis: result.totalElectricityBasis,
      totalAllocatedCentavos: result.totalAllocatedCentavos,
      totalUnallocatedCentavos: result.totalUnallocatedCentavos,
      roomAllocations: result.roomAllocations,
      boarderShares: result.boarderShares,
      warnings: result.warnings,
      recordedAt: recordedAt,
    );
  }

  final String waterRecordId;
  final DateTime recordedAt;
}
