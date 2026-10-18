import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/rent_models.dart';
import '../domain/rent_repository.dart';
import '../domain/rent_cycle_models.dart';

final rentRepositoryProvider = Provider<RentRepository>((ref) {
  throw StateError('rentRepositoryProvider must be overridden at startup.');
});

final rentSettingsProvider = StreamProvider.family<RentSettings, String>((
  ref,
  ownerId,
) {
  return ref.watch(rentRepositoryProvider).watchSettings(ownerId);
});

final rentBillingRecordsProvider =
    StreamProvider.family<List<RentBillingRecord>, String>((ref, ownerId) {
      return ref.watch(rentRepositoryProvider).watchBillingRecords(ownerId);
    });

final rentAgreementsProvider =
    StreamProvider.family<List<RentAgreement>, String>((ref, ownerId) {
      return ref.watch(rentRepositoryProvider).watchAgreements(ownerId);
    });

final rentCyclesProvider = StreamProvider.family<List<RentCycle>, String>((
  ref,
  ownerId,
) {
  return ref.watch(rentRepositoryProvider).watchCycles(ownerId);
});

final rentCycleControlsProvider =
    StreamProvider.family<List<RentCycleControl>, String>((ref, ownerId) {
      return ref.watch(rentRepositoryProvider).watchCycleControls(ownerId);
    });

final rentPaymentsProvider = StreamProvider.family<List<RentPayment>, String>((
  ref,
  ownerId,
) {
  return ref.watch(rentRepositoryProvider).watchPayments(ownerId);
});

final rentExtraStayResolutionsProvider =
    StreamProvider.family<List<RentExtraStayResolution>, String>((
      ref,
      ownerId,
    ) {
      return ref
          .watch(rentRepositoryProvider)
          .watchExtraStayResolutions(ownerId);
    });
