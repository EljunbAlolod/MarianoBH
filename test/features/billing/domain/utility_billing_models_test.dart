import 'package:boarding_house_manager/features/billing/domain/utility_billing_models.dart';
import 'package:boarding_house_manager/features/billing/domain/monthly_billing_models.dart';
import 'package:boarding_house_manager/features/electricity/domain/electricity_batch_models.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/water/domain/water_batch_models.dart';
import 'package:boarding_house_manager/features/water/domain/water_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const assembler = UtilityBillingAssembler();

  test('combines independent periods into room-only utility bills', () {
    final result = assembler.assemble(
      issuedOn: BusinessDate(2026, 7, 5),
      electricity: _electricityBatch(),
      water: _waterBatch(),
      associationMismatchConfirmed: false,
    );

    expect(result.electricityMeasurementStart, BusinessDate(2026, 6, 10));
    expect(result.electricityMeasurementEnd, BusinessDate(2026, 7, 1));
    expect(result.waterPeriodStart, BusinessDate(2026, 5, 1));
    expect(result.waterPeriodEndExclusive, BusinessDate(2026, 6, 1));
    expect(result.statements.single.electricityCentavos, 120000);
    expect(result.statements.single.waterCentavos, 300000);
    expect(result.totalBilledCentavos, 420000);
    expect(result.sourceReadingIds, ['reading-1']);
  });

  test(
    'requires confirmation when water used another electricity reference',
    () {
      final water = _waterBatch(referenceElectricityId: 'electricity-other');
      expect(
        () => assembler.assemble(
          issuedOn: BusinessDate(2026, 7, 5),
          electricity: _electricityBatch(),
          water: water,
          associationMismatchConfirmed: false,
        ),
        throwsA(
          isA<UtilityBillingException>().having(
            (error) => error.code,
            'code',
            'association-mismatch-not-confirmed',
          ),
        ),
      );

      final result = assembler.assemble(
        issuedOn: BusinessDate(2026, 7, 5),
        electricity: _electricityBatch(),
        water: water,
        associationMismatchConfirmed: true,
      );
      expect(result.associationMismatchConfirmed, isTrue);
      expect(result.warnings.single, contains('EB-OTHER'));
    },
  );

  test('summarizes unpaid, partial, and paid room accounts', () {
    final now = DateTime.utc(2026, 7, 5);
    UtilityRoomBillAccount account(int paid) => UtilityRoomBillAccount(
      accountId: 'bill-room',
      billingBatchId: 'bill',
      roomId: 'room',
      roomName: 'Room 201',
      totalChargesCentavos: 100000,
      totalPaidCentavos: paid,
      createdAt: now,
      updatedAt: now,
    );

    expect(utilityBillingPaymentStatus([account(0)]), BillPaymentStatus.unpaid);
    expect(
      utilityBillingPaymentStatus([account(50000)]),
      BillPaymentStatus.partiallyPaid,
    );
    expect(
      utilityBillingPaymentStatus([account(100000)]),
      BillPaymentStatus.paid,
    );
  });
}

ElectricityReadingBatch _electricityBatch() {
  final now = DateTime.utc(2026, 7, 1);
  return ElectricityReadingBatch(
    batchId: 'electricity-july',
    batchReference: 'EB-2026-07-001',
    status: ElectricityReadingBatchStatus.finalized,
    effectiveDate: BusinessDate(2026, 7, 1),
    effectiveAt: now,
    rateMicropesosPerKwh: 10000000,
    entries: [
      ElectricityReadingBatchEntry(
        roomId: 'room-201',
        roomName: '201',
        meterId: 'meter-201',
        sequence: 1,
        previousReadingId: 'reading-0',
        previousReadingDate: BusinessDate(2026, 6, 10),
        previousReadingWh: 100000,
        targetReadingId: 'reading-1',
        status: ElectricityBatchEntryStatus.recorded,
        currentReadingWh: 112000,
        actualReadAt: now,
        readingId: 'reading-1',
        consumptionWh: 12000,
        chargeCentavos: 120000,
        exclusionReason: null,
      ),
    ],
    roomCount: 1,
    pendingCount: 0,
    recordedCount: 1,
    excludedCount: 0,
    totalConsumptionWh: 12000,
    totalChargeCentavos: 120000,
    version: 2,
    lastLinkId: 'reading-1',
    createdAt: now,
    updatedAt: now,
    finalizedAt: now,
    usedAt: null,
    voidReason: null,
    voidedAt: null,
  );
}

WaterBillingBatch _waterBatch({String? referenceElectricityId}) {
  final now = DateTime.utc(2026, 6, 5);
  final hasReference = referenceElectricityId != null;
  return WaterBillingBatch(
    batchId: 'water-may',
    batchReference: 'WB-2026-05-001',
    status: WaterBillingBatchStatus.finalized,
    startDate: BusinessDate(2026, 5, 1),
    endDateExclusive: BusinessDate(2026, 6, 1),
    receiptDate: BusinessDate(2026, 6, 5),
    waterBillCentavos: 300000,
    method: hasReference
        ? WaterBillingMethod.electricityPercentage
        : WaterBillingMethod.personDays,
    summerBasis: SummerElectricityBasis.roomElectricityCharge,
    electricityBatchId: referenceElectricityId,
    electricityBatchReference: hasReference ? 'EB-OTHER' : null,
    electricityMeasurementStart: hasReference ? BusinessDate(2026, 5, 1) : null,
    electricityMeasurementEnd: hasReference ? BusinessDate(2026, 6, 1) : null,
    referencePeriodMismatchConfirmed: false,
    referenceExplanation: null,
    notes: null,
    totalPersonDays: 31,
    totalElectricityBasis: hasReference ? 120000 : 0,
    totalAllocatedCentavos: 300000,
    totalUnallocatedCentavos: 0,
    roomAllocations: [
      WaterRoomAllocation(
        roomId: 'room-201',
        roomName: '201',
        electricityBasisValue: hasReference ? 120000 : 0,
        occupancyDays: 31,
        roomChargeCentavos: 300000,
        allocatedCentavos: 300000,
        unallocatedCentavos: 0,
        boarderShares: const [],
      ),
    ],
    boarderShares: const [],
    warnings: const [],
    version: 2,
    createdAt: now,
    updatedAt: now,
    finalizedAt: now,
    usedAt: null,
    voidReason: null,
    voidedAt: null,
  );
}
