import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../billing/domain/monthly_billing_models.dart';
import '../../electricity/domain/electricity_values.dart';
import '../../property_management/domain/business_date.dart';
import '../../water/domain/water_models.dart';
import '../domain/billing_report_models.dart';

class BillingPdfGenerator {
  const BillingPdfGenerator();

  PdfPageFormat pageFormat(BillingReportDocumentType type) =>
      type == BillingReportDocumentType.monthlySummary
      ? PdfPageFormat.a4.landscape
      : PdfPageFormat.a4;

  String fileName({
    required BillingReportSnapshot report,
    required BillingReportDocumentType type,
    String? boarderId,
  }) {
    final house = _filePart(report.houseName, fallback: 'BoardingHouse');
    final period =
        '${report.cycle.startDate.year.toString().padLeft(4, '0')}-${report.cycle.startDate.month.toString().padLeft(2, '0')}';
    return switch (type) {
      BillingReportDocumentType.monthlySummary => '${house}_Bills_$period.pdf',
      BillingReportDocumentType.combinedBoarderStatements =>
        '${house}_Statements_$period.pdf',
      BillingReportDocumentType.individualBoarderStatement =>
        '${house}_${_filePart(report.boarder(boarderId!).statement.boarderName, fallback: 'Boarder')}_$period.pdf',
    };
  }

  Future<Uint8List> build({
    required BillingReportSnapshot report,
    required BillingReportDocumentType type,
    String? boarderId,
  }) async {
    if (type == BillingReportDocumentType.individualBoarderStatement &&
        boarderId == null) {
      throw const BillingReportException(
        'Select a boarder before generating an individual statement.',
        code: 'boarder-required',
      );
    }
    final document = pw.Document(
      title: _documentTitle(report, type, boarderId),
      author: report.houseName,
      creator: 'Boarding House Manager',
      subject: _period(report),
    );
    switch (type) {
      case BillingReportDocumentType.monthlySummary:
        document.addPage(_summary(report));
      case BillingReportDocumentType.combinedBoarderStatements:
        document.addPage(_statements(report, report.boarders));
      case BillingReportDocumentType.individualBoarderStatement:
        document.addPage(_statements(report, [report.boarder(boarderId!)]));
    }
    return document.save();
  }

  pw.MultiPage _summary(BillingReportSnapshot report) {
    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 28),
      header: (context) =>
          _pageHeader(context, report, 'Monthly boarding house summary'),
      footer: (context) => _pageFooter(context, report),
      build: (context) => [
        _statusBanner(report),
        pw.SizedBox(height: 12),
        _metadata([
          ('Billing period', _period(report)),
          ('Date generated', _date(report.generatedOn)),
          ('Water allocation', _waterMethod(report)),
          (
            'Electricity rate',
            'PHP ${ElectricityValues.formatMicropesosAsPesosPerKwh(report.electricity.rateMicropesosPerKwh)} / kWh',
          ),
          ('Original water bill', _peso(report.water.waterBillCentavos)),
          ('Cycle version', report.cycle.version.toString()),
        ], columns: 3),
        pw.SizedBox(height: 16),
        _sectionTitle('Billing totals'),
        pw.SizedBox(height: 6),
        _totalsTable(report),
        pw.SizedBox(height: 16),
        _sectionTitle('Rooms and allocated charges'),
        pw.SizedBox(height: 6),
        if (report.rooms.isEmpty)
          _notice('No room-level allocations were recorded for this cycle.')
        else
          _table(
            headers: const [
              'Room',
              'Electricity',
              'Water',
              'Rent',
              'Allocated total',
            ],
            data: report.rooms
                .map(
                  (room) => [
                    room.roomName,
                    _peso(room.electricityCentavos),
                    _peso(room.waterCentavos),
                    _peso(room.rentCentavos),
                    _peso(room.totalCentavos),
                  ],
                )
                .toList(growable: false),
            numericColumns: const {1, 2, 3, 4},
          ),
        if (report.cycle.rentAdjustmentCentavos != 0) ...[
          pw.SizedBox(height: 5),
          pw.Text(
            'Boarder-specific rent adjustments are listed in the boarder table and are not assigned to a room.',
            style: _smallMuted,
          ),
        ],
        pw.SizedBox(height: 16),
        _sectionTitle('Boarders and final amounts'),
        pw.SizedBox(height: 6),
        _table(
          headers: const [
            'Boarder',
            'Room(s)',
            'Electricity',
            'Water',
            'Rent',
            'Adjustments',
            'Billed',
            'Paid',
            'Outstanding',
          ],
          data: report.boarders
              .map(
                (boarder) => [
                  boarder.statement.boarderName,
                  boarder.roomNames.join(', '),
                  _peso(boarder.statement.electricityCentavos),
                  _peso(boarder.statement.waterCentavos),
                  _peso(boarder.statement.rentCentavos),
                  _signedPeso(boarder.statement.rentAdjustmentCentavos),
                  _peso(boarder.account.totalChargesCentavos),
                  _peso(boarder.account.totalPaidCentavos),
                  _peso(boarder.account.outstandingCentavos),
                ],
              )
              .toList(growable: false),
          numericColumns: const {2, 3, 4, 5, 6, 7, 8},
          compact: true,
        ),
        ..._notes(report),
      ],
    );
  }

  pw.MultiPage _statements(
    BillingReportSnapshot report,
    List<BoarderBillingReportRow> boarders,
  ) {
    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(38, 32, 38, 32),
      header: (context) =>
          _pageHeader(context, report, 'Individual billing statement'),
      footer: (context) => _pageFooter(context, report),
      build: (context) {
        final widgets = <pw.Widget>[];
        for (var index = 0; index < boarders.length; index++) {
          if (index > 0) widgets.add(pw.NewPage());
          widgets.addAll(_boarderStatement(report, boarders[index]));
        }
        return widgets;
      },
    );
  }

  List<pw.Widget> _boarderStatement(
    BillingReportSnapshot report,
    BoarderBillingReportRow boarder,
  ) {
    final statement = boarder.statement;
    final account = boarder.account;
    return [
      _statusBanner(report, boarder: boarder),
      pw.SizedBox(height: 14),
      pw.Text(
        statement.boarderName,
        style: pw.TextStyle(
          fontSize: 20,
          fontWeight: pw.FontWeight.bold,
          color: _ink,
        ),
      ),
      pw.SizedBox(height: 8),
      _metadata([
        ('Room(s)', boarder.roomNames.join(', ')),
        ('Billing period', _period(report)),
        (
          'Occupancy dates',
          '${_period(report)} overlap; ${boarder.billableDays} ${boarder.billableDays == 1 ? 'billable day' : 'billable days'} in the finalized record',
        ),
        ('Statement version', report.cycle.version.toString()),
      ], columns: 2),
      pw.SizedBox(height: 16),
      _sectionTitle('Charge breakdown'),
      pw.SizedBox(height: 6),
      _keyValueTable([
        ('Rent', _peso(statement.rentCentavos)),
        ('Rent adjustments', _signedPeso(statement.rentAdjustmentCentavos)),
        (
          boarder.electricityEstimated
              ? 'Electricity (occupancy-based estimate)'
              : 'Electricity',
          _peso(statement.electricityCentavos),
        ),
        ('Water', _peso(statement.waterCentavos)),
        ('Current bill total', _peso(statement.currentChargesCentavos)),
        if (statement.previousBalanceCentavos > 0)
          (
            'Previous unpaid balance (pay on original bill)',
            _peso(statement.previousBalanceCentavos),
          ),
        if (statement.previousBalanceCentavos > 0)
          (
            'Total due at finalization',
            _peso(statement.amountDueAtFinalizationCentavos),
          ),
      ]),
      if (boarder.summerWaterDetails.isNotEmpty) ...[
        pw.SizedBox(height: 16),
        _sectionTitle('Summer water allocation'),
        pw.SizedBox(height: 6),
        pw.Text(
          'The electricity value determines each room\'s percentage of the water bill; it is not added again as a water charge.',
          style: _smallMuted,
        ),
        pw.SizedBox(height: 6),
        _table(
          headers: const [
            'Room',
            'Electricity basis',
            'Room percentage',
            'Your water share',
          ],
          data: boarder.summerWaterDetails
              .map(
                (detail) => [
                  detail.roomName,
                  _waterBasis(report.water, detail.electricityBasisValue),
                  _percent(detail.basisPercentHundredths),
                  _peso(detail.boarderWaterCentavos),
                ],
              )
              .toList(growable: false),
          numericColumns: const {1, 2, 3},
        ),
      ],
      pw.SizedBox(height: 16),
      _sectionTitle('Payments and balance'),
      pw.SizedBox(height: 6),
      _keyValueTable([
        ('Payments received on this bill', _peso(account.totalPaidCentavos)),
        ('Outstanding balance', _peso(account.outstandingCentavos)),
        ('Payment status', _paymentStatus(account.status)),
      ]),
      if (boarder.payments.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        _table(
          headers: const ['Payment date', 'Method', 'Amount', 'Notes'],
          data: boarder.payments
              .map(
                (payment) => [
                  _date(payment.paymentDate),
                  _paymentMethod(payment.method),
                  _peso(payment.amountCentavos),
                  payment.notes ?? '',
                ],
              )
              .toList(growable: false),
          numericColumns: const {2},
        ),
      ] else ...[
        pw.SizedBox(height: 8),
        _notice('No payments have been recorded for this bill.'),
      ],
      if (boarder.electricityEstimated) ...[
        pw.SizedBox(height: 14),
        _notice(
          'Electricity sharing includes an occupancy-based estimate because boundary meter readings were not available.',
        ),
      ],
      pw.SizedBox(height: 18),
      pw.Text(
        'Generated from finalized billing snapshot ${report.cycle.billingCycleId}. Charges cannot be recalculated from newer settings.',
        style: _smallMuted,
      ),
    ];
  }

  pw.Widget _pageHeader(
    pw.Context context,
    BillingReportSnapshot report,
    String title,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 9),
      margin: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _teal, width: 1.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                report.houseName,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: _teal,
                ),
              ),
              pw.Text(title, style: _smallMuted),
            ],
          ),
          pw.Text(_period(report), style: _smallMuted),
        ],
      ),
    );
  }

  pw.Widget _pageFooter(pw.Context context, BillingReportSnapshot report) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 7),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _line)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated ${_date(report.generatedOn)} - Boarding House Manager',
            style: _tinyMuted,
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: _tinyMuted,
          ),
        ],
      ),
    );
  }

  pw.Widget _statusBanner(
    BillingReportSnapshot report, {
    BoarderBillingReportRow? boarder,
  }) {
    final voided = report.control.state == BillingCycleState.voided;
    final status = voided
        ? 'VOIDED - ${report.control.voidReason ?? 'Documented correction'}'
        : boarder == null
        ? _paymentStatus(report.control.paymentStatus).toUpperCase()
        : _paymentStatus(boarder.account.status).toUpperCase();
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: pw.BoxDecoration(
        color: voided ? PdfColors.red50 : _tealLight,
        border: pw.Border.all(color: voided ? PdfColors.red700 : _teal),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(
        status,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: voided ? PdfColors.red900 : _tealDark,
        ),
      ),
    );
  }

  pw.Widget _metadata(List<(String, String)> values, {required int columns}) {
    final rows = <pw.TableRow>[];
    for (var index = 0; index < values.length; index += columns) {
      rows.add(
        pw.TableRow(
          children: [
            for (var cell = 0; cell < columns; cell++)
              if (index + cell < values.length)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(right: 12, bottom: 8),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(values[index + cell].$1, style: _tinyMuted),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        values[index + cell].$2,
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: _ink,
                        ),
                      ),
                    ],
                  ),
                )
              else
                pw.SizedBox(),
          ],
        ),
      );
    }
    return pw.Table(children: rows);
  }

  pw.Widget _totalsTable(BillingReportSnapshot report) {
    return _table(
      headers: const [
        'Electricity',
        'Water',
        'Rent',
        'Adjustments',
        'Total billed',
        'Collected',
        'Outstanding',
      ],
      data: [
        [
          _peso(report.cycle.electricityTotalCentavos),
          _peso(report.cycle.waterTotalCentavos),
          _peso(report.cycle.rentTotalCentavos),
          _signedPeso(report.cycle.rentAdjustmentCentavos),
          _peso(report.control.totalBilledCentavos),
          _peso(report.control.totalPaidCentavos),
          _peso(report.control.outstandingCentavos),
        ],
      ],
      numericColumns: const {0, 1, 2, 3, 4, 5, 6},
    );
  }

  pw.Widget _keyValueTable(List<(String, String)> values) {
    return pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _line),
        top: pw.BorderSide(color: _line),
        bottom: pw.BorderSide(color: _line),
      ),
      columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2)},
      children: values
          .map(
            (value) => pw.TableRow(
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6),
                  child: pw.Text(
                    value.$1,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6),
                  child: pw.Text(
                    value.$2,
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          )
          .toList(growable: false),
    );
  }

  pw.Widget _table({
    required List<String> headers,
    required List<List<String>> data,
    required Set<int> numericColumns,
    bool compact = false,
  }) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerDecoration: const pw.BoxDecoration(color: _teal),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: compact ? 7 : 8,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: pw.TextStyle(fontSize: compact ? 6.7 : 8),
      cellPadding: pw.EdgeInsets.symmetric(
        horizontal: compact ? 3 : 5,
        vertical: compact ? 4 : 5,
      ),
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _line),
        bottom: pw.BorderSide(color: _line),
      ),
      rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
      oddRowDecoration: const pw.BoxDecoration(color: _rowAlt),
      headerAlignments: {
        for (var index = 0; index < headers.length; index++)
          index: numericColumns.contains(index)
              ? pw.Alignment.centerRight
              : pw.Alignment.centerLeft,
      },
      cellAlignments: {
        for (var index = 0; index < headers.length; index++)
          index: numericColumns.contains(index)
              ? pw.Alignment.centerRight
              : pw.Alignment.topLeft,
      },
    );
  }

  List<pw.Widget> _notes(BillingReportSnapshot report) {
    final messages = <String>{
      ...report.cycle.warnings,
      ...report.electricity.warnings,
      ...report.water.warnings,
      ...report.rent.warnings,
    };
    if (report.cycle.totalUnallocatedCentavos > 0) {
      messages.add(
        '${_peso(report.cycle.totalUnallocatedCentavos)} remained unallocated / landlady-paid and is not included in boarder bills.',
      );
    }
    if (messages.isEmpty) return const [];
    return [
      pw.SizedBox(height: 16),
      _sectionTitle('Billing notes'),
      pw.SizedBox(height: 5),
      ...messages.map(
        (message) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Bullet(text: message, style: _smallMuted),
        ),
      ),
    ];
  }

  pw.Widget _sectionTitle(String value) => pw.Text(
    value,
    style: pw.TextStyle(
      color: _ink,
      fontSize: 12,
      fontWeight: pw.FontWeight.bold,
    ),
  );

  pw.Widget _notice(String value) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey100,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
    ),
    child: pw.Text(value, style: _smallMuted),
  );

  String _documentTitle(
    BillingReportSnapshot report,
    BillingReportDocumentType type,
    String? boarderId,
  ) => switch (type) {
    BillingReportDocumentType.monthlySummary =>
      '${report.houseName} monthly bills - ${_period(report)}',
    BillingReportDocumentType.combinedBoarderStatements =>
      '${report.houseName} boarder statements - ${_period(report)}',
    BillingReportDocumentType.individualBoarderStatement =>
      '${report.boarder(boarderId!).statement.boarderName} statement - ${_period(report)}',
  };

  String _period(BillingReportSnapshot report) {
    return '${_date(report.cycle.startDate)} - ${_date(report.cycle.endDateExclusive.addDays(-1))}';
  }

  String _waterMethod(BillingReportSnapshot report) {
    if (report.water.method == WaterBillingMethod.personDays) {
      return 'Person-days';
    }
    if (report.water.method == WaterBillingMethod.roomDays) {
      return 'Occupied room-days';
    }
    final basis = switch (report.water.summerBasis) {
      SummerElectricityBasis.roomElectricityCharge => 'room electricity charge',
      SummerElectricityBasis.roomConsumption => 'room consumption (kWh)',
    };
    return 'Electricity percentage using $basis';
  }

  String _waterBasis(WaterBillingRecord water, int value) {
    return switch (water.summerBasis) {
      SummerElectricityBasis.roomElectricityCharge => _peso(value),
      SummerElectricityBasis.roomConsumption =>
        '${(value ~/ 1000)}.${(value % 1000).toString().padLeft(3, '0')} kWh',
    };
  }

  String _date(BusinessDate value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  String _peso(int centavos) {
    final negative = centavos < 0;
    final magnitude = centavos.abs();
    final whole = magnitude ~/ 100;
    final fraction = (magnitude % 100).toString().padLeft(2, '0');
    final digits = whole.toString();
    final grouped = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(',');
      grouped.write(digits[index]);
    }
    return '${negative ? '-' : ''}PHP $grouped.$fraction';
  }

  String _signedPeso(int centavos) {
    if (centavos == 0) return _peso(0);
    return '${centavos > 0 ? '+' : ''}${_peso(centavos)}';
  }

  String _percent(int hundredths) =>
      '${hundredths ~/ 100}.${(hundredths % 100).toString().padLeft(2, '0')}%';

  String _paymentStatus(BillPaymentStatus status) => switch (status) {
    BillPaymentStatus.unpaid => 'Unpaid',
    BillPaymentStatus.partiallyPaid => 'Partially paid',
    BillPaymentStatus.paid => 'Paid',
  };

  String _paymentMethod(PaymentMethod method) => switch (method) {
    PaymentMethod.cash => 'Cash',
    PaymentMethod.gcash => 'GCash',
    PaymentMethod.bankTransfer => 'Bank transfer',
    PaymentMethod.other => 'Other',
  };

  String _filePart(String value, {required String fallback}) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? fallback : cleaned;
  }

  static const _teal = PdfColor.fromInt(0xff0f766e);
  static const _tealDark = PdfColor.fromInt(0xff134e4a);
  static const _tealLight = PdfColor.fromInt(0xffccfbf1);
  static const _ink = PdfColor.fromInt(0xff0f172a);
  static const _line = PdfColor.fromInt(0xffcbd5e1);
  static const _rowAlt = PdfColor.fromInt(0xfff8fafc);
  static const _smallMuted = pw.TextStyle(
    fontSize: 8,
    color: PdfColor.fromInt(0xff475569),
    lineSpacing: 2,
  );
  static const _tinyMuted = pw.TextStyle(
    fontSize: 7,
    color: PdfColor.fromInt(0xff64748b),
  );
}
