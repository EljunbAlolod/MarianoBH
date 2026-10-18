import '../../electricity/domain/electricity_batch_models.dart';
import '../../property_management/domain/business_date.dart';
import '../../water/domain/water_batch_models.dart';
import '../../water/domain/water_models.dart';
import 'monthly_billing_models.dart';

enum UtilityBillingBatchStatus { finalized, voided }

class RoomUtilityBillStatement {
  const RoomUtilityBillStatement({
    required this.roomId,
    required this.roomName,
    required this.electricityCentavos,
    required this.waterCentavos,
    required this.adjustmentCentavos,
    required this.totalCentavos,
  });

  final String roomId;
  final String roomName;
  final int electricityCentavos;
  final int waterCentavos;
  final int adjustmentCentavos;
  final int totalCentavos;
}

class UtilityBillingResult {
  UtilityBillingResult({
    required this.issuedOn,
    required this.electricityBatchId,
    required this.electricityBatchReference,
    required this.electricityMeasurementStart,
    required this.electricityMeasurementEnd,
    required this.electricityRateMicropesosPerKwh,
    required List<String> sourceReadingIds,
    required this.waterBatchId,
    required this.waterBatchReference,
    required this.waterPeriodStart,
    required this.waterPeriodEndExclusive,
    required this.waterReceiptDate,
    required this.waterMethod,
    required this.waterSummerBasis,
    required this.waterReferenceElectricityBatchId,
    required this.waterReferenceElectricityBatchReference,
    required this.associationMismatchConfirmed,
    required this.electricityTotalCentavos,
    required this.waterTotalCentavos,
    required this.adjustmentTotalCentavos,
    required this.totalBilledCentavos,
    required this.totalUnallocatedCentavos,
    required List<RoomUtilityBillStatement> statements,
    required List<String> warnings,
  }) : sourceReadingIds = List.unmodifiable(sourceReadingIds),
       statements = List.unmodifiable(statements),
       warnings = List.unmodifiable(warnings);

  final BusinessDate issuedOn;
  final String electricityBatchId;
  final String electricityBatchReference;
  final BusinessDate electricityMeasurementStart;
  final BusinessDate electricityMeasurementEnd;
  final int electricityRateMicropesosPerKwh;
  final List<String> sourceReadingIds;
  final String waterBatchId;
  final String waterBatchReference;
  final BusinessDate waterPeriodStart;
  final BusinessDate waterPeriodEndExclusive;
  final BusinessDate waterReceiptDate;
  final WaterBillingMethod waterMethod;
  final SummerElectricityBasis waterSummerBasis;
  final String? waterReferenceElectricityBatchId;
  final String? waterReferenceElectricityBatchReference;
  final bool associationMismatchConfirmed;
  final int electricityTotalCentavos;
  final int waterTotalCentavos;
  final int adjustmentTotalCentavos;
  final int totalBilledCentavos;
  final int totalUnallocatedCentavos;
  final List<RoomUtilityBillStatement> statements;
  final List<String> warnings;

  bool get hasDifferentWaterReference =>
      waterReferenceElectricityBatchId != null &&
      waterReferenceElectricityBatchId != electricityBatchId;
}

class UtilityBillingBatch extends UtilityBillingResult {
  UtilityBillingBatch({
    required this.billingBatchId,
    required this.billingBatchReference,
    required this.status,
    required super.issuedOn,
    required super.electricityBatchId,
    required super.electricityBatchReference,
    required super.electricityMeasurementStart,
    required super.electricityMeasurementEnd,
    required super.electricityRateMicropesosPerKwh,
    required super.sourceReadingIds,
    required super.waterBatchId,
    required super.waterBatchReference,
    required super.waterPeriodStart,
    required super.waterPeriodEndExclusive,
    required super.waterReceiptDate,
    required super.waterMethod,
    required super.waterSummerBasis,
    required super.waterReferenceElectricityBatchId,
    required super.waterReferenceElectricityBatchReference,
    required super.associationMismatchConfirmed,
    required super.electricityTotalCentavos,
    required super.waterTotalCentavos,
    required super.adjustmentTotalCentavos,
    required super.totalBilledCentavos,
    required super.totalUnallocatedCentavos,
    required super.statements,
    required super.warnings,
    required this.createdAt,
    required this.voidReason,
    required this.voidedAt,
  });

  final String billingBatchId;
  final String billingBatchReference;
  final UtilityBillingBatchStatus status;
  final DateTime createdAt;
  final String? voidReason;
  final DateTime? voidedAt;
}

class UtilityRoomBillAccount {
  const UtilityRoomBillAccount({
    required this.accountId,
    required this.billingBatchId,
    required this.roomId,
    required this.roomName,
    required this.totalChargesCentavos,
    required this.totalPaidCentavos,
    required this.createdAt,
    required this.updatedAt,
  });

  final String accountId;
  final String billingBatchId;
  final String roomId;
  final String roomName;
  final int totalChargesCentavos;
  final int totalPaidCentavos;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get outstandingCentavos => totalChargesCentavos - totalPaidCentavos;

  BillPaymentStatus get status => paymentStatusFor(
    totalPaidCentavos: totalPaidCentavos,
    totalChargesCentavos: totalChargesCentavos,
  );
}

class UtilityRoomPaymentRecord {
  const UtilityRoomPaymentRecord({
    required this.paymentId,
    required this.billingBatchId,
    required this.accountId,
    required this.roomId,
    required this.roomName,
    required this.amountCentavos,
    required this.paymentDate,
    required this.method,
    required this.notes,
    required this.recordedAt,
  });

  final String paymentId;
  final String billingBatchId;
  final String accountId;
  final String roomId;
  final String roomName;
  final int amountCentavos;
  final BusinessDate paymentDate;
  final PaymentMethod method;
  final String? notes;
  final DateTime recordedAt;
}

BillPaymentStatus utilityBillingPaymentStatus(
  Iterable<UtilityRoomBillAccount> accounts,
) {
  final values = accounts.toList(growable: false);
  if (values.isNotEmpty &&
      values.every((account) => account.status == BillPaymentStatus.paid)) {
    return BillPaymentStatus.paid;
  }
  if (values.any((account) => account.totalPaidCentavos > 0)) {
    return BillPaymentStatus.partiallyPaid;
  }
  return BillPaymentStatus.unpaid;
}

class UtilityBillingAssembler {
  const UtilityBillingAssembler();

  UtilityBillingResult assemble({
    required BusinessDate issuedOn,
    required ElectricityReadingBatch electricity,
    required WaterBillingBatch water,
    required bool associationMismatchConfirmed,
  }) {
    if (electricity.status != ElectricityReadingBatchStatus.finalized ||
        water.status != WaterBillingBatchStatus.finalized) {
      throw const UtilityBillingException(
        'Select finalized, unused electricity and water batches.',
        code: 'source-not-finalized',
      );
    }
    final differentReference =
        water.electricityBatchId != null &&
        water.electricityBatchId != electricity.batchId;
    if (differentReference && !associationMismatchConfirmed) {
      throw const UtilityBillingException(
        'Confirm that the selected electricity batch intentionally differs from the water allocation reference.',
        code: 'association-mismatch-not-confirmed',
      );
    }

    final electricityEntries = electricity.entries
        .where((entry) => entry.status == ElectricityBatchEntryStatus.recorded)
        .toList();
    if (electricityEntries.isEmpty) {
      throw const UtilityBillingException(
        'The electricity batch has no recorded room readings to bill.',
        code: 'electricity-batch-has-no-readings',
      );
    }
    final electricityByRoom = {
      for (final entry in electricityEntries) entry.roomId: entry,
    };
    final waterByRoom = {
      for (final allocation in water.roomAllocations)
        allocation.roomId: allocation,
    };
    final roomIds = {...electricityByRoom.keys, ...waterByRoom.keys}.toList();
    final statements = <RoomUtilityBillStatement>[];
    for (final roomId in roomIds) {
      final electricityEntry = electricityByRoom[roomId];
      final waterAllocation = waterByRoom[roomId];
      final electricityCentavos = electricityEntry?.chargeCentavos ?? 0;
      final waterCentavos = waterAllocation?.allocatedCentavos ?? 0;
      final total = electricityCentavos + waterCentavos;
      if (total == 0) continue;
      statements.add(
        RoomUtilityBillStatement(
          roomId: roomId,
          roomName:
              electricityEntry?.roomName ?? waterAllocation?.roomName ?? 'Room',
          electricityCentavos: electricityCentavos,
          waterCentavos: waterCentavos,
          adjustmentCentavos: 0,
          totalCentavos: total,
        ),
      );
    }
    statements.sort((a, b) {
      final byName = a.roomName.toLowerCase().compareTo(
        b.roomName.toLowerCase(),
      );
      return byName != 0 ? byName : a.roomId.compareTo(b.roomId);
    });
    if (statements.isEmpty) {
      throw const UtilityBillingException(
        'The selected batches do not contain any room charges.',
        code: 'no-room-charges',
      );
    }
    final electricityTotal = statements.fold<int>(
      0,
      (sum, item) => sum + item.electricityCentavos,
    );
    final waterTotal = statements.fold<int>(
      0,
      (sum, item) => sum + item.waterCentavos,
    );
    if (electricityTotal != electricity.totalChargeCentavos ||
        waterTotal != water.totalAllocatedCentavos) {
      throw const UtilityBillingException(
        'The selected source totals do not reconcile with the room charges.',
        code: 'source-totals-do-not-reconcile',
      );
    }
    final warnings = <String>[...water.warnings];
    if (differentReference) {
      warnings.add(
        'The water allocation used ${water.electricityBatchReference}; this bill charges electricity from ${electricity.batchReference}.',
      );
    }
    if (water.totalUnallocatedCentavos > 0) {
      warnings.add(
        'Unallocated water remains landlady-paid and is not charged to a room.',
      );
    }
    return UtilityBillingResult(
      issuedOn: issuedOn,
      electricityBatchId: electricity.batchId,
      electricityBatchReference: electricity.batchReference,
      electricityMeasurementStart: electricityBatchMeasurementStart(
        electricity,
      ),
      electricityMeasurementEnd: electricity.effectiveDate,
      electricityRateMicropesosPerKwh: electricity.rateMicropesosPerKwh,
      sourceReadingIds: electricityEntries
          .map((entry) => entry.readingId)
          .whereType<String>()
          .toList(),
      waterBatchId: water.batchId,
      waterBatchReference: water.batchReference,
      waterPeriodStart: water.startDate,
      waterPeriodEndExclusive: water.endDateExclusive,
      waterReceiptDate: water.receiptDate,
      waterMethod: water.method,
      waterSummerBasis: water.summerBasis,
      waterReferenceElectricityBatchId: water.electricityBatchId,
      waterReferenceElectricityBatchReference: water.electricityBatchReference,
      associationMismatchConfirmed:
          differentReference && associationMismatchConfirmed,
      electricityTotalCentavos: electricityTotal,
      waterTotalCentavos: waterTotal,
      adjustmentTotalCentavos: 0,
      totalBilledCentavos: electricityTotal + waterTotal,
      totalUnallocatedCentavos: water.totalUnallocatedCentavos,
      statements: statements,
      warnings: warnings,
    );
  }
}

class UtilityBillingException implements Exception {
  const UtilityBillingException(this.message, {required this.code});

  final String message;
  final String code;

  @override
  String toString() => 'UtilityBillingException($code): $message';
}
