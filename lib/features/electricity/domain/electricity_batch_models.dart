import '../../property_management/domain/business_date.dart';
import 'electricity_values.dart';

enum ElectricityReadingBatchStatus { draft, finalized, usedInBilling, voided }

enum ElectricityBatchEntryStatus { pending, recorded, excluded }

class ElectricityBatchRoomSource {
  const ElectricityBatchRoomSource({
    required this.roomId,
    required this.roomName,
    required this.meterId,
    required this.sequence,
    required this.previousReadingId,
    required this.previousReadingDate,
    required this.previousReadingWh,
  });

  final String roomId;
  final String roomName;
  final String meterId;
  final int sequence;
  final String previousReadingId;
  final BusinessDate previousReadingDate;
  final int previousReadingWh;
}

class ElectricityBatchEntryDraft {
  const ElectricityBatchEntryDraft({
    required this.roomId,
    required this.currentReadingWh,
    required this.actualReadAt,
    required this.exclusionReason,
  });

  final String roomId;
  final int? currentReadingWh;
  final DateTime? actualReadAt;
  final String? exclusionReason;

  bool get isExcluded => exclusionReason?.trim().isNotEmpty == true;
}

class ElectricityReadingBatchEntry {
  const ElectricityReadingBatchEntry({
    required this.roomId,
    required this.roomName,
    required this.meterId,
    required this.sequence,
    required this.previousReadingId,
    required this.previousReadingDate,
    required this.previousReadingWh,
    required this.targetReadingId,
    required this.status,
    required this.currentReadingWh,
    required this.actualReadAt,
    required this.readingId,
    required this.consumptionWh,
    required this.chargeCentavos,
    required this.exclusionReason,
  });

  final String roomId;
  final String roomName;
  final String meterId;
  final int sequence;
  final String previousReadingId;
  final BusinessDate previousReadingDate;
  final int previousReadingWh;
  final String targetReadingId;
  final ElectricityBatchEntryStatus status;
  final int? currentReadingWh;
  final DateTime? actualReadAt;
  final String? readingId;
  final int consumptionWh;
  final int chargeCentavos;
  final String? exclusionReason;

  bool get isIncluded => status != ElectricityBatchEntryStatus.excluded;
  bool get isComplete => status != ElectricityBatchEntryStatus.pending;

  ElectricityReadingBatchEntry withDraft({
    required ElectricityBatchEntryDraft draft,
    required int rateMicropesosPerKwh,
  }) {
    if (status == ElectricityBatchEntryStatus.recorded) return this;
    final reason = draft.exclusionReason?.trim();
    if (reason?.isNotEmpty == true) {
      return ElectricityReadingBatchEntry(
        roomId: roomId,
        roomName: roomName,
        meterId: meterId,
        sequence: sequence,
        previousReadingId: previousReadingId,
        previousReadingDate: previousReadingDate,
        previousReadingWh: previousReadingWh,
        targetReadingId: targetReadingId,
        status: ElectricityBatchEntryStatus.excluded,
        currentReadingWh: null,
        actualReadAt: draft.actualReadAt,
        readingId: null,
        consumptionWh: 0,
        chargeCentavos: 0,
        exclusionReason: reason,
      );
    }
    final current = draft.currentReadingWh;
    final consumption = current == null ? 0 : current - previousReadingWh;
    return ElectricityReadingBatchEntry(
      roomId: roomId,
      roomName: roomName,
      meterId: meterId,
      sequence: sequence,
      previousReadingId: previousReadingId,
      previousReadingDate: previousReadingDate,
      previousReadingWh: previousReadingWh,
      targetReadingId: targetReadingId,
      status: ElectricityBatchEntryStatus.pending,
      currentReadingWh: current,
      actualReadAt: draft.actualReadAt,
      readingId: null,
      consumptionWh: consumption < 0 ? 0 : consumption,
      chargeCentavos: consumption < 0 || current == null
          ? 0
          : ElectricityValues.chargeCentavos(
              consumptionWh: consumption,
              rateMicropesosPerKwh: rateMicropesosPerKwh,
            ),
      exclusionReason: null,
    );
  }
}

class ElectricityReadingBatch {
  ElectricityReadingBatch({
    required this.batchId,
    required this.batchReference,
    required this.status,
    required this.effectiveDate,
    required this.effectiveAt,
    required this.rateMicropesosPerKwh,
    required List<ElectricityReadingBatchEntry> entries,
    required this.roomCount,
    required this.pendingCount,
    required this.recordedCount,
    required this.excludedCount,
    required this.totalConsumptionWh,
    required this.totalChargeCentavos,
    required this.version,
    required this.lastLinkId,
    required this.createdAt,
    required this.updatedAt,
    required this.finalizedAt,
    required this.usedAt,
    required this.voidReason,
    required this.voidedAt,
  }) : entries = List.unmodifiable(entries);

  final String batchId;
  final String batchReference;
  final ElectricityReadingBatchStatus status;
  final BusinessDate effectiveDate;
  final DateTime effectiveAt;
  final int rateMicropesosPerKwh;
  final List<ElectricityReadingBatchEntry> entries;
  final int roomCount;
  final int pendingCount;
  final int recordedCount;
  final int excludedCount;
  final int totalConsumptionWh;
  final int totalChargeCentavos;
  final int version;
  final String? lastLinkId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? finalizedAt;
  final DateTime? usedAt;
  final String? voidReason;
  final DateTime? voidedAt;

  bool get canEdit => status == ElectricityReadingBatchStatus.draft;
  bool get canVoid => status == ElectricityReadingBatchStatus.finalized;
}
