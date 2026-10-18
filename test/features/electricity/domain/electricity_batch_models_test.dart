import 'package:boarding_house_manager/features/electricity/domain/electricity_batch_models.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rate = 13186000;

  ElectricityReadingBatchEntry entry() => ElectricityReadingBatchEntry(
    roomId: 'room-201',
    roomName: '201',
    meterId: 'meter-201-1',
    sequence: 1,
    previousReadingId: 'reading-previous',
    previousReadingDate: BusinessDate(2026, 10, 1),
    previousReadingWh: 400000,
    targetReadingId: 'reading-batch',
    status: ElectricityBatchEntryStatus.pending,
    currentReadingWh: null,
    actualReadAt: null,
    readingId: null,
    consumptionWh: 0,
    chargeCentavos: 0,
    exclusionReason: null,
  );

  test('included draft calculates exact consumption and centavo charge', () {
    final updated = entry().withDraft(
      draft: ElectricityBatchEntryDraft(
        roomId: 'room-201',
        currentReadingWh: 432000,
        actualReadAt: DateTime(2026, 10, 14, 9, 30),
        exclusionReason: null,
      ),
      rateMicropesosPerKwh: rate,
    );

    expect(updated.status, ElectricityBatchEntryStatus.pending);
    expect(updated.consumptionWh, 32000);
    expect(updated.chargeCentavos, 42195);
  });

  test('explicit exclusion removes consumption and charge', () {
    final updated = entry().withDraft(
      draft: ElectricityBatchEntryDraft(
        roomId: 'room-201',
        currentReadingWh: 432000,
        actualReadAt: DateTime(2026, 10, 14, 9, 30),
        exclusionReason: 'Meter is inaccessible during repairs',
      ),
      rateMicropesosPerKwh: rate,
    );

    expect(updated.status, ElectricityBatchEntryStatus.excluded);
    expect(updated.currentReadingWh, isNull);
    expect(updated.consumptionWh, 0);
    expect(updated.chargeCentavos, 0);
    expect(updated.exclusionReason, 'Meter is inaccessible during repairs');
  });

  test('recorded entry cannot be rewritten through a draft update', () {
    final original = ElectricityReadingBatchEntry(
      roomId: 'room-201',
      roomName: '201',
      meterId: 'meter-201-1',
      sequence: 1,
      previousReadingId: 'reading-previous',
      previousReadingDate: BusinessDate(2026, 10, 1),
      previousReadingWh: 400000,
      targetReadingId: 'reading-batch',
      status: ElectricityBatchEntryStatus.recorded,
      currentReadingWh: 432000,
      actualReadAt: DateTime(2026, 10, 14, 9, 30),
      readingId: 'reading-batch',
      consumptionWh: 32000,
      chargeCentavos: 42195,
      exclusionReason: null,
    );

    final updated = original.withDraft(
      draft: const ElectricityBatchEntryDraft(
        roomId: 'room-201',
        currentReadingWh: 999000,
        actualReadAt: null,
        exclusionReason: null,
      ),
      rateMicropesosPerKwh: rate,
    );

    expect(identical(updated, original), isTrue);
  });
}
