import '../../property_management/domain/business_date.dart';
import 'water_models.dart';
import 'water_batch_models.dart';

abstract class WaterRepository {
  Stream<List<WaterBillingBatch>> watchBillingBatches(String ownerId);

  Stream<WaterSettings> watchSettings(String ownerId);

  Stream<List<WaterBillingRecord>> watchBillingRecords(String ownerId);

  Future<void> saveSettings({
    required String ownerId,
    required WaterSettings settings,
  });

  Future<String> recordBillingSnapshot({
    required String ownerId,
    required WaterCalculationResult result,
  });

  Future<String> createBillingBatchDraft({
    required String ownerId,
    required BusinessDate receiptDate,
    required WaterCalculationResult result,
    required String? electricityBatchId,
    required bool referencePeriodMismatchConfirmed,
    required String? referenceExplanation,
    required String? notes,
  });

  Future<void> updateBillingBatchDraft({
    required String ownerId,
    required String batchId,
    required int expectedVersion,
    required BusinessDate receiptDate,
    required WaterCalculationResult result,
    required String? electricityBatchId,
    required bool referencePeriodMismatchConfirmed,
    required String? referenceExplanation,
    required String? notes,
  });

  Future<void> finalizeBillingBatch({
    required String ownerId,
    required String batchId,
    int? expectedVersion,
  });

  Future<void> voidBillingBatch({
    required String ownerId,
    required String batchId,
    required String reason,
  });
}

class WaterRepositoryException implements Exception {
  const WaterRepositoryException(
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
  String toString() => 'WaterRepositoryException($code): $message';
}
