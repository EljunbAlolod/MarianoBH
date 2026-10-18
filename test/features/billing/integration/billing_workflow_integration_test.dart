import 'dart:convert';

import 'package:boarding_house_manager/features/billing/domain/monthly_billing_models.dart';
import 'package:boarding_house_manager/features/billing/domain/utility_billing_models.dart';
import 'package:boarding_house_manager/features/electricity/domain/electricity_batch_models.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/rent/domain/rent_cycle_models.dart';
import 'package:boarding_house_manager/features/rent/domain/rent_cycle_service.dart';
import 'package:boarding_house_manager/features/reports/application/utility_billing_pdf_generator.dart';
import 'package:boarding_house_manager/features/water/domain/water_batch_models.dart';
import 'package:boarding_house_manager/features/water/domain/water_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const assembler = UtilityBillingAssembler();

  test('fixed rent and independent utility periods never merge charges', () {
    final agreement = _agreement();
    final rentCycle = const RentCycleService().monthlyCycle(agreement, 1);
    final result = assembler.assemble(
      issuedOn: BusinessDate(2026, 7, 12),
      electricity: _electricityBatch(),
      water: _waterBatch(),
      associationMismatchConfirmed: true,
    );

    expect(rentCycle.coverageStart, BusinessDate(2026, 6, 10));
    expect(rentCycle.coverageEndExclusive, BusinessDate(2026, 7, 10));
    expect(rentCycle.amountCentavos, 200000);
    expect(result.electricityMeasurementStart, BusinessDate(2026, 6, 10));
    expect(result.electricityMeasurementEnd, BusinessDate(2026, 7, 10));
    expect(result.waterPeriodStart, BusinessDate(2026, 5, 1));
    expect(result.waterPeriodEndExclusive, BusinessDate(2026, 6, 1));
    expect(result.electricityBatchReference, 'EB-2026-07-001');
    expect(result.waterBatchReference, 'WB-2026-05-001');
    expect(result.totalBilledCentavos, 30000);
    expect(result.statements.map((statement) => statement.totalCentavos), [
      20000,
      10000,
    ]);
    expect(
      result.statements.every(
        (statement) => statement.totalCentavos < rentCycle.amountCentavos,
      ),
      isTrue,
    );
    expect(result.associationMismatchConfirmed, isTrue);
  });

  test('non-finalized or already-used sources cannot create another bill', () {
    expect(
      () => assembler.assemble(
        issuedOn: BusinessDate(2026, 7, 12),
        electricity: _electricityBatch(
          status: ElectricityReadingBatchStatus.usedInBilling,
        ),
        water: _waterBatch(),
        associationMismatchConfirmed: true,
      ),
      _throwsUtilityCode('source-not-finalized'),
    );
    expect(
      () => assembler.assemble(
        issuedOn: BusinessDate(2026, 7, 12),
        electricity: _electricityBatch(entries: const []),
        water: _waterBatch(),
        associationMismatchConfirmed: true,
      ),
      _throwsUtilityCode('electricity-batch-has-no-readings'),
    );
  });

  test(
    'historical PDF uses the immutable bill snapshot and payment ledger',
    () async {
      final result = assembler.assemble(
        issuedOn: BusinessDate(2026, 7, 12),
        electricity: _electricityBatch(),
        water: _waterBatch(),
        associationMismatchConfirmed: true,
      );
      final snapshot = _snapshot(result);
      final accounts = snapshot.statements
          .map(
            (statement) => UtilityRoomBillAccount(
              accountId: '${snapshot.billingBatchId}_${statement.roomId}',
              billingBatchId: snapshot.billingBatchId,
              roomId: statement.roomId,
              roomName: statement.roomName,
              totalChargesCentavos: statement.totalCentavos,
              totalPaidCentavos: statement.roomId == 'room-201' ? 5000 : 0,
              createdAt: snapshot.createdAt,
              updatedAt: snapshot.createdAt,
            ),
          )
          .toList(growable: false);
      final payments = [
        UtilityRoomPaymentRecord(
          paymentId: 'payment-1',
          billingBatchId: snapshot.billingBatchId,
          accountId: '${snapshot.billingBatchId}_room-201',
          roomId: 'room-201',
          roomName: 'Room 201',
          amountCentavos: 5000,
          paymentDate: BusinessDate(2026, 7, 12),
          method: PaymentMethod.cash,
          notes: 'Partial payment',
          recordedAt: snapshot.createdAt,
        ),
      ];

      expect(
        () => snapshot.statements.add(
          const RoomUtilityBillStatement(
            roomId: 'forged',
            roomName: 'Forged',
            electricityCentavos: 1,
            waterCentavos: 0,
            adjustmentCentavos: 0,
            totalCentavos: 1,
          ),
        ),
        throwsUnsupportedError,
      );
      expect(
        utilityBillingPaymentStatus(accounts),
        BillPaymentStatus.partiallyPaid,
      );

      final bytes = await const UtilityBillingPdfGenerator().build(
        houseName: 'Mariano Boarding House',
        batch: snapshot,
        accounts: accounts,
        payments: payments,
        type: UtilityBillingPdfDocumentType.allRoomStatements,
      );

      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(1800));
      expect(snapshot.totalBilledCentavos, 30000);
      expect(snapshot.electricityTotalCentavos, 18000);
      expect(snapshot.waterTotalCentavos, 12000);
    },
  );
}

Matcher _throwsUtilityCode(String code) => throwsA(
  isA<UtilityBillingException>().having((error) => error.code, 'code', code),
);

RentAgreement _agreement() => RentAgreement(
  agreementId: 'occupancy-201',
  occupancyId: 'occupancy-201',
  boarderId: 'boarder-201',
  boarderName: 'Ana Cruz',
  roomId: 'room-201',
  roomName: 'Room 201',
  startDate: BusinessDate(2026, 6, 10),
  anchorDay: 10,
  monthlyRentCentavos: 200000,
  createdAt: DateTime.utc(2026, 6, 10),
);

ElectricityReadingBatch _electricityBatch({
  ElectricityReadingBatchStatus status =
      ElectricityReadingBatchStatus.finalized,
  List<ElectricityReadingBatchEntry>? entries,
}) {
  final recordedAt = DateTime.utc(2026, 7, 10, 2);
  final values =
      entries ??
      [
        _electricityEntry(
          roomId: 'room-201',
          roomName: 'Room 201',
          readingId: 'reading-201',
          previousWh: 100000,
          currentWh: 112000,
          chargeCentavos: 12000,
        ),
        _electricityEntry(
          roomId: 'room-202',
          roomName: 'Room 202',
          readingId: 'reading-202',
          previousWh: 200000,
          currentWh: 206000,
          chargeCentavos: 6000,
        ),
      ];
  return ElectricityReadingBatch(
    batchId: 'electricity-july',
    batchReference: 'EB-2026-07-001',
    status: status,
    effectiveDate: BusinessDate(2026, 7, 10),
    effectiveAt: recordedAt,
    rateMicropesosPerKwh: 10000000,
    entries: values,
    roomCount: values.length,
    pendingCount: 0,
    recordedCount: values.length,
    excludedCount: 0,
    totalConsumptionWh: values.fold(
      0,
      (sum, entry) => sum + entry.consumptionWh,
    ),
    totalChargeCentavos: values.fold(
      0,
      (sum, entry) => sum + entry.chargeCentavos,
    ),
    version: status == ElectricityReadingBatchStatus.usedInBilling ? 3 : 2,
    lastLinkId: values.isEmpty ? null : values.last.readingId,
    createdAt: DateTime.utc(2026, 6, 10),
    updatedAt: recordedAt,
    finalizedAt: recordedAt,
    usedAt: status == ElectricityReadingBatchStatus.usedInBilling
        ? DateTime.utc(2026, 7, 12)
        : null,
    voidReason: null,
    voidedAt: null,
  );
}

ElectricityReadingBatchEntry _electricityEntry({
  required String roomId,
  required String roomName,
  required String readingId,
  required int previousWh,
  required int currentWh,
  required int chargeCentavos,
}) => ElectricityReadingBatchEntry(
  roomId: roomId,
  roomName: roomName,
  meterId: 'meter-$roomId',
  sequence: 1,
  previousReadingId: 'previous-$roomId',
  previousReadingDate: BusinessDate(2026, 6, 10),
  previousReadingWh: previousWh,
  targetReadingId: readingId,
  status: ElectricityBatchEntryStatus.recorded,
  currentReadingWh: currentWh,
  actualReadAt: DateTime.utc(2026, 7, 10, 2),
  readingId: readingId,
  consumptionWh: currentWh - previousWh,
  chargeCentavos: chargeCentavos,
  exclusionReason: null,
);

WaterBillingBatch _waterBatch() {
  final recordedAt = DateTime.utc(2026, 6, 5);
  return WaterBillingBatch(
    batchId: 'water-may',
    batchReference: 'WB-2026-05-001',
    status: WaterBillingBatchStatus.finalized,
    startDate: BusinessDate(2026, 5, 1),
    endDateExclusive: BusinessDate(2026, 6, 1),
    receiptDate: BusinessDate(2026, 6, 5),
    waterBillCentavos: 12000,
    method: WaterBillingMethod.electricityPercentage,
    summerBasis: SummerElectricityBasis.roomElectricityCharge,
    electricityBatchId: 'electricity-june-reference',
    electricityBatchReference: 'EB-2026-06-REF',
    electricityMeasurementStart: BusinessDate(2026, 5, 10),
    electricityMeasurementEnd: BusinessDate(2026, 6, 10),
    referencePeriodMismatchConfirmed: true,
    referenceExplanation: 'Provider periods intentionally differ.',
    notes: null,
    totalPersonDays: 0,
    totalElectricityBasis: 18000,
    totalAllocatedCentavos: 12000,
    totalUnallocatedCentavos: 0,
    roomAllocations: [
      WaterRoomAllocation(
        roomId: 'room-201',
        roomName: 'Room 201',
        electricityBasisValue: 12000,
        occupancyDays: 0,
        roomChargeCentavos: 8000,
        allocatedCentavos: 8000,
        unallocatedCentavos: 0,
        boarderShares: [],
      ),
      WaterRoomAllocation(
        roomId: 'room-202',
        roomName: 'Room 202',
        electricityBasisValue: 6000,
        occupancyDays: 0,
        roomChargeCentavos: 4000,
        allocatedCentavos: 4000,
        unallocatedCentavos: 0,
        boarderShares: [],
      ),
    ],
    boarderShares: const [],
    warnings: const ['May water uses a June electricity reference.'],
    version: 2,
    createdAt: recordedAt,
    updatedAt: recordedAt,
    finalizedAt: recordedAt,
    usedAt: null,
    voidReason: null,
    voidedAt: null,
  );
}

UtilityBillingBatch _snapshot(UtilityBillingResult result) =>
    UtilityBillingBatch(
      billingBatchId: 'utility-july',
      billingBatchReference: 'UB-2026-07-001',
      status: UtilityBillingBatchStatus.finalized,
      issuedOn: result.issuedOn,
      electricityBatchId: result.electricityBatchId,
      electricityBatchReference: result.electricityBatchReference,
      electricityMeasurementStart: result.electricityMeasurementStart,
      electricityMeasurementEnd: result.electricityMeasurementEnd,
      electricityRateMicropesosPerKwh: result.electricityRateMicropesosPerKwh,
      sourceReadingIds: result.sourceReadingIds,
      waterBatchId: result.waterBatchId,
      waterBatchReference: result.waterBatchReference,
      waterPeriodStart: result.waterPeriodStart,
      waterPeriodEndExclusive: result.waterPeriodEndExclusive,
      waterReceiptDate: result.waterReceiptDate,
      waterMethod: result.waterMethod,
      waterSummerBasis: result.waterSummerBasis,
      waterReferenceElectricityBatchId: result.waterReferenceElectricityBatchId,
      waterReferenceElectricityBatchReference:
          result.waterReferenceElectricityBatchReference,
      associationMismatchConfirmed: result.associationMismatchConfirmed,
      electricityTotalCentavos: result.electricityTotalCentavos,
      waterTotalCentavos: result.waterTotalCentavos,
      adjustmentTotalCentavos: result.adjustmentTotalCentavos,
      totalBilledCentavos: result.totalBilledCentavos,
      totalUnallocatedCentavos: result.totalUnallocatedCentavos,
      statements: result.statements,
      warnings: result.warnings,
      createdAt: DateTime.utc(2026, 7, 12),
      voidReason: null,
      voidedAt: null,
    );
