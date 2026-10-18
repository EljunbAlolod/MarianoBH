import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/water_models.dart';
import '../domain/water_batch_models.dart';
import '../domain/water_repository.dart';

final waterRepositoryProvider = Provider<WaterRepository>((ref) {
  throw StateError('waterRepositoryProvider must be overridden at startup.');
});

final waterSettingsProvider = StreamProvider.family<WaterSettings, String>((
  ref,
  ownerId,
) {
  return ref.watch(waterRepositoryProvider).watchSettings(ownerId);
});

final waterBillingRecordsProvider =
    StreamProvider.family<List<WaterBillingRecord>, String>((ref, ownerId) {
      return ref.watch(waterRepositoryProvider).watchBillingRecords(ownerId);
    });

final waterBillingBatchesProvider =
    StreamProvider.family<List<WaterBillingBatch>, String>((ref, ownerId) {
      return ref.watch(waterRepositoryProvider).watchBillingBatches(ownerId);
    });
