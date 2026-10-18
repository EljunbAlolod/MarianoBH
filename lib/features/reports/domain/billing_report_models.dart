import '../../billing/domain/monthly_billing_models.dart';
import '../../electricity/domain/electricity_models.dart';
import '../../property_management/domain/business_date.dart';
import '../../rent/domain/rent_models.dart';
import '../../water/domain/water_models.dart';

enum BillingReportDocumentType {
  monthlySummary,
  combinedBoarderStatements,
  individualBoarderStatement,
}

class BillingReportException implements Exception {
  const BillingReportException(this.message, {required this.code});

  final String message;
  final String code;

  @override
  String toString() => message;
}

class BillingReportSnapshot {
  BillingReportSnapshot({
    required this.houseName,
    required this.cycle,
    required this.control,
    required this.electricity,
    required this.water,
    required this.rent,
    required List<RoomBillingReportRow> rooms,
    required List<BoarderBillingReportRow> boarders,
    required List<PaymentRecord> payments,
    required this.generatedOn,
  }) : rooms = List.unmodifiable(rooms),
       boarders = List.unmodifiable(boarders),
       payments = List.unmodifiable(payments);

  final String houseName;
  final MonthlyBillingCycle cycle;
  final BillingCycleControl control;
  final ElectricityBillingRecord electricity;
  final WaterBillingRecord water;
  final RentBillingRecord rent;
  final List<RoomBillingReportRow> rooms;
  final List<BoarderBillingReportRow> boarders;
  final List<PaymentRecord> payments;
  final BusinessDate generatedOn;

  BoarderBillingReportRow boarder(String boarderId) {
    return boarders.singleWhere(
      (item) => item.statement.boarderId == boarderId,
      orElse: () => throw const BillingReportException(
        'The selected boarder is not part of this finalized billing cycle.',
        code: 'boarder-not-found',
      ),
    );
  }
}

class RoomBillingReportRow {
  const RoomBillingReportRow({
    required this.roomId,
    required this.roomName,
    required this.electricityCentavos,
    required this.waterCentavos,
    required this.rentCentavos,
  });

  final String roomId;
  final String roomName;
  final int electricityCentavos;
  final int waterCentavos;
  final int rentCentavos;

  int get totalCentavos => electricityCentavos + waterCentavos + rentCentavos;
}

class BoarderBillingReportRow {
  BoarderBillingReportRow({
    required this.statement,
    required this.account,
    required List<String> roomNames,
    required this.billableDays,
    required this.electricityEstimated,
    required List<SummerWaterReportDetail> summerWaterDetails,
    required List<PaymentRecord> payments,
  }) : roomNames = List.unmodifiable(roomNames),
       summerWaterDetails = List.unmodifiable(summerWaterDetails),
       payments = List.unmodifiable(payments);

  final BoarderMonthlyStatement statement;
  final BoarderBillAccount account;
  final List<String> roomNames;
  final int billableDays;
  final bool electricityEstimated;
  final List<SummerWaterReportDetail> summerWaterDetails;
  final List<PaymentRecord> payments;
}

class SummerWaterReportDetail {
  const SummerWaterReportDetail({
    required this.roomName,
    required this.electricityBasisValue,
    required this.basisPercentHundredths,
    required this.boarderWaterCentavos,
  });

  final String roomName;
  final int electricityBasisValue;

  /// Percentage stored as hundredths, so 7,500 means 75.00%.
  final int basisPercentHundredths;
  final int boarderWaterCentavos;
}
