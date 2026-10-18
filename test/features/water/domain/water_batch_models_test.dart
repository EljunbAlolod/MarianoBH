import 'package:boarding_house_manager/features/electricity/domain/electricity_batch_models.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/water/domain/water_batch_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('May water can deliberately reference a June electricity batch', () {
    final batch = _electricityBatch(
      start: BusinessDate(2026, 5, 10),
      end: BusinessDate(2026, 6, 10),
    );

    expect(
      waterAndElectricityPeriodsDiffer(
        waterStart: BusinessDate(2026, 5, 1),
        waterEndExclusive: BusinessDate(2026, 6, 1),
        electricityBatch: batch,
      ),
      isTrue,
    );

    final adapted = electricityAllocationRecordFromBatch(
      batch: batch,
      waterStart: BusinessDate(2026, 5, 1),
      waterEndExclusive: BusinessDate(2026, 6, 1),
    );
    expect(adapted.billingRecordId, batch.batchId);
    expect(adapted.startDate, BusinessDate(2026, 5, 1));
    expect(adapted.endDateExclusive, BusinessDate(2026, 6, 1));
    expect(adapted.totalChargeCentavos, 120000);
    expect(adapted.totalConsumptionWh, 12000);
    expect(adapted.sourceReadingIds, ['reading-1']);
  });

  test(
    'matching water and electricity boundaries need no mismatch warning',
    () {
      final batch = _electricityBatch(
        start: BusinessDate(2026, 5, 1),
        end: BusinessDate(2026, 6, 1),
      );
      expect(
        waterAndElectricityPeriodsDiffer(
          waterStart: BusinessDate(2026, 5, 1),
          waterEndExclusive: BusinessDate(2026, 6, 1),
          electricityBatch: batch,
        ),
        isFalse,
      );
    },
  );
}

ElectricityReadingBatch _electricityBatch({
  required BusinessDate start,
  required BusinessDate end,
}) {
  final now = DateTime.utc(2026, 6, 10);
  return ElectricityReadingBatch(
    batchId: 'electricity-batch-1',
    batchReference: 'EB-2026-06-ABC123',
    status: ElectricityReadingBatchStatus.finalized,
    effectiveDate: end,
    effectiveAt: now,
    rateMicropesosPerKwh: 10000000,
    entries: [
      ElectricityReadingBatchEntry(
        roomId: 'room-1',
        roomName: '201',
        meterId: 'meter-1',
        sequence: 1,
        previousReadingId: 'reading-0',
        previousReadingDate: start,
        previousReadingWh: 100000,
        targetReadingId: 'reading-1',
        status: ElectricityBatchEntryStatus.recorded,
        currentReadingWh: 112000,
        actualReadAt: now,
        readingId: 'reading-1',
        consumptionWh: 12000,
        chargeCentavos: 120000,
        exclusionReason: null,
      ),
    ],
    roomCount: 1,
    pendingCount: 0,
    recordedCount: 1,
    excludedCount: 0,
    totalConsumptionWh: 12000,
    totalChargeCentavos: 120000,
    version: 2,
    lastLinkId: 'reading-1',
    createdAt: now,
    updatedAt: now,
    finalizedAt: now,
    usedAt: null,
    voidReason: null,
    voidedAt: null,
  );
}
