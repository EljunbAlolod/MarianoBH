import '../../billing/domain/monthly_billing_models.dart';
import '../../electricity/domain/electricity_models.dart';
import '../../property_management/domain/business_date.dart';
import '../../rent/domain/rent_models.dart';
import '../../water/domain/water_models.dart';
import 'billing_report_models.dart';

class BillingReportAssembler {
  const BillingReportAssembler();

  BillingReportSnapshot assemble({
    required String houseName,
    required MonthlyBillingCycle cycle,
    required BillingCycleControl control,
    required List<BoarderBillAccount> accounts,
    required List<PaymentRecord> payments,
    required ElectricityBillingRecord electricity,
    required WaterBillingRecord water,
    required RentBillingRecord rent,
    required BusinessDate generatedOn,
  }) {
    _validateSources(cycle, electricity, water, rent);
    final cycleAccounts = accounts
        .where((item) => item.billingCycleId == cycle.billingCycleId)
        .toList(growable: false);
    final cyclePayments = payments
        .where((item) => item.billingCycleId == cycle.billingCycleId)
        .toList(growable: false);
    _validateLedger(cycle, control, cycleAccounts, cyclePayments);

    final roomNames = _roomNames(electricity, water, rent);
    final accountByBoarder = {
      for (final account in cycleAccounts) account.boarderId: account,
    };
    final rentByBoarder = {
      for (final charge in rent.boarderCharges) charge.boarderId: charge,
    };
    final waterByBoarder = {
      for (final share in water.boarderShares) share.boarderId: share,
    };

    final boarders =
        cycle.statements.map((statement) {
          final account = accountByBoarder[statement.boarderId];
          if (account == null) {
            throw BillingReportException(
              '${statement.boarderName} does not have a matching bill account.',
              code: 'missing-boarder-account',
            );
          }
          final electricityShares = electricity.roomCharges
              .expand((room) => room.boarderShares)
              .where((share) => share.boarderId == statement.boarderId)
              .toList(growable: false);
          final rentCharge = rentByBoarder[statement.boarderId];
          final waterShare = waterByBoarder[statement.boarderId];
          final billableDays =
              rentCharge?.occupancyDays ??
              waterShare?.occupancyDays ??
              electricityShares.fold<int>(
                0,
                (total, share) => total + share.occupancyDays,
              );
          final boarderPayments =
              cyclePayments
                  .where((item) => item.boarderId == statement.boarderId)
                  .toList()
                ..sort(_comparePayments);
          return BoarderBillingReportRow(
            statement: statement,
            account: account,
            roomNames: statement.roomIds
                .map((roomId) => roomNames[roomId] ?? 'Room $roomId')
                .toList(growable: false),
            billableDays: billableDays,
            electricityEstimated: electricityShares.any(
              (share) => share.isEstimated,
            ),
            summerWaterDetails: _summerDetails(statement.boarderId, water),
            payments: boarderPayments,
          );
        }).toList()..sort(
          (a, b) => a.statement.boarderName.toLowerCase().compareTo(
            b.statement.boarderName.toLowerCase(),
          ),
        );

    final orderedPayments = [...cyclePayments]..sort(_comparePayments);
    return BillingReportSnapshot(
      houseName: houseName.trim(),
      cycle: cycle,
      control: control,
      electricity: electricity,
      water: water,
      rent: rent,
      rooms: _rooms(electricity, water, rent),
      boarders: boarders,
      payments: orderedPayments,
      generatedOn: generatedOn,
    );
  }

  void _validateSources(
    MonthlyBillingCycle cycle,
    ElectricityBillingRecord electricity,
    WaterBillingRecord water,
    RentBillingRecord rent,
  ) {
    final idsMatch =
        cycle.electricityRecordId == electricity.billingRecordId &&
        cycle.waterRecordId == water.waterRecordId &&
        cycle.rentRecordId == rent.rentRecordId;
    final datesMatch =
        [
          (electricity.startDate, electricity.endDateExclusive),
          (water.startDate, water.endDateExclusive),
          (rent.startDate, rent.endDateExclusive),
        ].every(
          (period) =>
              period.$1 == cycle.startDate &&
              period.$2 == cycle.endDateExclusive,
        );
    final totalsMatch =
        cycle.electricityTotalCentavos == electricity.totalAllocatedCentavos &&
        cycle.waterTotalCentavos == water.totalAllocatedCentavos &&
        cycle.rentTotalCentavos == rent.totalRentCentavos &&
        cycle.rentAdjustmentCentavos == rent.totalAdjustmentCentavos &&
        cycle.totalBilledCentavos ==
            cycle.electricityTotalCentavos +
                cycle.waterTotalCentavos +
                cycle.rentTotalCentavos +
                cycle.rentAdjustmentCentavos;
    if (!idsMatch || !datesMatch || !totalsMatch) {
      throw const BillingReportException(
        'The finalized bill and its immutable source records do not reconcile.',
        code: 'source-snapshot-mismatch',
      );
    }
  }

  void _validateLedger(
    MonthlyBillingCycle cycle,
    BillingCycleControl control,
    List<BoarderBillAccount> accounts,
    List<PaymentRecord> payments,
  ) {
    if (control.billingCycleId != cycle.billingCycleId ||
        control.totalBilledCentavos != cycle.totalBilledCentavos) {
      throw const BillingReportException(
        'The billing-cycle totals are temporarily unavailable.',
        code: 'cycle-control-mismatch',
      );
    }
    final accountIds = <String>{};
    final boarderIds = <String>{};
    for (final account in accounts) {
      if (!accountIds.add(account.accountId) ||
          !boarderIds.add(account.boarderId)) {
        throw const BillingReportException(
          'Duplicate boarder bill accounts were found.',
          code: 'duplicate-boarder-account',
        );
      }
    }
    final charges = accounts.fold<int>(
      0,
      (sum, item) => sum + item.totalChargesCentavos,
    );
    final paid = accounts.fold<int>(
      0,
      (sum, item) => sum + item.totalPaidCentavos,
    );
    final paymentTotal = payments.fold<int>(
      0,
      (sum, item) => sum + item.amountCentavos,
    );
    if (charges != control.totalBilledCentavos ||
        paid != control.totalPaidCentavos ||
        paymentTotal != paid ||
        control.outstandingCentavos !=
            control.totalBilledCentavos - control.totalPaidCentavos) {
      throw const BillingReportException(
        'Payment totals are still synchronizing. Please try again.',
        code: 'payment-ledger-mismatch',
      );
    }
  }

  Map<String, String> _roomNames(
    ElectricityBillingRecord electricity,
    WaterBillingRecord water,
    RentBillingRecord rent,
  ) {
    return {
      for (final room in electricity.roomCharges) room.roomId: room.roomName,
      for (final room in water.roomAllocations) room.roomId: room.roomName,
      for (final room in rent.roomAllocations) room.roomId: room.roomName,
    };
  }

  List<RoomBillingReportRow> _rooms(
    ElectricityBillingRecord electricity,
    WaterBillingRecord water,
    RentBillingRecord rent,
  ) {
    final rows = <String, _RoomAccumulator>{};
    _RoomAccumulator room(String id, String name) =>
        rows.putIfAbsent(id, () => _RoomAccumulator(id, name));
    for (final source in electricity.roomCharges) {
      room(source.roomId, source.roomName).electricity +=
          source.allocatedCentavos;
    }
    for (final source in water.roomAllocations) {
      room(source.roomId, source.roomName).water += source.allocatedCentavos;
    }
    for (final source in rent.roomAllocations) {
      room(source.roomId, source.roomName).rent += source.rentCentavos;
    }
    final result = rows.values
        .map(
          (item) => RoomBillingReportRow(
            roomId: item.id,
            roomName: item.name,
            electricityCentavos: item.electricity,
            waterCentavos: item.water,
            rentCentavos: item.rent,
          ),
        )
        .toList();
    result.sort(
      (a, b) => a.roomName.toLowerCase().compareTo(b.roomName.toLowerCase()),
    );
    return result;
  }

  List<SummerWaterReportDetail> _summerDetails(
    String boarderId,
    WaterBillingRecord water,
  ) {
    if (water.method != WaterBillingMethod.electricityPercentage ||
        water.totalElectricityBasis <= 0) {
      return const [];
    }
    final result = <SummerWaterReportDetail>[];
    for (final room in water.roomAllocations) {
      final amount = room.boarderShares
          .where((share) => share.boarderId == boarderId)
          .fold<int>(0, (sum, share) => sum + share.amountCentavos);
      if (amount == 0) continue;
      result.add(
        SummerWaterReportDetail(
          roomName: room.roomName,
          electricityBasisValue: room.electricityBasisValue,
          basisPercentHundredths:
              (room.electricityBasisValue * 10000 +
                  water.totalElectricityBasis ~/ 2) ~/
              water.totalElectricityBasis,
          boarderWaterCentavos: amount,
        ),
      );
    }
    return result;
  }

  int _comparePayments(PaymentRecord a, PaymentRecord b) {
    final date = a.paymentDate.compareTo(b.paymentDate);
    if (date != 0) return date;
    return a.recordedAt.compareTo(b.recordedAt);
  }
}

class _RoomAccumulator {
  _RoomAccumulator(this.id, this.name);

  final String id;
  final String name;
  int electricity = 0;
  int water = 0;
  int rent = 0;
}
