import 'dart:convert';

import 'package:boarding_house_manager/features/reports/application/billing_pdf_generator.dart';
import 'package:boarding_house_manager/features/reports/domain/billing_report_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../report_fixture.dart';

void main() {
  const generator = BillingPdfGenerator();

  test('uses stable privacy-safe report filenames', () {
    final report = reportFixture();

    expect(
      generator.fileName(
        report: report,
        type: BillingReportDocumentType.monthlySummary,
      ),
      'Mariano_Boarding_House_Bills_2026-10.pdf',
    );
    expect(
      generator.fileName(
        report: report,
        type: BillingReportDocumentType.individualBoarderStatement,
        boarderId: 'boarder-a',
      ),
      'Mariano_Boarding_House_Ana_Cruz_2026-10.pdf',
    );
  });

  test('generates valid A4 summary and individual PDF bytes', () async {
    final report = reportFixture();
    for (final type in BillingReportDocumentType.values) {
      final bytes = await generator.build(
        report: report,
        type: type,
        boarderId: type == BillingReportDocumentType.individualBoarderStatement
            ? 'boarder-a'
            : null,
      );

      expect(bytes, isNotEmpty);
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(2000));
    }
  });
}
