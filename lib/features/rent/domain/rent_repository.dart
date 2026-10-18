import 'rent_models.dart';
import '../../property_management/domain/business_date.dart';
import 'rent_cycle_models.dart';

abstract class RentRepository {
  Stream<List<RentAgreement>> watchAgreements(String ownerId);

  Stream<List<RentCycle>> watchCycles(String ownerId);

  Stream<List<RentCycleControl>> watchCycleControls(String ownerId);

  Stream<List<RentPayment>> watchPayments(String ownerId);

  Stream<List<RentExtraStayResolution>> watchExtraStayResolutions(
    String ownerId,
  );

  Stream<RentSettings> watchSettings(String ownerId);

  Stream<List<RentBillingRecord>> watchBillingRecords(String ownerId);

  Future<void> saveSettings({
    required String ownerId,
    required RentSettings settings,
  });

  Future<String> recordBillingSnapshot({
    required String ownerId,
    required RentCalculationResult result,
    bool roomBillingSource = false,
  });

  Future<String> createAgreement({
    required String ownerId,
    required String occupancyId,
    required int monthlyRentCentavos,
  });

  Future<int> createDueCycles({
    required String ownerId,
    required RentAgreement agreement,
    required BusinessDate throughDate,
  });

  Future<String> recordPayment({
    required String ownerId,
    required String cycleId,
    required int expectedPaidCentavos,
    required int amountCentavos,
    required BusinessDate receivedOn,
    String? note,
  });

  Future<String> resolveExtraStay({
    required String ownerId,
    required RentAgreement agreement,
    required BusinessDate moveOutDate,
    required ExtraStayDecision decision,
    required int amountCentavos,
    required String note,
  });
}

class RentRepositoryException implements Exception {
  const RentRepositoryException(
    this.message, {
    required this.code,
    this.isOffline = false,
    this.isConflict = false,
  });

  final String message;
  final String code;
  final bool isOffline;
  final bool isConflict;

  @override
  String toString() => 'RentRepositoryException($code): $message';
}
