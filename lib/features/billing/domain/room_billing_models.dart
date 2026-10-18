import '../../property_management/domain/business_date.dart';
import 'monthly_billing_models.dart';

const roomBillingNoRentRecordId = 'not-applicable';

class OccupiedDateRange {
  const OccupiedDateRange({
    required this.startDate,
    required this.endDateExclusive,
  });

  final BusinessDate startDate;
  final BusinessDate endDateExclusive;

  int get days => startDate.daysUntil(endDateExclusive);
}

class RoomMonthlyStatement {
  RoomMonthlyStatement({
    required this.roomId,
    required this.roomName,
    required List<OccupiedDateRange> occupiedRanges,
    required this.occupiedDays,
    required this.rentCentavos,
    required this.adjustmentCentavos,
    required this.electricityCentavos,
    required this.waterCentavos,
    required this.currentChargesCentavos,
  }) : occupiedRanges = List.unmodifiable(occupiedRanges);

  final String roomId;
  final String roomName;
  final List<OccupiedDateRange> occupiedRanges;
  final int occupiedDays;
  final int rentCentavos;
  final int adjustmentCentavos;
  final int electricityCentavos;
  final int waterCentavos;
  final int currentChargesCentavos;
}

class RoomBillingResult {
  RoomBillingResult({
    required this.startDate,
    required this.endDateExclusive,
    required this.electricityRecordId,
    required this.waterRecordId,
    required this.rentRecordId,
    required this.electricityTotalCentavos,
    required this.waterTotalCentavos,
    required this.rentTotalCentavos,
    required this.adjustmentTotalCentavos,
    required this.totalBilledCentavos,
    required this.totalUnallocatedCentavos,
    required List<RoomMonthlyStatement> statements,
    required List<String> warnings,
  }) : statements = List.unmodifiable(statements),
       warnings = List.unmodifiable(warnings);

  final BusinessDate startDate;
  final BusinessDate endDateExclusive;
  final String electricityRecordId;
  final String waterRecordId;
  final String rentRecordId;
  final int electricityTotalCentavos;
  final int waterTotalCentavos;
  final int rentTotalCentavos;
  final int adjustmentTotalCentavos;
  final int totalBilledCentavos;
  final int totalUnallocatedCentavos;
  final List<RoomMonthlyStatement> statements;
  final List<String> warnings;
}

class RoomBillingCycle extends RoomBillingResult {
  RoomBillingCycle({
    required this.billingCycleId,
    required this.periodId,
    required this.version,
    required this.replacesCycleId,
    required super.startDate,
    required super.endDateExclusive,
    required super.electricityRecordId,
    required super.waterRecordId,
    required super.rentRecordId,
    required super.electricityTotalCentavos,
    required super.waterTotalCentavos,
    required super.rentTotalCentavos,
    required super.adjustmentTotalCentavos,
    required super.totalBilledCentavos,
    required super.totalUnallocatedCentavos,
    required super.statements,
    required super.warnings,
    required this.finalizedAt,
  });

  final String billingCycleId;
  final String periodId;
  final int version;
  final String? replacesCycleId;
  final DateTime finalizedAt;
}

class RoomBillAccount {
  const RoomBillAccount({
    required this.accountId,
    required this.billingCycleId,
    required this.roomId,
    required this.roomName,
    required this.totalChargesCentavos,
    required this.totalPaidCentavos,
    required this.updatedAt,
  });

  final String accountId;
  final String billingCycleId;
  final String roomId;
  final String roomName;
  final int totalChargesCentavos;
  final int totalPaidCentavos;
  final DateTime updatedAt;

  int get outstandingCentavos => totalChargesCentavos - totalPaidCentavos;

  BillPaymentStatus get status => roomPaymentStatusFor(
    totalPaidCentavos: totalPaidCentavos,
    totalChargesCentavos: totalChargesCentavos,
  );
}

class RoomPaymentRecord {
  const RoomPaymentRecord({
    required this.paymentId,
    required this.billingCycleId,
    required this.roomId,
    required this.roomName,
    required this.amountCentavos,
    required this.paymentDate,
    required this.method,
    required this.notes,
    required this.recordedAt,
  });

  final String paymentId;
  final String billingCycleId;
  final String roomId;
  final String roomName;
  final int amountCentavos;
  final BusinessDate paymentDate;
  final PaymentMethod method;
  final String? notes;
  final DateTime recordedAt;
}

class RoomBillingDashboardSummary {
  const RoomBillingDashboardSummary({
    required this.currentCycle,
    required this.totalBilledCentavos,
    required this.totalCollectedCentavos,
    required this.totalOutstandingCentavos,
    required this.unpaidBillCount,
  });

  final RoomBillingCycle? currentCycle;
  final int totalBilledCentavos;
  final int totalCollectedCentavos;
  final int totalOutstandingCentavos;
  final int unpaidBillCount;
}

BillPaymentStatus roomPaymentStatusFor({
  required int totalPaidCentavos,
  required int totalChargesCentavos,
}) {
  if (totalChargesCentavos == 0 || totalPaidCentavos >= totalChargesCentavos) {
    return BillPaymentStatus.paid;
  }
  if (totalPaidCentavos > 0) return BillPaymentStatus.partiallyPaid;
  return BillPaymentStatus.unpaid;
}
