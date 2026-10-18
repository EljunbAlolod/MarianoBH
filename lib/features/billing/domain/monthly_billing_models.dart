import '../../property_management/domain/business_date.dart';

enum BillingCycleState { active, voided }

enum BillPaymentStatus { unpaid, partiallyPaid, paid }

enum PaymentMethod { cash, gcash, bankTransfer, other }

class BoarderMonthlyStatement {
  BoarderMonthlyStatement({
    required this.boarderId,
    required this.boarderName,
    required List<String> roomIds,
    required this.rentCentavos,
    required this.rentAdjustmentCentavos,
    required this.electricityCentavos,
    required this.waterCentavos,
    required this.currentChargesCentavos,
    required this.previousBalanceCentavos,
  }) : roomIds = List.unmodifiable(roomIds);

  final String boarderId;
  final String boarderName;
  final List<String> roomIds;
  final int rentCentavos;
  final int rentAdjustmentCentavos;
  final int electricityCentavos;
  final int waterCentavos;
  final int currentChargesCentavos;

  /// Informational snapshot of older active bills when this cycle was created.
  /// Payments remain allocated to their original bill to prevent double-counting.
  final int previousBalanceCentavos;

  int get amountDueAtFinalizationCentavos =>
      currentChargesCentavos + previousBalanceCentavos;
}

class MonthlyBillingResult {
  MonthlyBillingResult({
    required this.startDate,
    required this.endDateExclusive,
    required this.electricityRecordId,
    required this.waterRecordId,
    required this.rentRecordId,
    required this.electricityTotalCentavos,
    required this.waterTotalCentavos,
    required this.rentTotalCentavos,
    required this.rentAdjustmentCentavos,
    required this.totalBilledCentavos,
    required this.totalUnallocatedCentavos,
    required List<BoarderMonthlyStatement> statements,
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
  final int rentAdjustmentCentavos;
  final int totalBilledCentavos;
  final int totalUnallocatedCentavos;
  final List<BoarderMonthlyStatement> statements;
  final List<String> warnings;
}

class MonthlyBillingCycle extends MonthlyBillingResult {
  MonthlyBillingCycle({
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
    required super.rentAdjustmentCentavos,
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

class BillingCycleControl {
  const BillingCycleControl({
    required this.billingCycleId,
    required this.state,
    required this.totalBilledCentavos,
    required this.totalPaidCentavos,
    required this.outstandingCentavos,
    required this.voidReason,
    required this.voidedAt,
    required this.reissuedAsCycleId,
    required this.updatedAt,
  });

  final String billingCycleId;
  final BillingCycleState state;
  final int totalBilledCentavos;
  final int totalPaidCentavos;
  final int outstandingCentavos;
  final String? voidReason;
  final DateTime? voidedAt;
  final String? reissuedAsCycleId;
  final DateTime updatedAt;

  BillPaymentStatus get paymentStatus => paymentStatusFor(
    totalPaidCentavos: totalPaidCentavos,
    totalChargesCentavos: totalBilledCentavos,
  );
}

class BoarderBillAccount {
  const BoarderBillAccount({
    required this.accountId,
    required this.billingCycleId,
    required this.boarderId,
    required this.boarderName,
    required this.totalChargesCentavos,
    required this.previousBalanceCentavos,
    required this.totalPaidCentavos,
    required this.updatedAt,
  });

  final String accountId;
  final String billingCycleId;
  final String boarderId;
  final String boarderName;
  final int totalChargesCentavos;
  final int previousBalanceCentavos;
  final int totalPaidCentavos;
  final DateTime updatedAt;

  int get outstandingCentavos => totalChargesCentavos - totalPaidCentavos;

  BillPaymentStatus get status => paymentStatusFor(
    totalPaidCentavos: totalPaidCentavos,
    totalChargesCentavos: totalChargesCentavos,
  );
}

class PaymentRecord {
  const PaymentRecord({
    required this.paymentId,
    required this.billingCycleId,
    required this.boarderId,
    required this.boarderName,
    required this.amountCentavos,
    required this.paymentDate,
    required this.method,
    required this.notes,
    required this.recordedAt,
  });

  final String paymentId;
  final String billingCycleId;
  final String boarderId;
  final String boarderName;
  final int amountCentavos;
  final BusinessDate paymentDate;
  final PaymentMethod method;
  final String? notes;
  final DateTime recordedAt;
}

class BillingDashboardSummary {
  const BillingDashboardSummary({
    required this.currentCycle,
    required this.totalBilledCentavos,
    required this.totalCollectedCentavos,
    required this.totalOutstandingCentavos,
    required this.unpaidBillCount,
  });

  final MonthlyBillingCycle? currentCycle;
  final int totalBilledCentavos;
  final int totalCollectedCentavos;
  final int totalOutstandingCentavos;
  final int unpaidBillCount;
}

BillPaymentStatus paymentStatusFor({
  required int totalPaidCentavos,
  required int totalChargesCentavos,
}) {
  if (totalChargesCentavos > 0 && totalPaidCentavos >= totalChargesCentavos) {
    return BillPaymentStatus.paid;
  }
  if (totalPaidCentavos > 0) return BillPaymentStatus.partiallyPaid;
  return BillPaymentStatus.unpaid;
}
