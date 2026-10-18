import '../../property_management/domain/business_date.dart';
import 'electricity_models.dart';
import 'electricity_batch_models.dart';

abstract class ElectricityRepository {
  Stream<List<ElectricityReadingBatch>> watchReadingBatches(String ownerId);

  Stream<List<RoomMeterState>> watchRoomMeterStates(String ownerId);

  Stream<List<ElectricityMeter>> watchMeters(String ownerId);

  Stream<List<MeterReading>> watchReadings(String ownerId);

  Stream<List<MeterReadingCorrection>> watchReadingCorrections(String ownerId);

  Stream<List<ElectricityBillingRecord>> watchBillingRecords(String ownerId);

  Future<void> initializeMeter({
    required String ownerId,
    required String roomId,
    required BusinessDate openingDate,
    required int openingReadingWh,
    String? note,
  });

  Future<void> recordReading({
    required String ownerId,
    required String roomId,
    required BusinessDate readingDate,
    required int readingWh,
    MeterReadingKind kind = MeterReadingKind.regular,
    String? note,
  });

  Future<void> transitionMeter({
    required String ownerId,
    required String roomId,
    required BusinessDate transitionDate,
    required int closingReadingWh,
    required int newOpeningReadingWh,
    required ElectricityMeterStartKind startKind,
    required String reason,
  });

  Future<void> correctLatestReading({
    required String ownerId,
    required String roomId,
    required String readingId,
    required BusinessDate expectedReadingDate,
    required int expectedReadingWh,
    required int expectedCorrectionCount,
    required BusinessDate correctedReadingDate,
    required int correctedReadingWh,
    required String reason,
  });

  Future<void> insertHistoricalReading({
    required String ownerId,
    required String roomId,
    required String meterId,
    required String predecessorReadingId,
    required BusinessDate expectedPredecessorDate,
    required int expectedPredecessorWh,
    required String successorReadingId,
    required BusinessDate expectedSuccessorDate,
    required int expectedSuccessorWh,
    required BusinessDate readingDate,
    required int readingWh,
    required String reason,
  });

  Future<String> recordBillingSnapshot({
    required String ownerId,
    required ElectricityCalculationResult result,
    bool roomBillingSource = false,
  });

  Future<String> createReadingBatchDraft({
    required String ownerId,
    required BusinessDate effectiveDate,
    required DateTime effectiveAt,
    required int rateMicropesosPerKwh,
    required List<ElectricityBatchRoomSource> rooms,
  });

  Future<void> updateReadingBatchDraft({
    required String ownerId,
    required String batchId,
    required int expectedVersion,
    required BusinessDate effectiveDate,
    required DateTime effectiveAt,
    required int rateMicropesosPerKwh,
    required List<ElectricityBatchEntryDraft> entries,
  });

  Future<void> finalizeReadingBatch({
    required String ownerId,
    required String batchId,
  });

  Future<void> voidReadingBatch({
    required String ownerId,
    required String batchId,
    required String reason,
  });
}

class ElectricityRepositoryException implements Exception {
  const ElectricityRepositoryException(
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
  String toString() => 'ElectricityRepositoryException($code): $message';
}
