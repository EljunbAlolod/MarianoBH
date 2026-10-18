import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/rent/domain/rent_cycle_models.dart';
import 'package:boarding_house_manager/features/rent/domain/rent_cycle_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = RentCycleService();

  RentAgreement agreement({BusinessDate? start, int rentCentavos = 200000}) {
    final value = start ?? BusinessDate(2026, 6, 10);
    return RentAgreement(
      agreementId: 'occupancy-1',
      occupancyId: 'occupancy-1',
      boarderId: 'boarder-1',
      boarderName: 'Ana Cruz',
      roomId: 'room-201',
      roomName: '201',
      startDate: value,
      anchorDay: value.day,
      monthlyRentCentavos: rentCentavos,
      createdAt: DateTime.utc(2026, 6, 10),
    );
  }

  test('June 10 cycle is full rent and becomes due July 10', () {
    final cycle = service.monthlyCycle(agreement(), 1);

    expect(cycle.coverageStart, BusinessDate(2026, 6, 10));
    expect(cycle.coverageEndExclusive, BusinessDate(2026, 7, 10));
    expect(cycle.dueDate, BusinessDate(2026, 7, 10));
    expect(cycle.amountCentavos, 200000);
  });

  test('next cycle starts on the previous exclusive boundary', () {
    final first = service.monthlyCycle(agreement(), 1);
    final second = service.monthlyCycle(agreement(), 2);

    expect(second.coverageStart, first.coverageEndExclusive);
    expect(second.coverageEndExclusive, BusinessDate(2026, 8, 10));
    expect(second.amountCentavos, first.amountCentavos);
  });

  test('only completed cycles are generated and no daily proration occurs', () {
    final beforeDue = service.completedCycles(
      agreement(),
      throughDate: BusinessDate(2026, 7, 9),
    );
    final onDue = service.completedCycles(
      agreement(),
      throughDate: BusinessDate(2026, 7, 10),
    );

    expect(beforeDue, isEmpty);
    expect(onDue, hasLength(1));
    expect(onDue.single.amountCentavos, 200000);
  });

  test('31st clamps in February then returns to the original anchor day', () {
    final value = agreement(start: BusinessDate(2027, 1, 31));

    expect(
      service.monthlyCycle(value, 1).coverageEndExclusive,
      BusinessDate(2027, 2, 28),
    );
    expect(
      service.monthlyCycle(value, 2).coverageEndExclusive,
      BusinessDate(2027, 3, 31),
    );
  });

  test('July 15 move-out leaves five dates after July 10 boundary', () {
    final boundary = service.latestCompletedBoundary(
      agreement(),
      throughDate: BusinessDate(2026, 7, 15),
    );

    expect(boundary, BusinessDate(2026, 7, 10));
    expect(boundary.daysUntil(BusinessDate(2026, 7, 15)), 5);
  });

  test('partial and full payment statuses keep exact centavo balances', () {
    final cycle = service.monthlyCycle(agreement(), 1);
    final partial = RentCycleControl(
      cycleId: cycle.cycleId,
      totalPaidCentavos: 100000,
      lastPaymentId: 'payment-1',
      updatedAt: DateTime.utc(2026, 7, 10),
    );
    final paid = RentCycleControl(
      cycleId: cycle.cycleId,
      totalPaidCentavos: 200000,
      lastPaymentId: 'payment-2',
      updatedAt: DateTime.utc(2026, 7, 10),
    );

    expect(partial.outstandingFor(cycle), 100000);
    expect(
      partial.statusFor(cycle, today: BusinessDate(2026, 7, 10)),
      RentCyclePaymentStatus.partiallyPaid,
    );
    expect(paid.outstandingFor(cycle), 0);
    expect(
      paid.statusFor(cycle, today: BusinessDate(2026, 7, 10)),
      RentCyclePaymentStatus.paid,
    );
  });
}
