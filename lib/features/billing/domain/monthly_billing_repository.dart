import '../../property_management/domain/business_date.dart';
import 'monthly_billing_models.dart';
import 'room_billing_models.dart';
import 'utility_billing_models.dart';

abstract class MonthlyBillingRepository {
  Stream<List<UtilityBillingBatch>> watchUtilityBillingBatches(String ownerId);

  Stream<List<UtilityRoomBillAccount>> watchUtilityRoomAccounts(String ownerId);

  Stream<List<UtilityRoomPaymentRecord>> watchUtilityRoomPayments(
    String ownerId,
  );

  Stream<List<MonthlyBillingCycle>> watchCycles(String ownerId);

  Stream<List<BillingCycleControl>> watchControls(String ownerId);

  Stream<List<BoarderBillAccount>> watchAccounts(String ownerId);

  Stream<List<PaymentRecord>> watchPayments(String ownerId);

  Stream<List<RoomBillingCycle>> watchRoomCycles(String ownerId);

  Stream<List<BillingCycleControl>> watchRoomControls(String ownerId);

  Stream<List<RoomBillAccount>> watchRoomAccounts(String ownerId);

  Stream<List<RoomPaymentRecord>> watchRoomPayments(String ownerId);

  Future<String> finalizeCycle({
    required String ownerId,
    required MonthlyBillingResult result,
  });

  Future<String> finalizeRoomCycle({
    required String ownerId,
    required RoomBillingResult result,
  });

  Future<String> finalizeUtilityBillingBatch({
    required String ownerId,
    required UtilityBillingResult result,
  });

  Future<void> voidCycle({
    required String ownerId,
    required String billingCycleId,
    required String reason,
  });

  Future<void> voidRoomCycle({
    required String ownerId,
    required String billingCycleId,
    required String reason,
  });

  Future<String> recordPayment({
    required String ownerId,
    required String billingCycleId,
    required String boarderId,
    required int amountCentavos,
    required BusinessDate paymentDate,
    required PaymentMethod method,
    String? notes,
  });

  Future<String> recordRoomPayment({
    required String ownerId,
    required String billingCycleId,
    required String roomId,
    required int amountCentavos,
    required BusinessDate paymentDate,
    required PaymentMethod method,
    String? notes,
  });

  Future<String> recordUtilityRoomPayment({
    required String ownerId,
    required String billingBatchId,
    required String roomId,
    required int amountCentavos,
    required BusinessDate paymentDate,
    required PaymentMethod method,
    String? notes,
  });
}

class MonthlyBillingRepositoryException implements Exception {
  const MonthlyBillingRepositoryException(
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
  String toString() => 'MonthlyBillingRepositoryException($code): $message';
}
