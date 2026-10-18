import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/monthly_billing_models.dart';
import '../domain/monthly_billing_repository.dart';
import '../domain/room_billing_models.dart';
import '../domain/utility_billing_models.dart';

final monthlyBillingRepositoryProvider = Provider<MonthlyBillingRepository>((
  ref,
) {
  throw StateError(
    'monthlyBillingRepositoryProvider must be overridden at startup.',
  );
});

final utilityBillingBatchesProvider =
    StreamProvider.family<List<UtilityBillingBatch>, String>((ref, ownerId) {
      return ref
          .watch(monthlyBillingRepositoryProvider)
          .watchUtilityBillingBatches(ownerId);
    });

final utilityRoomBillAccountsProvider =
    StreamProvider.family<List<UtilityRoomBillAccount>, String>((ref, ownerId) {
      return ref
          .watch(monthlyBillingRepositoryProvider)
          .watchUtilityRoomAccounts(ownerId);
    });

final utilityRoomPaymentRecordsProvider =
    StreamProvider.family<List<UtilityRoomPaymentRecord>, String>((
      ref,
      ownerId,
    ) {
      return ref
          .watch(monthlyBillingRepositoryProvider)
          .watchUtilityRoomPayments(ownerId);
    });

final monthlyBillingCyclesProvider =
    StreamProvider.family<List<MonthlyBillingCycle>, String>((ref, ownerId) {
      return ref.watch(monthlyBillingRepositoryProvider).watchCycles(ownerId);
    });

final billingCycleControlsProvider =
    StreamProvider.family<List<BillingCycleControl>, String>((ref, ownerId) {
      return ref.watch(monthlyBillingRepositoryProvider).watchControls(ownerId);
    });

final boarderBillAccountsProvider =
    StreamProvider.family<List<BoarderBillAccount>, String>((ref, ownerId) {
      return ref.watch(monthlyBillingRepositoryProvider).watchAccounts(ownerId);
    });

final paymentRecordsProvider =
    StreamProvider.family<List<PaymentRecord>, String>((ref, ownerId) {
      return ref.watch(monthlyBillingRepositoryProvider).watchPayments(ownerId);
    });

final roomBillingCyclesProvider =
    StreamProvider.family<List<RoomBillingCycle>, String>((ref, ownerId) {
      return ref
          .watch(monthlyBillingRepositoryProvider)
          .watchRoomCycles(ownerId);
    });

final roomBillingControlsProvider =
    StreamProvider.family<List<BillingCycleControl>, String>((ref, ownerId) {
      return ref
          .watch(monthlyBillingRepositoryProvider)
          .watchRoomControls(ownerId);
    });

final roomBillAccountsProvider =
    StreamProvider.family<List<RoomBillAccount>, String>((ref, ownerId) {
      return ref
          .watch(monthlyBillingRepositoryProvider)
          .watchRoomAccounts(ownerId);
    });

final roomPaymentRecordsProvider =
    StreamProvider.family<List<RoomPaymentRecord>, String>((ref, ownerId) {
      return ref
          .watch(monthlyBillingRepositoryProvider)
          .watchRoomPayments(ownerId);
    });
