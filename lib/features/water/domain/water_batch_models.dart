import '../../electricity/domain/electricity_batch_models.dart';
import '../../electricity/domain/electricity_models.dart';
import '../../property_management/domain/business_date.dart';
import 'water_models.dart';

enum WaterBillingBatchStatus { draft, finalized, usedInBilling, voided }

class WaterBillingBatch extends WaterCalculationResult {
  WaterBillingBatch({
    required this.batchId,
    required this.batchReference,
    required this.status,
    required super.startDate,
    required super.endDateExclusive,
    required this.receiptDate,
    required super.waterBillCentavos,
    required super.method,
    required super.summerBasis,
    required this.electricityBatchId,
    required this.electricityBatchReference,
    required this.electricityMeasurementStart,
    required this.electricityMeasurementEnd,
    required this.referencePeriodMismatchConfirmed,
    required this.referenceExplanation,
    required this.notes,
    required super.totalPersonDays,
    required super.totalElectricityBasis,
    required super.totalAllocatedCentavos,
    required super.totalUnallocatedCentavos,
    required super.roomAllocations,
    required super.boarderShares,
    required super.warnings,
    super.decisions,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.finalizedAt,
    required this.usedAt,
    required this.voidReason,
    required this.voidedAt,
  }) : super(
         electricityRecordId: method == WaterBillingMethod.electricityPercentage
             ? electricityBatchId
             : null,
       );

  final String batchId;
  final String batchReference;
  final WaterBillingBatchStatus status;
  final BusinessDate receiptDate;
  final String? electricityBatchId;
  final String? electricityBatchReference;
  final BusinessDate? electricityMeasurementStart;
  final BusinessDate? electricityMeasurementEnd;
  final bool referencePeriodMismatchConfirmed;
  final String? referenceExplanation;
  final String? notes;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? finalizedAt;
  final DateTime? usedAt;
  final String? voidReason;
  final DateTime? voidedAt;

  bool get canEdit => status == WaterBillingBatchStatus.draft;
  bool get canVoid => status == WaterBillingBatchStatus.finalized;
}

BusinessDate electricityBatchMeasurementStart(ElectricityReadingBatch batch) {
  final included = batch.entries.where(
    (entry) => entry.status == ElectricityBatchEntryStatus.recorded,
  );
  if (included.isEmpty) return batch.effectiveDate;
  return included
      .map((entry) => entry.previousReadingDate)
      .reduce((a, b) => a.isBefore(b) ? a : b);
}

bool waterAndElectricityPeriodsDiffer({
  required BusinessDate waterStart,
  required BusinessDate waterEndExclusive,
  required ElectricityReadingBatch electricityBatch,
}) {
  return waterStart != electricityBatchMeasurementStart(electricityBatch) ||
      waterEndExclusive != electricityBatch.effectiveDate;
}

/// Adapts an immutable reading batch to the legacy calculator's room-basis
/// input. The water dates are deliberately used only to satisfy the legacy
/// calculator boundary contract; the original electricity interval remains
/// stored separately on [WaterBillingBatch].
ElectricityBillingRecord electricityAllocationRecordFromBatch({
  required ElectricityReadingBatch batch,
  required BusinessDate waterStart,
  required BusinessDate waterEndExclusive,
}) {
  final entries = batch.entries
      .where((entry) => entry.status == ElectricityBatchEntryStatus.recorded)
      .toList();
  final charges = entries
      .map(
        (entry) => RoomElectricityCharge(
          roomId: entry.roomId,
          roomName: entry.roomName,
          segments: const [],
          adjustments: const [],
          boarderShares: const [],
          consumptionWh: entry.consumptionWh,
          baseChargeCentavos: entry.chargeCentavos,
          adjustmentCentavos: 0,
          finalChargeCentavos: entry.chargeCentavos,
          allocatedCentavos: entry.chargeCentavos,
          unallocatedCentavos: 0,
          hasEstimatedShares: false,
        ),
      )
      .toList();
  return ElectricityBillingRecord(
    billingRecordId: batch.batchId,
    startDate: waterStart,
    endDateExclusive: waterEndExclusive,
    rateMicropesosPerKwh: batch.rateMicropesosPerKwh,
    roomCharges: charges,
    totalConsumptionWh: entries.fold(
      0,
      (sum, entry) => sum + entry.consumptionWh,
    ),
    totalBaseChargeCentavos: entries.fold(
      0,
      (sum, entry) => sum + entry.chargeCentavos,
    ),
    totalAdjustmentsCentavos: 0,
    totalChargeCentavos: entries.fold(
      0,
      (sum, entry) => sum + entry.chargeCentavos,
    ),
    totalAllocatedCentavos: entries.fold(
      0,
      (sum, entry) => sum + entry.chargeCentavos,
    ),
    totalUnallocatedCentavos: 0,
    warnings: const [],
    recordedAt: batch.finalizedAt ?? batch.updatedAt,
    sourceReadingIds: entries
        .map((entry) => entry.readingId)
        .whereType<String>()
        .toList(),
  );
}
