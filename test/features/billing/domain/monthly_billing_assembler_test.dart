import 'package:boarding_house_manager/features/billing/domain/monthly_billing_assembler.dart';
import 'package:boarding_house_manager/features/billing/domain/monthly_billing_models.dart';
import 'package:boarding_house_manager/features/electricity/domain/electricity_models.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/rent/domain/rent_models.dart';
import 'package:boarding_house_manager/features/water/domain/water_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const assembler = MonthlyBillingAssembler();

  test('combines finalized source shares into boarder statements', () {
    final result = assembler.assemble(
      electricity: _electricity(),
      water: _water(),
      rent: _rent(),
      previousBalancesByBoarder: const {'a': 2500},
    );

    expect(result.totalBilledCentavos, 271500);
    expect(result.totalUnallocatedCentavos, 1500);
    expect(result.statements, hasLength(2));
    expect(result.statements.first.boarderName, 'Ana');
    expect(result.statements.first.rentCentavos, 160000);
    expect(result.statements.first.rentAdjustmentCentavos, 1500);
    expect(result.statements.first.electricityCentavos, 60000);
    expect(result.statements.first.waterCentavos, 40000);
    expect(result.statements.first.currentChargesCentavos, 261500);
    expect(result.statements.first.previousBalanceCentavos, 2500);
    expect(result.statements.first.amountDueAtFinalizationCentavos, 264000);
    expect(result.statements.last.currentChargesCentavos, 10000);
  });

  test('rejects source records with different periods', () {
    expect(
      () => assembler.assemble(
        electricity: _electricity(),
        water: _water(end: _d(2026, 11, 2)),
        rent: _rent(),
      ),
      throwsA(
        isA<MonthlyBillingException>().having(
          (error) => error.code,
          'code',
          'source-period-mismatch',
        ),
      ),
    );
  });

  test('rejects source totals that do not reconcile with boarder shares', () {
    expect(
      () => assembler.assemble(
        electricity: _electricity(allocated: 60001),
        water: _water(),
        rent: _rent(),
      ),
      throwsA(
        isA<MonthlyBillingException>().having(
          (error) => error.code,
          'code',
          'source-totals-do-not-reconcile',
        ),
      ),
    );
  });

  test('dashboard excludes voided cycles and summarizes active accounts', () {
    final source = assembler.assemble(
      electricity: _electricity(),
      water: _water(),
      rent: _rent(),
    );
    MonthlyBillingCycle cycle(String id, int version) => MonthlyBillingCycle(
      billingCycleId: id,
      periodId: 'period',
      version: version,
      replacesCycleId: null,
      startDate: source.startDate,
      endDateExclusive: source.endDateExclusive,
      electricityRecordId: source.electricityRecordId,
      waterRecordId: source.waterRecordId,
      rentRecordId: source.rentRecordId,
      electricityTotalCentavos: source.electricityTotalCentavos,
      waterTotalCentavos: source.waterTotalCentavos,
      rentTotalCentavos: source.rentTotalCentavos,
      rentAdjustmentCentavos: source.rentAdjustmentCentavos,
      totalBilledCentavos: source.totalBilledCentavos,
      totalUnallocatedCentavos: source.totalUnallocatedCentavos,
      statements: source.statements,
      warnings: source.warnings,
      finalizedAt: DateTime.utc(2026),
    );
    BillingCycleControl control(String id, BillingCycleState state) =>
        BillingCycleControl(
          billingCycleId: id,
          state: state,
          totalBilledCentavos: 10000,
          totalPaidCentavos: state == BillingCycleState.active ? 4000 : 0,
          outstandingCentavos: state == BillingCycleState.active ? 6000 : 10000,
          voidReason: state == BillingCycleState.voided ? 'Correction' : null,
          voidedAt: null,
          reissuedAsCycleId: null,
          updatedAt: DateTime.utc(2026),
        );
    BoarderBillAccount account(String cycleId, int paid) => BoarderBillAccount(
      accountId: '$cycleId-a',
      billingCycleId: cycleId,
      boarderId: 'a',
      boarderName: 'Ana',
      totalChargesCentavos: 10000,
      previousBalanceCentavos: 0,
      totalPaidCentavos: paid,
      updatedAt: DateTime.utc(2026),
    );

    final summary = assembler.summarize(
      cycles: [cycle('active', 2), cycle('voided', 1)],
      controls: [
        control('active', BillingCycleState.active),
        control('voided', BillingCycleState.voided),
      ],
      accounts: [account('active', 4000), account('voided', 0)],
    );
    expect(summary.currentCycle?.billingCycleId, 'active');
    expect(summary.totalBilledCentavos, 10000);
    expect(summary.totalCollectedCentavos, 4000);
    expect(summary.totalOutstandingCentavos, 6000);
    expect(summary.unpaidBillCount, 1);
  });
}

BusinessDate _d(int year, int month, int day) => BusinessDate(year, month, day);

ElectricityBillingRecord _electricity({int allocated = 60000}) {
  final share = BoarderElectricityShare(
    boarderId: 'a',
    boarderName: 'Ana',
    occupancyIds: const ['oa'],
    occupancyDays: 16,
    amountCentavos: 60000,
    isEstimated: true,
  );
  return ElectricityBillingRecord(
    billingRecordId: 'electricity',
    startDate: _d(2026, 10, 1),
    endDateExclusive: _d(2026, 11, 1),
    rateMicropesosPerKwh: 12000000,
    roomCharges: [
      RoomElectricityCharge(
        roomId: 'room-a',
        roomName: 'Room A',
        segments: const [],
        adjustments: const [],
        boarderShares: [share],
        consumptionWh: 51250,
        baseChargeCentavos: 61500,
        adjustmentCentavos: 0,
        finalChargeCentavos: 61500,
        allocatedCentavos: allocated,
        unallocatedCentavos: 1500,
        hasEstimatedShares: true,
      ),
    ],
    totalConsumptionWh: 51250,
    totalBaseChargeCentavos: 61500,
    totalAdjustmentsCentavos: 0,
    totalChargeCentavos: 61500,
    totalAllocatedCentavos: allocated,
    totalUnallocatedCentavos: 1500,
    warnings: const ['One share is estimated.'],
    recordedAt: DateTime.utc(2026, 11, 1),
  );
}

WaterBillingRecord _water({BusinessDate? end}) => WaterBillingRecord(
  waterRecordId: 'water',
  startDate: _d(2026, 10, 1),
  endDateExclusive: end ?? _d(2026, 11, 1),
  waterBillCentavos: 50000,
  method: WaterBillingMethod.personDays,
  summerBasis: SummerElectricityBasis.roomElectricityCharge,
  electricityRecordId: null,
  totalPersonDays: 31,
  totalElectricityBasis: 0,
  totalAllocatedCentavos: 50000,
  totalUnallocatedCentavos: 0,
  roomAllocations: const [],
  boarderShares: [
    BoarderWaterShare(
      boarderId: 'a',
      boarderName: 'Ana',
      occupancyIds: const ['oa'],
      roomIds: const ['room-a'],
      occupancyDays: 16,
      amountCentavos: 40000,
    ),
    BoarderWaterShare(
      boarderId: 'b',
      boarderName: 'Ben',
      occupancyIds: const ['ob'],
      roomIds: const ['room-b'],
      occupancyDays: 15,
      amountCentavos: 10000,
    ),
  ],
  warnings: const [],
  recordedAt: DateTime.utc(2026, 11, 1),
);

RentBillingRecord _rent() => RentBillingRecord(
  rentRecordId: 'rent',
  startDate: _d(2026, 10, 1),
  endDateExclusive: _d(2026, 11, 1),
  mode: RentBillingMode.perBoarder,
  periodDays: 31,
  totalRentCentavos: 160000,
  totalAdjustmentCentavos: 1500,
  grandTotalCentavos: 161500,
  roomAllocations: const [],
  boarderCharges: [
    BoarderRentCharge(
      boarderId: 'a',
      boarderName: 'Ana',
      occupancyIds: const ['oa'],
      roomIds: const ['room-a'],
      occupancyDays: 16,
      rentCentavos: 160000,
      adjustmentCentavos: 1500,
      totalCentavos: 161500,
    ),
  ],
  adjustments: const [],
  warnings: const [],
  recordedAt: DateTime.utc(2026, 11, 1),
);
