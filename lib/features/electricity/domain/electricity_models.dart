import '../../property_management/domain/boarder.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/domain/occupancy.dart';
import '../../property_management/domain/room.dart';

enum ElectricityMeterStatus { active, retired }

enum ElectricityMeterStartKind { initial, reset, replacement, correction }

enum MeterReadingKind { opening, regular, intermediate, closing }

enum ElectricityAdjustmentType { surcharge, discount }

enum ElectricityAllocationQuality { exact, estimated, unallocated }

class RoomMeterState {
  const RoomMeterState({
    required this.roomId,
    required this.currentMeterId,
    required this.lastTransitionId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String roomId;
  final String currentMeterId;
  final String? lastTransitionId;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// One uninterrupted, non-decreasing meter-reading sequence.
///
/// A reset, replacement, or correction retires the current sequence and
/// starts a new one so readings are never subtracted across discontinuities.
class ElectricityMeter {
  const ElectricityMeter({
    required this.meterId,
    required this.roomId,
    required this.sequence,
    required this.status,
    required this.startedOn,
    required this.endedOn,
    required this.startKind,
    required this.transitionReason,
    required this.previousMeterId,
    required this.replacementMeterId,
    required this.lastReadingId,
    required this.lastReadingDate,
    required this.lastReadingWh,
    required this.createdAt,
    required this.updatedAt,
  });

  final String meterId;
  final String roomId;
  final int sequence;
  final ElectricityMeterStatus status;
  final BusinessDate startedOn;
  final BusinessDate? endedOn;
  final ElectricityMeterStartKind startKind;
  final String? transitionReason;
  final String? previousMeterId;
  final String? replacementMeterId;
  final String lastReadingId;
  final BusinessDate lastReadingDate;
  final int lastReadingWh;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class MeterReading {
  MeterReading({
    required this.readingId,
    required this.meterId,
    required this.roomId,
    required this.sequence,
    required this.readingDate,
    required this.readingWh,
    required this.kind,
    required this.previousReadingId,
    required this.previousReadingDate,
    required this.previousReadingWh,
    required this.consumptionWh,
    required this.note,
    required this.createdAt,
    List<String> billingRecordIds = const [],
    this.lockTrackingComplete = true,
    this.correctionCount = 0,
    this.lastCorrectionId,
    this.lastCorrectedAt,
    this.lastCorrectedBy,
  }) : billingRecordIds = List.unmodifiable(billingRecordIds);

  final String readingId;
  final String meterId;
  final String roomId;
  final int sequence;
  final BusinessDate readingDate;
  final int readingWh;
  final MeterReadingKind kind;
  final String? previousReadingId;
  final BusinessDate? previousReadingDate;
  final int? previousReadingWh;
  final int consumptionWh;
  final String? note;
  final DateTime createdAt;
  final List<String> billingRecordIds;

  /// False only for legacy documents that have not completed the lock
  /// backfill. Those readings are conservatively treated as read-only.
  final bool lockTrackingComplete;
  final int correctionCount;
  final String? lastCorrectionId;
  final DateTime? lastCorrectedAt;
  final String? lastCorrectedBy;
}

enum MeterReadingCorrectionEligibility {
  eligible,
  migrationRequired,
  billed,
  newerReadingExists,
  inactiveSequence,
  unsupportedReading,
}

MeterReadingCorrectionEligibility meterReadingCorrectionEligibility({
  required MeterReading reading,
  required ElectricityMeter? activeMeter,
}) {
  if (!reading.lockTrackingComplete) {
    return MeterReadingCorrectionEligibility.migrationRequired;
  }
  if (reading.billingRecordIds.isNotEmpty) {
    return MeterReadingCorrectionEligibility.billed;
  }
  if (activeMeter == null ||
      activeMeter.status != ElectricityMeterStatus.active ||
      activeMeter.meterId != reading.meterId) {
    return MeterReadingCorrectionEligibility.inactiveSequence;
  }
  if (activeMeter.lastReadingId != reading.readingId) {
    return MeterReadingCorrectionEligibility.newerReadingExists;
  }
  final regularReading =
      reading.kind == MeterReadingKind.regular ||
      reading.kind == MeterReadingKind.intermediate;
  final initialBaseline =
      reading.kind == MeterReadingKind.opening &&
      reading.sequence == 1 &&
      activeMeter.startKind == ElectricityMeterStartKind.initial &&
      activeMeter.previousMeterId == null;
  return regularReading || initialBaseline
      ? MeterReadingCorrectionEligibility.eligible
      : MeterReadingCorrectionEligibility.unsupportedReading;
}

class MeterReadingCorrectionVersion {
  const MeterReadingCorrectionVersion({
    required this.readingDate,
    required this.readingWh,
    required this.consumptionWh,
    required this.meterStartedOn,
    required this.meterLastReadingDate,
    required this.meterLastReadingWh,
  });

  final BusinessDate readingDate;
  final int readingWh;
  final int consumptionWh;
  final BusinessDate meterStartedOn;
  final BusinessDate meterLastReadingDate;
  final int meterLastReadingWh;
}

class MeterReadingCorrection {
  const MeterReadingCorrection({
    required this.correctionId,
    required this.ownerId,
    required this.roomId,
    required this.meterId,
    required this.readingId,
    required this.sequence,
    required this.kind,
    required this.before,
    required this.after,
    required this.reason,
    required this.correctedBy,
    required this.createdAt,
  });

  final String correctionId;
  final String ownerId;
  final String roomId;
  final String meterId;
  final String readingId;
  final int sequence;
  final MeterReadingKind kind;
  final MeterReadingCorrectionVersion before;
  final MeterReadingCorrectionVersion after;
  final String reason;
  final String correctedBy;
  final DateTime createdAt;
}

class ElectricityAdjustment {
  const ElectricityAdjustment({
    required this.adjustmentId,
    required this.roomId,
    required this.type,
    required this.magnitudeCentavos,
    required this.reason,
    required this.adjustmentDate,
  });

  final String adjustmentId;
  final String roomId;
  final ElectricityAdjustmentType type;

  /// Positive magnitude. [type] determines whether it adds or subtracts.
  final int magnitudeCentavos;
  final String reason;
  final BusinessDate adjustmentDate;

  int get signedCentavos => switch (type) {
    ElectricityAdjustmentType.surcharge => magnitudeCentavos,
    ElectricityAdjustmentType.discount => -magnitudeCentavos,
  };
}

class BoarderElectricityShare {
  BoarderElectricityShare({
    required this.boarderId,
    required this.boarderName,
    required List<String> occupancyIds,
    required this.occupancyDays,
    required this.amountCentavos,
    required this.isEstimated,
  }) : occupancyIds = List.unmodifiable(occupancyIds);

  final String boarderId;
  final String boarderName;
  final List<String> occupancyIds;
  final int occupancyDays;
  final int amountCentavos;
  final bool isEstimated;
}

class ElectricitySegmentSnapshot {
  ElectricitySegmentSnapshot({
    required this.meterId,
    required this.sequence,
    required this.previousReadingId,
    required this.currentReadingId,
    required this.startDate,
    required this.endDateExclusive,
    required this.previousReadingWh,
    required this.currentReadingWh,
    required this.consumptionWh,
    required this.chargeCentavos,
    required List<BoarderElectricityShare> boarderShares,
    required this.unallocatedCentavos,
    required this.allocationQuality,
  }) : boarderShares = List.unmodifiable(boarderShares);

  final String meterId;
  final int sequence;
  final String previousReadingId;
  final String currentReadingId;
  final BusinessDate startDate;
  final BusinessDate endDateExclusive;
  final int previousReadingWh;
  final int currentReadingWh;
  final int consumptionWh;
  final int chargeCentavos;
  final List<BoarderElectricityShare> boarderShares;
  final int unallocatedCentavos;
  final ElectricityAllocationQuality allocationQuality;
}

class RoomElectricityCharge {
  RoomElectricityCharge({
    required this.roomId,
    required this.roomName,
    required List<ElectricitySegmentSnapshot> segments,
    required List<ElectricityAdjustment> adjustments,
    required List<BoarderElectricityShare> boarderShares,
    required this.consumptionWh,
    required this.baseChargeCentavos,
    required this.adjustmentCentavos,
    required this.finalChargeCentavos,
    required this.allocatedCentavos,
    required this.unallocatedCentavos,
    required this.hasEstimatedShares,
  }) : segments = List.unmodifiable(segments),
       adjustments = List.unmodifiable(adjustments),
       boarderShares = List.unmodifiable(boarderShares);

  final String roomId;
  final String roomName;
  final List<ElectricitySegmentSnapshot> segments;
  final List<ElectricityAdjustment> adjustments;
  final List<BoarderElectricityShare> boarderShares;
  final int consumptionWh;
  final int baseChargeCentavos;
  final int adjustmentCentavos;
  final int finalChargeCentavos;
  final int allocatedCentavos;
  final int unallocatedCentavos;
  final bool hasEstimatedShares;
}

class ElectricityCalculationInput {
  ElectricityCalculationInput({
    required this.startDate,
    required this.endDateExclusive,
    required this.rateMicropesosPerKwh,
    required List<Room> rooms,
    required List<ElectricityMeter> meters,
    required List<MeterReading> readings,
    required List<Occupancy> occupancies,
    required List<Boarder> boarders,
    List<ElectricityAdjustment> adjustments = const [],
  }) : rooms = List.unmodifiable(rooms),
       meters = List.unmodifiable(meters),
       readings = List.unmodifiable(readings),
       occupancies = List.unmodifiable(occupancies),
       boarders = List.unmodifiable(boarders),
       adjustments = List.unmodifiable(adjustments);

  final BusinessDate startDate;
  final BusinessDate endDateExclusive;
  final int rateMicropesosPerKwh;
  final List<Room> rooms;
  final List<ElectricityMeter> meters;
  final List<MeterReading> readings;
  final List<Occupancy> occupancies;
  final List<Boarder> boarders;
  final List<ElectricityAdjustment> adjustments;
}

class ElectricityCalculationResult {
  ElectricityCalculationResult({
    required this.startDate,
    required this.endDateExclusive,
    required this.rateMicropesosPerKwh,
    required List<RoomElectricityCharge> roomCharges,
    required this.totalConsumptionWh,
    required this.totalBaseChargeCentavos,
    required this.totalAdjustmentsCentavos,
    required this.totalChargeCentavos,
    required this.totalAllocatedCentavos,
    required this.totalUnallocatedCentavos,
    required List<String> warnings,
  }) : roomCharges = List.unmodifiable(roomCharges),
       warnings = List.unmodifiable(warnings);

  final BusinessDate startDate;
  final BusinessDate endDateExclusive;
  final int rateMicropesosPerKwh;
  final List<RoomElectricityCharge> roomCharges;
  final int totalConsumptionWh;
  final int totalBaseChargeCentavos;
  final int totalAdjustmentsCentavos;
  final int totalChargeCentavos;
  final int totalAllocatedCentavos;
  final int totalUnallocatedCentavos;
  final List<String> warnings;
}

/// Immutable historical copy of a completed electricity calculation.
class ElectricityBillingRecord {
  ElectricityBillingRecord({
    required this.billingRecordId,
    required this.startDate,
    required this.endDateExclusive,
    required this.rateMicropesosPerKwh,
    required List<RoomElectricityCharge> roomCharges,
    required this.totalConsumptionWh,
    required this.totalBaseChargeCentavos,
    required this.totalAdjustmentsCentavos,
    required this.totalChargeCentavos,
    required this.totalAllocatedCentavos,
    required this.totalUnallocatedCentavos,
    required List<String> warnings,
    required this.recordedAt,
    List<String> sourceReadingIds = const [],
    this.sourceLocksComplete = true,
  }) : roomCharges = List.unmodifiable(roomCharges),
       warnings = List.unmodifiable(warnings),
       sourceReadingIds = List.unmodifiable(sourceReadingIds);

  factory ElectricityBillingRecord.fromResult({
    required String billingRecordId,
    required ElectricityCalculationResult result,
    required DateTime recordedAt,
  }) {
    return ElectricityBillingRecord(
      billingRecordId: billingRecordId,
      startDate: result.startDate,
      endDateExclusive: result.endDateExclusive,
      rateMicropesosPerKwh: result.rateMicropesosPerKwh,
      roomCharges: result.roomCharges,
      totalConsumptionWh: result.totalConsumptionWh,
      totalBaseChargeCentavos: result.totalBaseChargeCentavos,
      totalAdjustmentsCentavos: result.totalAdjustmentsCentavos,
      totalChargeCentavos: result.totalChargeCentavos,
      totalAllocatedCentavos: result.totalAllocatedCentavos,
      totalUnallocatedCentavos: result.totalUnallocatedCentavos,
      warnings: result.warnings,
      recordedAt: recordedAt,
    );
  }

  final String billingRecordId;
  final BusinessDate startDate;
  final BusinessDate endDateExclusive;
  final int rateMicropesosPerKwh;
  final List<RoomElectricityCharge> roomCharges;
  final int totalConsumptionWh;
  final int totalBaseChargeCentavos;
  final int totalAdjustmentsCentavos;
  final int totalChargeCentavos;
  final int totalAllocatedCentavos;
  final int totalUnallocatedCentavos;
  final List<String> warnings;
  final DateTime recordedAt;
  final List<String> sourceReadingIds;

  /// False for a legacy record that has not completed the source-lock
  /// backfill. Legacy readings remain ineligible for correction.
  final bool sourceLocksComplete;
}
