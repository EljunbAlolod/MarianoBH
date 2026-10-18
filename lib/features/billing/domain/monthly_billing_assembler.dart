import '../../electricity/domain/electricity_models.dart';
import '../../rent/domain/rent_models.dart';
import '../../water/domain/water_models.dart';
import 'monthly_billing_models.dart';

class MonthlyBillingException implements Exception {
  const MonthlyBillingException(this.message, {required this.code});
  final String message;
  final String code;

  @override
  String toString() => 'MonthlyBillingException($code): $message';
}

class MonthlyBillingAssembler {
  const MonthlyBillingAssembler();

  MonthlyBillingResult assemble({
    required ElectricityBillingRecord electricity,
    required WaterBillingRecord water,
    required RentBillingRecord rent,
    Map<String, int> previousBalancesByBoarder = const {},
  }) {
    if (electricity.startDate != water.startDate ||
        electricity.startDate != rent.startDate ||
        electricity.endDateExclusive != water.endDateExclusive ||
        electricity.endDateExclusive != rent.endDateExclusive) {
      throw const MonthlyBillingException(
        'Electricity, water, and rent records must use the exact same dates.',
        code: 'source-period-mismatch',
      );
    }

    final items = <String, _MutableStatement>{};
    _MutableStatement item(String id, String name) => items.putIfAbsent(
      id,
      () => _MutableStatement(boarderId: id, boarderName: name),
    );

    for (final room in electricity.roomCharges) {
      for (final share in room.boarderShares) {
        final target = item(share.boarderId, share.boarderName);
        target.electricity += share.amountCentavos;
        target.roomIds.add(room.roomId);
      }
    }
    for (final share in water.boarderShares) {
      final target = item(share.boarderId, share.boarderName);
      target.water += share.amountCentavos;
      target.roomIds.addAll(share.roomIds);
    }
    for (final charge in rent.boarderCharges) {
      final target = item(charge.boarderId, charge.boarderName);
      target.rent += charge.rentCentavos;
      target.rentAdjustment += charge.adjustmentCentavos;
      target.roomIds.addAll(charge.roomIds);
    }

    final statements =
        items.values.map((item) {
          final current =
              item.rent + item.rentAdjustment + item.electricity + item.water;
          if (current < 0) {
            throw MonthlyBillingException(
              '${item.boarderName} has a negative monthly charge.',
              code: 'negative-boarder-charge',
            );
          }
          final previous = previousBalancesByBoarder[item.boarderId] ?? 0;
          if (previous < 0) {
            throw const MonthlyBillingException(
              'A previous balance cannot be negative.',
              code: 'negative-previous-balance',
            );
          }
          final roomIds = item.roomIds.toList()..sort();
          return BoarderMonthlyStatement(
            boarderId: item.boarderId,
            boarderName: item.boarderName,
            roomIds: roomIds,
            rentCentavos: item.rent,
            rentAdjustmentCentavos: item.rentAdjustment,
            electricityCentavos: item.electricity,
            waterCentavos: item.water,
            currentChargesCentavos: current,
            previousBalanceCentavos: previous,
          );
        }).toList()..sort((a, b) {
          final byName = a.boarderName.toLowerCase().compareTo(
            b.boarderName.toLowerCase(),
          );
          return byName != 0 ? byName : a.boarderId.compareTo(b.boarderId);
        });

    final totalBilled = statements.fold<int>(
      0,
      (sum, item) => sum + item.currentChargesCentavos,
    );
    final expectedAllocated =
        electricity.totalAllocatedCentavos +
        water.totalAllocatedCentavos +
        rent.grandTotalCentavos;
    if (totalBilled != expectedAllocated) {
      throw const MonthlyBillingException(
        'The boarder statements do not reconcile with the source records.',
        code: 'source-totals-do-not-reconcile',
      );
    }

    final warnings = <String>[
      ...electricity.warnings.map((value) => 'Electricity: $value'),
      ...water.warnings.map((value) => 'Water: $value'),
      ...rent.warnings.map((value) => 'Rent: $value'),
    ];
    final unallocated =
        electricity.totalUnallocatedCentavos + water.totalUnallocatedCentavos;
    if (unallocated > 0) {
      warnings.add(
        'Unallocated utility costs are landlady-paid and are not included in boarder bills.',
      );
    }

    return MonthlyBillingResult(
      startDate: electricity.startDate,
      endDateExclusive: electricity.endDateExclusive,
      electricityRecordId: electricity.billingRecordId,
      waterRecordId: water.waterRecordId,
      rentRecordId: rent.rentRecordId,
      electricityTotalCentavos: electricity.totalAllocatedCentavos,
      waterTotalCentavos: water.totalAllocatedCentavos,
      rentTotalCentavos: rent.totalRentCentavos,
      rentAdjustmentCentavos: rent.totalAdjustmentCentavos,
      totalBilledCentavos: totalBilled,
      totalUnallocatedCentavos: unallocated,
      statements: statements,
      warnings: warnings,
    );
  }

  BillingDashboardSummary summarize({
    required List<MonthlyBillingCycle> cycles,
    required List<BillingCycleControl> controls,
    required List<BoarderBillAccount> accounts,
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
    final activeAccounts = accounts.where(
      (item) => activeIds.contains(item.billingCycleId),
    );
    return BillingDashboardSummary(
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
}

class _MutableStatement {
  _MutableStatement({required this.boarderId, required this.boarderName});
  final String boarderId;
  final String boarderName;
  final Set<String> roomIds = {};
  int rent = 0;
  int rentAdjustment = 0;
  int electricity = 0;
  int water = 0;
}
