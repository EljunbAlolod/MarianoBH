import 'dart:convert';

import 'package:boarding_house_manager/features/billing/domain/monthly_billing_models.dart';
import 'package:boarding_house_manager/features/billing/domain/utility_billing_models.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/reports/application/utility_billing_pdf_generator.dart';
import 'package:boarding_house_manager/features/water/domain/water_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const generator = UtilityBillingPdfGenerator();

  test('uses stable room utility PDF filenames', () {
    final batch = _batch();
    expect(
      generator.fileName(
        houseName: 'Mariano Boarding House',
        batch: batch,
        type: UtilityBillingPdfDocumentType.summary,
      ),
      'Mariano_Boarding_House_UB_2026_07_001_Summary.pdf',
    );
    expect(
      generator.fileName(
        houseName: 'Mariano Boarding House',
        batch: batch,
        type: UtilityBillingPdfDocumentType.individualRoomStatement,
        roomName: 'Room 201',
      ),
      'Mariano_Boarding_House_UB_2026_07_001_Room_201.pdf',
    );
  });

  test('generates summary and room PDFs from the finalized snapshot', () async {
    final batch = _batch();
    final account = _account();
    for (final type in UtilityBillingPdfDocumentType.values) {
      final bytes = await generator.build(
        houseName: 'Mariano Boarding House',
        batch: batch,
        accounts: [account],
        payments: [_payment()],
        type: type,
        roomId: type == UtilityBillingPdfDocumentType.individualRoomStatement
            ? 'room-a'
            : null,
      );

      expect(bytes, isNotEmpty);
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(1800));
    }
  });

  test('rejects accounts that do not match snapshot totals', () async {
    await expectLater(
      generator.build(
        houseName: 'Mariano Boarding House',
        batch: _batch(),
        accounts: [
          UtilityRoomBillAccount(
            accountId: 'utility-bill-1_room-a',
            billingBatchId: 'utility-bill-1',
            roomId: 'room-a',
            roomName: 'Room 201',
            totalChargesCentavos: 1,
            totalPaidCentavos: 0,
            createdAt: DateTime.utc(2026, 7, 5),
            updatedAt: DateTime.utc(2026, 7, 5),
          ),
        ],
        payments: const [],
        type: UtilityBillingPdfDocumentType.summary,
      ),
      throwsA(
        isA<UtilityBillingPdfException>().having(
          (error) => error.code,
          'code',
          'account-snapshot-mismatch',
        ),
      ),
    );
  });
}

UtilityBillingBatch _batch() {
  final createdAt = DateTime.utc(2026, 7, 5);
  return UtilityBillingBatch(
    billingBatchId: 'utility-bill-1',
    billingBatchReference: 'UB-2026-07-001',
    status: UtilityBillingBatchStatus.finalized,
    issuedOn: BusinessDate(2026, 7, 5),
    electricityBatchId: 'electricity-july',
    electricityBatchReference: 'EB-2026-07-001',
    electricityMeasurementStart: BusinessDate(2026, 6, 10),
    electricityMeasurementEnd: BusinessDate(2026, 7, 1),
    electricityRateMicropesosPerKwh: 10000000,
    sourceReadingIds: const ['reading-1'],
    waterBatchId: 'water-may',
    waterBatchReference: 'WB-2026-05-001',
    waterPeriodStart: BusinessDate(2026, 5, 1),
    waterPeriodEndExclusive: BusinessDate(2026, 6, 1),
    waterReceiptDate: BusinessDate(2026, 6, 5),
    waterMethod: WaterBillingMethod.personDays,
    waterSummerBasis: SummerElectricityBasis.roomElectricityCharge,
    waterReferenceElectricityBatchId: null,
    waterReferenceElectricityBatchReference: null,
    associationMismatchConfirmed: false,
    electricityTotalCentavos: 120000,
    waterTotalCentavos: 300000,
    adjustmentTotalCentavos: 0,
    totalBilledCentavos: 420000,
    totalUnallocatedCentavos: 0,
    statements: const [
      RoomUtilityBillStatement(
        roomId: 'room-a',
        roomName: 'Room 201',
        electricityCentavos: 120000,
        waterCentavos: 300000,
        adjustmentCentavos: 0,
        totalCentavos: 420000,
      ),
    ],
    warnings: const [],
    createdAt: createdAt,
    voidReason: null,
    voidedAt: null,
  );
}

UtilityRoomBillAccount _account() {
  final createdAt = DateTime.utc(2026, 7, 5);
  return UtilityRoomBillAccount(
    accountId: 'utility-bill-1_room-a',
    billingBatchId: 'utility-bill-1',
    roomId: 'room-a',
    roomName: 'Room 201',
    totalChargesCentavos: 420000,
    totalPaidCentavos: 100000,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

UtilityRoomPaymentRecord _payment() => UtilityRoomPaymentRecord(
  paymentId: 'payment-1',
  billingBatchId: 'utility-bill-1',
  accountId: 'utility-bill-1_room-a',
  roomId: 'room-a',
  roomName: 'Room 201',
  amountCentavos: 100000,
  paymentDate: BusinessDate(2026, 7, 5),
  method: PaymentMethod.gcash,
  notes: 'Deposit',
  recordedAt: DateTime.utc(2026, 7, 5),
);
