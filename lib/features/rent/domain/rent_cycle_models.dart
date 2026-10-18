import '../../property_management/domain/business_date.dart';

enum RentCycleKind { monthly, extraStay }

enum RentCyclePaymentStatus { accruing, due, partiallyPaid, paid }

enum ExtraStayDecision { waived, manualCharge, fullCycle }

class RentAgreement {
  const RentAgreement({
    required this.agreementId,
    required this.occupancyId,
    required this.boarderId,
    required this.boarderName,
    required this.roomId,
    required this.roomName,
    required this.startDate,
    required this.anchorDay,
    required this.monthlyRentCentavos,
    required this.createdAt,
  });

  final String agreementId;
  final String occupancyId;
  final String boarderId;
  final String boarderName;
  final String roomId;
  final String roomName;
  final BusinessDate startDate;
  final int anchorDay;
  final int monthlyRentCentavos;
  final DateTime createdAt;
}

class RentCycle {
  const RentCycle({
    required this.cycleId,
    required this.agreementId,
    required this.occupancyId,
    required this.boarderId,
    required this.boarderName,
    required this.roomId,
    required this.roomName,
    required this.kind,
    required this.cycleNumber,
    required this.coverageStart,
    required this.coverageEndExclusive,
    required this.dueDate,
    required this.amountCentavos,
    required this.createdAt,
  });

  final String cycleId;
  final String agreementId;
  final String occupancyId;
  final String boarderId;
  final String boarderName;
  final String roomId;
  final String roomName;
  final RentCycleKind kind;
  final int cycleNumber;
  final BusinessDate coverageStart;
  final BusinessDate coverageEndExclusive;
  final BusinessDate dueDate;
  final int amountCentavos;
  final DateTime createdAt;
}

class RentCycleControl {
  const RentCycleControl({
    required this.cycleId,
    required this.totalPaidCentavos,
    required this.lastPaymentId,
    required this.updatedAt,
  });

  final String cycleId;
  final int totalPaidCentavos;
  final String? lastPaymentId;
  final DateTime updatedAt;

  int outstandingFor(RentCycle cycle) =>
      (cycle.amountCentavos - totalPaidCentavos).clamp(0, cycle.amountCentavos);

  RentCyclePaymentStatus statusFor(
    RentCycle cycle, {
    required BusinessDate today,
  }) {
    if (totalPaidCentavos >= cycle.amountCentavos) {
      return RentCyclePaymentStatus.paid;
    }
    if (totalPaidCentavos > 0) return RentCyclePaymentStatus.partiallyPaid;
    return today.isBefore(cycle.dueDate)
        ? RentCyclePaymentStatus.accruing
        : RentCyclePaymentStatus.due;
  }
}

class RentPayment {
  const RentPayment({
    required this.paymentId,
    required this.cycleId,
    required this.agreementId,
    required this.amountCentavos,
    required this.note,
    required this.receivedOn,
    required this.createdBy,
    required this.createdAt,
  });

  final String paymentId;
  final String cycleId;
  final String agreementId;
  final int amountCentavos;
  final String? note;
  final BusinessDate receivedOn;
  final String createdBy;
  final DateTime createdAt;
}

class RentExtraStayResolution {
  const RentExtraStayResolution({
    required this.resolutionId,
    required this.agreementId,
    required this.occupancyId,
    required this.boarderId,
    required this.roomId,
    required this.extraStayStart,
    required this.moveOutDate,
    required this.decision,
    required this.amountCentavos,
    required this.note,
    required this.createdBy,
    required this.createdAt,
  });

  final String resolutionId;
  final String agreementId;
  final String occupancyId;
  final String boarderId;
  final String roomId;
  final BusinessDate extraStayStart;
  final BusinessDate moveOutDate;
  final ExtraStayDecision decision;
  final int amountCentavos;
  final String note;
  final String createdBy;
  final DateTime createdAt;
}
