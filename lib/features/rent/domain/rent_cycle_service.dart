import '../../property_management/domain/business_date.dart';
import 'rent_cycle_models.dart';

class RentCycleService {
  const RentCycleService();

  BusinessDate anniversaryBoundary(RentAgreement agreement, int monthOffset) {
    if (monthOffset < 0) throw ArgumentError.value(monthOffset, 'monthOffset');
    final zeroBased = agreement.startDate.month - 1 + monthOffset;
    final year = agreement.startDate.year + zeroBased ~/ 12;
    final month = zeroBased % 12 + 1;
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    return BusinessDate(year, month, agreement.anchorDay.clamp(1, lastDay));
  }

  RentCycle monthlyCycle(RentAgreement agreement, int cycleNumber) {
    if (cycleNumber < 1) throw ArgumentError.value(cycleNumber, 'cycleNumber');
    final start = anniversaryBoundary(agreement, cycleNumber - 1);
    final end = anniversaryBoundary(agreement, cycleNumber);
    return RentCycle(
      cycleId: '${agreement.agreementId}_$cycleNumber',
      agreementId: agreement.agreementId,
      occupancyId: agreement.occupancyId,
      boarderId: agreement.boarderId,
      boarderName: agreement.boarderName,
      roomId: agreement.roomId,
      roomName: agreement.roomName,
      kind: RentCycleKind.monthly,
      cycleNumber: cycleNumber,
      coverageStart: start,
      coverageEndExclusive: end,
      dueDate: end,
      amountCentavos: agreement.monthlyRentCentavos,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  List<RentCycle> completedCycles(
    RentAgreement agreement, {
    required BusinessDate throughDate,
    int maximumCycles = 1200,
  }) {
    final result = <RentCycle>[];
    for (var number = 1; number <= maximumCycles; number++) {
      final cycle = monthlyCycle(agreement, number);
      if (cycle.coverageEndExclusive.isAfter(throughDate)) break;
      result.add(cycle);
    }
    return result;
  }

  RentCycle currentCycle(
    RentAgreement agreement, {
    required BusinessDate onDate,
  }) {
    var number = 1;
    while (number < 1200) {
      final cycle = monthlyCycle(agreement, number);
      if (onDate.isBefore(cycle.coverageEndExclusive)) return cycle;
      number++;
    }
    throw StateError('The rental schedule exceeds the supported range.');
  }

  BusinessDate latestCompletedBoundary(
    RentAgreement agreement, {
    required BusinessDate throughDate,
  }) {
    final cycles = completedCycles(agreement, throughDate: throughDate);
    return cycles.isEmpty
        ? agreement.startDate
        : cycles.last.coverageEndExclusive;
  }
}
