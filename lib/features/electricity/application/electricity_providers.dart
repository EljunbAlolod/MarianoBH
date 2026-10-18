import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/electricity_models.dart';
import '../domain/electricity_batch_models.dart';
import '../domain/electricity_repository.dart';

final electricityRepositoryProvider = Provider<ElectricityRepository>((ref) {
  throw StateError(
    'electricityRepositoryProvider must be overridden at startup.',
  );
});

final roomMeterStatesProvider =
    StreamProvider.family<List<RoomMeterState>, String>((ref, ownerId) {
      return ref
          .watch(electricityRepositoryProvider)
          .watchRoomMeterStates(ownerId);
    });

final electricityMetersProvider =
    StreamProvider.family<List<ElectricityMeter>, String>((ref, ownerId) {
      return ref.watch(electricityRepositoryProvider).watchMeters(ownerId);
    });

final meterReadingsProvider = StreamProvider.family<List<MeterReading>, String>(
  (ref, ownerId) {
    return ref.watch(electricityRepositoryProvider).watchReadings(ownerId);
  },
);

final meterReadingCorrectionsProvider =
    StreamProvider.family<List<MeterReadingCorrection>, String>((ref, ownerId) {
      return ref
          .watch(electricityRepositoryProvider)
          .watchReadingCorrections(ownerId);
    });

final electricityBillingRecordsProvider =
    StreamProvider.family<List<ElectricityBillingRecord>, String>((
      ref,
      ownerId,
    ) {
      return ref
          .watch(electricityRepositoryProvider)
          .watchBillingRecords(ownerId);
    });

final electricityReadingBatchesProvider =
    StreamProvider.family<List<ElectricityReadingBatch>, String>((
      ref,
      ownerId,
    ) {
      return ref
          .watch(electricityRepositoryProvider)
          .watchReadingBatches(ownerId);
    });
