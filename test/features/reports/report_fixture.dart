import 'package:boarding_house_manager/features/billing/domain/monthly_billing_models.dart';
import 'package:boarding_house_manager/features/electricity/domain/electricity_models.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/rent/domain/rent_models.dart';
import 'package:boarding_house_manager/features/reports/domain/billing_report_assembler.dart';
import 'package:boarding_house_manager/features/reports/domain/billing_report_models.dart';
import 'package:boarding_house_manager/features/water/domain/water_models.dart';

BillingReportSnapshot reportFixture({int electricityTotal = 90000}) {
  final start = BusinessDate(2026, 10, 1);
  final end = BusinessDate(2026, 11, 1);
  final recordedAt = DateTime.utc(2026, 11, 1);
  BoarderElectricityShare electricityShare(
    String id,
    String name,
    int amount,
  ) => BoarderElectricityShare(
    boarderId: id,
    boarderName: name,
    occupancyIds: ['occupancy-$id'],
    occupancyDays: id == 'boarder-a' ? 16 : 31,
    amountCentavos: amount,
    isEstimated: id == 'boarder-a',
  );
  RoomElectricityCharge electricityRoom(
    String id,
    String name,
    int amount,
    BoarderElectricityShare share,
  ) => RoomElectricityCharge(
    roomId: id,
    roomName: name,
    segments: const [],
    adjustments: const [],
    boarderShares: [share],
    consumptionWh: amount == 60000 ? 5000 : 2500,
    baseChargeCentavos: amount,
    adjustmentCentavos: 0,
    finalChargeCentavos: amount,
    allocatedCentavos: amount,
    unallocatedCentavos: 0,
    hasEstimatedShares: share.isEstimated,
  );
  final electricity = ElectricityBillingRecord(
    billingRecordId: 'electricity-1',
    startDate: start,
    endDateExclusive: end,
    rateMicropesosPerKwh: 12000000,
    roomCharges: [
      electricityRoom(
        'room-a',
        'Room A',
        60000,
        electricityShare('boarder-a', 'Ana Cruz', 60000),
      ),
      electricityRoom(
        'room-b',
        'Room B',
        30000,
        electricityShare('boarder-b', 'Ben Lim', 30000),
      ),
    ],
    totalConsumptionWh: 7500,
    totalBaseChargeCentavos: 90000,
    totalAdjustmentsCentavos: 0,
    totalChargeCentavos: 90000,
    totalAllocatedCentavos: electricityTotal,
    totalUnallocatedCentavos: 0,
    warnings: const ['Room A electricity is estimated.'],
    recordedAt: recordedAt,
  );
  RoomBoarderWaterShare roomWaterShare(
    String id,
    String name,
    int days,
    int amount,
  ) => RoomBoarderWaterShare(
    boarderId: id,
    boarderName: name,
    occupancyIds: ['occupancy-$id'],
    occupancyDays: days,
    amountCentavos: amount,
  );
  WaterRoomAllocation waterRoom(
    String roomId,
    String roomName,
    int basis,
    int days,
    int amount,
    RoomBoarderWaterShare share,
  ) => WaterRoomAllocation(
    roomId: roomId,
    roomName: roomName,
    electricityBasisValue: basis,
    occupancyDays: days,
    roomChargeCentavos: amount,
    allocatedCentavos: amount,
    unallocatedCentavos: 0,
    boarderShares: [share],
  );
  final water = WaterBillingRecord(
    waterRecordId: 'water-1',
    startDate: start,
    endDateExclusive: end,
    waterBillCentavos: 60000,
    method: WaterBillingMethod.electricityPercentage,
    summerBasis: SummerElectricityBasis.roomElectricityCharge,
    electricityRecordId: electricity.billingRecordId,
    totalPersonDays: 47,
    totalElectricityBasis: 90000,
    totalAllocatedCentavos: 60000,
    totalUnallocatedCentavos: 0,
    roomAllocations: [
      waterRoom(
        'room-a',
        'Room A',
        60000,
        16,
        40000,
        roomWaterShare('boarder-a', 'Ana Cruz', 16, 40000),
      ),
      waterRoom(
        'room-b',
        'Room B',
        30000,
        31,
        20000,
        roomWaterShare('boarder-b', 'Ben Lim', 31, 20000),
      ),
    ],
    boarderShares: [
      BoarderWaterShare(
        boarderId: 'boarder-a',
        boarderName: 'Ana Cruz',
        occupancyIds: const ['occupancy-boarder-a'],
        roomIds: const ['room-a'],
        occupancyDays: 16,
        amountCentavos: 40000,
      ),
      BoarderWaterShare(
        boarderId: 'boarder-b',
        boarderName: 'Ben Lim',
        occupancyIds: const ['occupancy-boarder-b'],
        roomIds: const ['room-b'],
        occupancyDays: 31,
        amountCentavos: 20000,
      ),
    ],
    warnings: const [],
    recordedAt: recordedAt,
  );
  RoomBoarderRentShare rentShare(
    String id,
    String name,
    int days,
    int amount,
  ) => RoomBoarderRentShare(
    boarderId: id,
    boarderName: name,
    occupancyIds: ['occupancy-$id'],
    occupancyDays: days,
    rentCentavos: amount,
  );
  RoomRentAllocation rentRoom(
    String roomId,
    String roomName,
    int days,
    int amount,
    RoomBoarderRentShare share,
  ) => RoomRentAllocation(
    roomId: roomId,
    roomName: roomName,
    monthlyRentCentavos: amount,
    occupiedDays: days,
    personDays: days,
    rentCentavos: amount,
    boarderShares: [share],
  );
  final rent = RentBillingRecord(
    rentRecordId: 'rent-1',
    startDate: start,
    endDateExclusive: end,
    mode: RentBillingMode.perBoarder,
    periodDays: 31,
    totalRentCentavos: 260000,
    totalAdjustmentCentavos: 1500,
    grandTotalCentavos: 261500,
    roomAllocations: [
      rentRoom(
        'room-a',
        'Room A',
        16,
        160000,
        rentShare('boarder-a', 'Ana Cruz', 16, 160000),
      ),
      rentRoom(
        'room-b',
        'Room B',
        31,
        100000,
        rentShare('boarder-b', 'Ben Lim', 31, 100000),
      ),
    ],
    boarderCharges: [
      BoarderRentCharge(
        boarderId: 'boarder-a',
        boarderName: 'Ana Cruz',
        occupancyIds: const ['occupancy-boarder-a'],
        roomIds: const ['room-a'],
        occupancyDays: 16,
        rentCentavos: 160000,
        adjustmentCentavos: 1500,
        totalCentavos: 161500,
      ),
      BoarderRentCharge(
        boarderId: 'boarder-b',
        boarderName: 'Ben Lim',
        occupancyIds: const ['occupancy-boarder-b'],
        roomIds: const ['room-b'],
        occupancyDays: 31,
        rentCentavos: 100000,
        adjustmentCentavos: 0,
        totalCentavos: 100000,
      ),
    ],
    adjustments: [
      BillingAdjustment(
        adjustmentId: 'adjustment-1',
        boarderId: 'boarder-a',
        type: BillingAdjustmentType.charge,
        amountCentavos: 1500,
        reason: 'Key replacement',
        adjustmentDate: start,
      ),
    ],
    warnings: const [],
    recordedAt: recordedAt,
  );
  final statements = [
    BoarderMonthlyStatement(
      boarderId: 'boarder-a',
      boarderName: 'Ana Cruz',
      roomIds: const ['room-a'],
      rentCentavos: 160000,
      rentAdjustmentCentavos: 1500,
      electricityCentavos: 60000,
      waterCentavos: 40000,
      currentChargesCentavos: 261500,
      previousBalanceCentavos: 2500,
    ),
    BoarderMonthlyStatement(
      boarderId: 'boarder-b',
      boarderName: 'Ben Lim',
      roomIds: const ['room-b'],
      rentCentavos: 100000,
      rentAdjustmentCentavos: 0,
      electricityCentavos: 30000,
      waterCentavos: 20000,
      currentChargesCentavos: 150000,
      previousBalanceCentavos: 0,
    ),
  ];
  final cycle = MonthlyBillingCycle(
    billingCycleId: 'cycle-1',
    periodId: '2026-10-01_2026-11-01',
    version: 1,
    replacesCycleId: null,
    startDate: start,
    endDateExclusive: end,
    electricityRecordId: electricity.billingRecordId,
    waterRecordId: water.waterRecordId,
    rentRecordId: rent.rentRecordId,
    electricityTotalCentavos: 90000,
    waterTotalCentavos: 60000,
    rentTotalCentavos: 260000,
    rentAdjustmentCentavos: 1500,
    totalBilledCentavos: 411500,
    totalUnallocatedCentavos: 0,
    statements: statements,
    warnings: const ['Electricity: Room A electricity is estimated.'],
    finalizedAt: recordedAt,
  );
  final control = BillingCycleControl(
    billingCycleId: cycle.billingCycleId,
    state: BillingCycleState.active,
    totalBilledCentavos: 411500,
    totalPaidCentavos: 100000,
    outstandingCentavos: 311500,
    voidReason: null,
    voidedAt: null,
    reissuedAsCycleId: null,
    updatedAt: DateTime.utc(2026, 11, 2),
  );
  final accounts = [
    BoarderBillAccount(
      accountId: 'cycle-1_boarder-a',
      billingCycleId: cycle.billingCycleId,
      boarderId: 'boarder-a',
      boarderName: 'Ana Cruz',
      totalChargesCentavos: 261500,
      previousBalanceCentavos: 2500,
      totalPaidCentavos: 100000,
      updatedAt: DateTime.utc(2026, 11, 2),
    ),
    BoarderBillAccount(
      accountId: 'cycle-1_boarder-b',
      billingCycleId: cycle.billingCycleId,
      boarderId: 'boarder-b',
      boarderName: 'Ben Lim',
      totalChargesCentavos: 150000,
      previousBalanceCentavos: 0,
      totalPaidCentavos: 0,
      updatedAt: DateTime.utc(2026, 11, 2),
    ),
  ];
  final payments = [
    PaymentRecord(
      paymentId: 'payment-1',
      billingCycleId: cycle.billingCycleId,
      boarderId: 'boarder-a',
      boarderName: 'Ana Cruz',
      amountCentavos: 100000,
      paymentDate: BusinessDate(2026, 11, 2),
      method: PaymentMethod.gcash,
      notes: 'Reference 123',
      recordedAt: DateTime.utc(2026, 11, 2),
    ),
  ];
  return const BillingReportAssembler().assemble(
    houseName: 'Mariano Boarding House',
    cycle: cycle,
    control: control,
    accounts: accounts,
    payments: payments,
    electricity: electricity,
    water: water,
    rent: rent,
    generatedOn: BusinessDate(2026, 11, 3),
  );
}
