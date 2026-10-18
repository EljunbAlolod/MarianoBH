import '../../electricity/domain/electricity_models.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/domain/occupancy.dart';
import '../../water/domain/water_models.dart';
import 'monthly_billing_models.dart';
import 'room_billing_models.dart';

class RoomBillingException implements Exception {
  const RoomBillingException(this.message, {required this.code});

  final String message;
  final String code;

  @override
  String toString() => 'RoomBillingException($code): $message';
}

class RoomBillingAssembler {
  const RoomBillingAssembler();

  RoomBillingResult assemble({
    required ElectricityBillingRecord electricity,
    required WaterBillingRecord water,
    required List<Occupancy> occupancies,
  }) {
    _validatePeriod(electricity, water);
    if (water.method != WaterBillingMethod.roomDays) {
      throw const RoomBillingException(
        'Create the water source using occupied room-days. Boarder person-days cannot be used for room bills.',
        code: 'legacy-water-allocation',
      );
    }
    final rangesByRoom = occupiedRangesByRoom(
      occupancies: occupancies,
      startDate: electricity.startDate,
      endDateExclusive: electricity.endDateExclusive,
    );
    final electricityByRoom = {
      for (final item in electricity.roomCharges) item.roomId: item,
    };
    final waterByRoom = {
      for (final item in water.roomAllocations) item.roomId: item,
    };
    final statements = <RoomMonthlyStatement>[];

    for (final entry in rangesByRoom.entries) {
      final roomId = entry.key;
      final ranges = entry.value;
      final occupiedDays = ranges.fold<int>(0, (sum, item) => sum + item.days);
      final electricityRoom = electricityByRoom[roomId];
      final waterRoom = waterByRoom[roomId];
      if (electricityRoom == null || waterRoom == null) {
        throw const RoomBillingException(
          'Every occupied room needs matching electricity and water source data.',
          code: 'missing-room-source',
        );
      }
      if (waterRoom.occupancyDays != occupiedDays) {
        throw RoomBillingException(
          '${waterRoom.roomName} occupancy changed after a source was saved. Recreate the room-based sources.',
          code: 'occupancy-snapshot-mismatch',
        );
      }
      final electricityCentavos = _occupiedElectricity(electricityRoom, ranges);
      final current = electricityCentavos + waterRoom.roomChargeCentavos;
      if (current < 0) {
        throw RoomBillingException(
          '${waterRoom.roomName} has a negative room charge.',
          code: 'negative-room-charge',
        );
      }
      statements.add(
        RoomMonthlyStatement(
          roomId: roomId,
          roomName: waterRoom.roomName,
          occupiedRanges: ranges,
          occupiedDays: occupiedDays,
          rentCentavos: 0,
          adjustmentCentavos: 0,
          electricityCentavos: electricityCentavos,
          waterCentavos: waterRoom.roomChargeCentavos,
          currentChargesCentavos: current,
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
      throw const RoomBillingException(
        'No room was occupied during this billing month.',
        code: 'no-occupied-rooms',
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
    if (waterTotal != water.totalAllocatedCentavos) {
      throw const RoomBillingException(
        'Room source totals do not reconcile. Recreate the source records for this month.',
        code: 'source-totals-do-not-reconcile',
      );
    }
    final total = statements.fold<int>(
      0,
      (sum, item) => sum + item.currentChargesCentavos,
    );
    final warnings = <String>[
      ...electricity.warnings.map((value) => 'Electricity: $value'),
      ...water.warnings.map((value) => 'Water: $value'),
    ];
    final unallocated =
        electricity.totalChargeCentavos -
        electricityTotal +
        water.totalUnallocatedCentavos;
    if (unallocated > 0) {
      warnings.add(
        'Vacant-room utility usage remains landlady-paid and is not included in room bills.',
      );
    }
    return RoomBillingResult(
      startDate: electricity.startDate,
      endDateExclusive: electricity.endDateExclusive,
      electricityRecordId: electricity.billingRecordId,
      waterRecordId: water.waterRecordId,
      rentRecordId: roomBillingNoRentRecordId,
      electricityTotalCentavos: electricityTotal,
      waterTotalCentavos: waterTotal,
      rentTotalCentavos: 0,
      adjustmentTotalCentavos: 0,
      totalBilledCentavos: total,
      totalUnallocatedCentavos: unallocated,
      statements: statements,
      warnings: warnings,
    );
  }

  RoomBillingDashboardSummary summarize({
    required List<RoomBillingCycle> cycles,
    required List<BillingCycleControl> controls,
    required List<RoomBillAccount> accounts,
  }) {
    final controlsById = {
      for (final item in controls) item.billingCycleId: item,
    };
    final activeCycles =
        cycles
            .where(
              (cycle) =>
                  controlsById[cycle.billingCycleId]?.state ==
                  BillingCycleState.active,
            )
            .toList()
          ..sort((a, b) {
            final byEnd = b.endDateExclusive.compareTo(a.endDateExclusive);
            return byEnd != 0 ? byEnd : b.version.compareTo(a.version);
          });
    final activeIds = activeCycles.map((item) => item.billingCycleId).toSet();
    final activeAccounts = accounts
        .where((item) => activeIds.contains(item.billingCycleId))
        .toList();
    return RoomBillingDashboardSummary(
      currentCycle: activeCycles.firstOrNull,
      totalBilledCentavos: activeAccounts.fold(
        0,
        (sum, item) => sum + item.totalChargesCentavos,
      ),
      totalCollectedCentavos: activeAccounts.fold(
        0,
        (sum, item) => sum + item.totalPaidCentavos,
      ),
      totalOutstandingCentavos: activeAccounts.fold(
        0,
        (sum, item) => sum + item.outstandingCentavos,
      ),
      unpaidBillCount: activeAccounts
          .where((item) => item.status != BillPaymentStatus.paid)
          .length,
    );
  }

  void _validatePeriod(
    ElectricityBillingRecord electricity,
    WaterBillingRecord water,
  ) {
    if (electricity.startDate != water.startDate ||
        electricity.endDateExclusive != water.endDateExclusive) {
      throw const RoomBillingException(
        'Electricity and water records must use the exact same dates.',
        code: 'source-period-mismatch',
      );
    }
    final start = electricity.startDate;
    final expectedEnd = start.month == 12
        ? BusinessDate(start.year + 1, 1, 1)
        : BusinessDate(start.year, start.month + 1, 1);
    if (start.day != 1 || electricity.endDateExclusive != expectedEnd) {
      throw const RoomBillingException(
        'Room bills use complete calendar-month source periods.',
        code: 'not-calendar-month',
      );
    }
  }

  int _occupiedElectricity(
    RoomElectricityCharge room,
    List<OccupiedDateRange> ranges,
  ) {
    final boundaries = <BusinessDate>{};
    for (final segment in room.segments) {
      boundaries
        ..add(segment.startDate)
        ..add(segment.endDateExclusive);
    }
    for (final range in ranges) {
      if (!boundaries.contains(range.startDate) ||
          !boundaries.contains(range.endDateExclusive)) {
        throw RoomBillingException(
          '${room.roomName} needs exact meter readings on ${range.startDate} and ${range.endDateExclusive} so vacant usage is not charged to the room.',
          code: 'missing-occupancy-boundary-reading',
        );
      }
    }
    var total = 0;
    for (final segment in room.segments) {
      final occupied = ranges.any(
        (range) =>
            !segment.startDate.isBefore(range.startDate) &&
            !segment.endDateExclusive.isAfter(range.endDateExclusive),
      );
      if (occupied) total += segment.chargeCentavos;
    }
    return total;
  }
}

Map<String, List<OccupiedDateRange>> occupiedRangesByRoom({
  required List<Occupancy> occupancies,
  required BusinessDate startDate,
  required BusinessDate endDateExclusive,
}) {
  final daysByRoom = <String, Set<int>>{};
  for (final occupancy in occupancies) {
    final overlapStart = occupancy.moveInDate.isAfter(startDate)
        ? occupancy.moveInDate
        : startDate;
    final moveOut = occupancy.moveOutDate;
    final overlapEnd = moveOut != null && moveOut.isBefore(endDateExclusive)
        ? moveOut
        : endDateExclusive;
    if (!overlapStart.isBefore(overlapEnd)) continue;
    final days = daysByRoom.putIfAbsent(occupancy.roomId, () => <int>{});
    final first = startDate.daysUntil(overlapStart);
    final count = overlapStart.daysUntil(overlapEnd);
    for (var offset = 0; offset < count; offset++) {
      days.add(first + offset);
    }
  }
  final result = <String, List<OccupiedDateRange>>{};
  for (final entry in daysByRoom.entries) {
    final days = entry.value.toList()..sort();
    if (days.isEmpty) continue;
    final ranges = <OccupiedDateRange>[];
    var rangeStart = days.first;
    var previous = days.first;
    for (final day in days.skip(1)) {
      if (day != previous + 1) {
        ranges.add(
          OccupiedDateRange(
            startDate: startDate.addDays(rangeStart),
            endDateExclusive: startDate.addDays(previous + 1),
          ),
        );
        rangeStart = day;
      }
      previous = day;
    }
    ranges.add(
      OccupiedDateRange(
        startDate: startDate.addDays(rangeStart),
        endDateExclusive: startDate.addDays(previous + 1),
      ),
    );
    result[entry.key] = ranges;
  }
  return result;
}
