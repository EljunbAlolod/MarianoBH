import 'package:boarding_house_manager/features/reports/domain/billing_report_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../report_fixture.dart';

void main() {
  test('reconciles immutable sources into room and boarder report rows', () {
    final report = reportFixture();

    expect(report.rooms, hasLength(2));
    expect(report.rooms.first.roomName, 'Room A');
    expect(report.rooms.first.totalCentavos, 260000);
    expect(report.boarders, hasLength(2));
    expect(report.boarders.first.statement.boarderName, 'Ana Cruz');
    expect(report.boarders.first.billableDays, 16);
    expect(report.boarders.first.electricityEstimated, isTrue);
    expect(
      report.boarders.first.summerWaterDetails.single.basisPercentHundredths,
      6667,
    );
    expect(report.boarders.first.payments.single.amountCentavos, 100000);
  });

  test('rejects a source whose totals differ from the finalized cycle', () {
    expect(
      () => reportFixture(electricityTotal: 89999),
      throwsA(
        isA<BillingReportException>().having(
          (error) => error.code,
          'code',
          'source-snapshot-mismatch',
        ),
      ),
    );
  });
}
