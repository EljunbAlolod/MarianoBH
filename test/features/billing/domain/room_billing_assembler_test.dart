import 'package:boarding_house_manager/features/billing/domain/room_billing_assembler.dart';
import 'package:boarding_house_manager/features/billing/domain/room_billing_models.dart';
import 'package:boarding_house_manager/features/electricity/domain/electricity_models.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/property_management/domain/occupancy.dart';
import 'package:boarding_house_manager/features/water/domain/water_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const assembler = RoomBillingAssembler();

  test('bills one room only for its occupied calendar range', () {
    final result = assembler.assemble(
      electricity: _electricity(withOccupancyBoundary: true),
      water: _water(),
      occupancies: [_occupancy()],
    );

    final statement = result.statements.single;
    expect(statement.occupiedRanges.single.startDate, _d(2026, 10, 10));
    expect(statement.occupiedRanges.single.endDateExclusive, _d(2026, 11, 1));
    expect(statement.occupiedDays, 22);
    expect(statement.electricityCentavos, 22000);
    expect(statement.waterCentavos, 11000);
    expect(statement.rentCentavos, 0);
    expect(statement.currentChargesCentavos, 33000);
    expect(result.rentRecordId, roomBillingNoRentRecordId);
    expect(result.rentTotalCentavos, 0);
    expect(result.totalUnallocatedCentavos, 9000);
  });

  test('requires exact meter boundaries at move-in and month end', () {
    expect(
      () => assembler.assemble(
        electricity: _electricity(withOccupancyBoundary: false),
        water: _water(),
        occupancies: [_occupancy()],
      ),
      throwsA(
        isA<RoomBillingException>().having(
          (error) => error.code,
          'code',
          'missing-occupancy-boundary-reading',
        ),
      ),
    );
  });

  test('rejects legacy person-day water allocation', () {
    expect(
      () => assembler.assemble(
        electricity: _electricity(withOccupancyBoundary: true),
        water: _water(method: WaterBillingMethod.personDays),
        occupancies: [_occupancy()],
      ),
      throwsA(
        isA<RoomBillingException>().having(
          (error) => error.code,
          'code',
          'legacy-water-allocation',
        ),
      ),
    );
  });
}

BusinessDate _d(int year, int month, int day) => BusinessDate(year, month, day);

Occupancy _occupancy() => Occupancy(
  occupancyId: 'occupancy-a',
  boarderId: 'boarder-a',
  roomId: 'room-a',
  moveInDate: _d(2026, 10, 10),
  moveOutDate: null,
  createdAt: DateTime.utc(2026, 10, 10),
  updatedAt: DateTime.utc(2026, 10, 10),
);

ElectricitySegmentSnapshot _segment({
  required String id,
  required BusinessDate start,
  required BusinessDate end,
  required int charge,
}) => ElectricitySegmentSnapshot(
  meterId: 'meter-a',
  sequence: 1,
  previousReadingId: '$id-before',
  currentReadingId: '$id-after',
  startDate: start,
  endDateExclusive: end,
  previousReadingWh: 0,
  currentReadingWh: charge,
  consumptionWh: charge,
  chargeCentavos: charge,
  boarderShares: const [],
  unallocatedCentavos: charge,
  allocationQuality: ElectricityAllocationQuality.unallocated,
);

ElectricityBillingRecord _electricity({required bool withOccupancyBoundary}) {
  final segments = withOccupancyBoundary
      ? [
          _segment(
            id: 'vacant',
            start: _d(2026, 10, 1),
            end: _d(2026, 10, 10),
            charge: 9000,
          ),
          _segment(
            id: 'occupied',
            start: _d(2026, 10, 10),
            end: _d(2026, 11, 1),
            charge: 22000,
          ),
        ]
      : [
          _segment(
            id: 'whole-month',
            start: _d(2026, 10, 1),
            end: _d(2026, 11, 1),
            charge: 31000,
          ),
        ];
  return ElectricityBillingRecord(
    billingRecordId: '2026-10-01_2026-11-01_roomV2',
    startDate: _d(2026, 10, 1),
    endDateExclusive: _d(2026, 11, 1),
    rateMicropesosPerKwh: 10000000,
    roomCharges: [
      RoomElectricityCharge(
        roomId: 'room-a',
        roomName: 'Room A',
        segments: segments,
        adjustments: const [],
        boarderShares: const [],
        consumptionWh: 31000,
        baseChargeCentavos: 31000,
        adjustmentCentavos: 0,
        finalChargeCentavos: 31000,
        allocatedCentavos: 0,
        unallocatedCentavos: 31000,
        hasEstimatedShares: false,
      ),
    ],
    totalConsumptionWh: 31000,
    totalBaseChargeCentavos: 31000,
    totalAdjustmentsCentavos: 0,
    totalChargeCentavos: 31000,
    totalAllocatedCentavos: 0,
    totalUnallocatedCentavos: 31000,
    warnings: const [],
    recordedAt: DateTime.utc(2026, 11, 1),
    sourceReadingIds: const ['oct-1', 'oct-10', 'nov-1'],
  );
}

WaterBillingRecord _water({
  WaterBillingMethod method = WaterBillingMethod.roomDays,
}) => WaterBillingRecord(
  waterRecordId: '2026-10-01_2026-11-01_roomDays',
  startDate: _d(2026, 10, 1),
  endDateExclusive: _d(2026, 11, 1),
  waterBillCentavos: 11000,
  method: method,
  summerBasis: SummerElectricityBasis.roomElectricityCharge,
  electricityRecordId: null,
  totalPersonDays: 22,
  totalElectricityBasis: 0,
  totalAllocatedCentavos: 11000,
  totalUnallocatedCentavos: 0,
  roomAllocations: [
    WaterRoomAllocation(
      roomId: 'room-a',
      roomName: 'Room A',
      electricityBasisValue: 0,
      occupancyDays: 22,
      roomChargeCentavos: 11000,
      allocatedCentavos: 11000,
      unallocatedCentavos: 0,
      boarderShares: const [],
    ),
  ],
  boarderShares: const [],
  warnings: const [],
  recordedAt: DateTime.utc(2026, 11, 1),
);
