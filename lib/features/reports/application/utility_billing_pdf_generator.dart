import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../billing/domain/monthly_billing_models.dart';
import '../../billing/domain/utility_billing_models.dart';
import '../../property_management/domain/business_date.dart';

enum UtilityBillingPdfDocumentType {
  summary,
  allRoomStatements,
  individualRoomStatement,
}

class UtilityBillingPdfGenerator {
  const UtilityBillingPdfGenerator();

  PdfPageFormat pageFormat(UtilityBillingPdfDocumentType type) =>
      type == UtilityBillingPdfDocumentType.summary
      ? PdfPageFormat.a4.landscape
      : PdfPageFormat.a4;

  String fileName({
    required String houseName,
    required UtilityBillingBatch batch,
    required UtilityBillingPdfDocumentType type,
    String? roomName,
  }) {
    final house = _filePart(houseName, fallback: 'BoardingHouse');
    final reference = _filePart(
      batch.billingBatchReference,
      fallback: 'UtilityBill',
    );
    return switch (type) {
      UtilityBillingPdfDocumentType.summary =>
        '${house}_${reference}_Summary.pdf',
      UtilityBillingPdfDocumentType.allRoomStatements =>
        '${house}_${reference}_Room_Statements.pdf',
      UtilityBillingPdfDocumentType.individualRoomStatement =>
        '${house}_${reference}_${_filePart(roomName ?? '', fallback: 'Room')}.pdf',
    };
  }

  Future<Uint8List> build({
    required String houseName,
    required UtilityBillingBatch batch,
    required List<UtilityRoomBillAccount> accounts,
    required List<UtilityRoomPaymentRecord> payments,
    required UtilityBillingPdfDocumentType type,
    String? roomId,
  }) async {
    final accountByRoom = {
      for (final account in accounts)
        if (account.billingBatchId == batch.billingBatchId)
          account.roomId: account,
    };
    final batchPayments = payments
        .where((payment) => payment.billingBatchId == batch.billingBatchId)
        .toList(growable: false);
    if (accountByRoom.length != batch.statements.length ||
        batch.statements.any(
          (statement) =>
              accountByRoom[statement.roomId]?.totalChargesCentavos !=
              statement.totalCentavos,
        )) {
      throw const UtilityBillingPdfException(
        'The room payment accounts do not match the finalized bill snapshot.',
        code: 'account-snapshot-mismatch',
      );
    }
    if (type == UtilityBillingPdfDocumentType.individualRoomStatement &&
        (roomId == null || !accountByRoom.containsKey(roomId))) {
      throw const UtilityBillingPdfException(
        'Select a room before generating an individual statement.',
        code: 'room-required',
      );
    }

    final document = pw.Document(
      title: '$houseName ${batch.billingBatchReference}',
      author: houseName,
      creator: 'Boarding House Manager',
      subject: 'Finalized room utility bill snapshot',
    );
    switch (type) {
      case UtilityBillingPdfDocumentType.summary:
        document.addPage(
          _summary(houseName: houseName, batch: batch, accounts: accountByRoom),
        );
      case UtilityBillingPdfDocumentType.allRoomStatements:
        document.addPage(
          _statements(
            houseName: houseName,
            batch: batch,
            statements: batch.statements,
            accounts: accountByRoom,
            payments: batchPayments,
          ),
        );
      case UtilityBillingPdfDocumentType.individualRoomStatement:
        document.addPage(
          _statements(
            houseName: houseName,
            batch: batch,
            statements: batch.statements
                .where((statement) => statement.roomId == roomId)
                .toList(growable: false),
            accounts: accountByRoom,
            payments: batchPayments,
          ),
        );
    }
    return document.save();
  }

  pw.MultiPage _summary({
    required String houseName,
    required UtilityBillingBatch batch,
    required Map<String, UtilityRoomBillAccount> accounts,
  }) {
    final batchAccounts = accounts.values.toList(growable: false);
    final paid = batchAccounts.fold<int>(
      0,
      (sum, account) => sum + account.totalPaidCentavos,
    );
    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 28),
      header: (context) =>
          _header(context, houseName, batch, 'Created bills summary'),
      footer: _footer,
      build: (context) => [
        _statusBanner(utilityBillingPaymentStatus(batchAccounts)),
        pw.SizedBox(height: 12),
        _metadata(batch),
        pw.SizedBox(height: 16),
        _sectionTitle('Totals'),
        pw.SizedBox(height: 6),
        _table(
          headers: const [
            'Electricity',
            'Water',
            'Rent',
            'Total billed',
            'Paid',
            'Outstanding',
          ],
          data: [
            [
              _peso(batch.electricityTotalCentavos),
              _peso(batch.waterTotalCentavos),
              _peso(0),
              _peso(batch.totalBilledCentavos),
              _peso(paid),
              _peso(batch.totalBilledCentavos - paid),
            ],
          ],
          numericColumns: const {0, 1, 2, 3, 4, 5},
        ),
        pw.SizedBox(height: 16),
        _sectionTitle('Room bills'),
        pw.SizedBox(height: 6),
        _table(
          headers: const [
            'Room',
            'Electricity',
            'Water',
            'Total',
            'Paid',
            'Outstanding',
            'Status',
          ],
          data: batch.statements
              .map((statement) {
                final account = accounts[statement.roomId]!;
                return [
                  statement.roomName,
                  _peso(statement.electricityCentavos),
                  _peso(statement.waterCentavos),
                  _peso(statement.totalCentavos),
                  _peso(account.totalPaidCentavos),
                  _peso(account.outstandingCentavos),
                  _status(account.status),
                ];
              })
              .toList(growable: false),
          numericColumns: const {1, 2, 3, 4, 5},
        ),
        ..._notes(batch),
      ],
    );
  }

  pw.MultiPage _statements({
    required String houseName,
    required UtilityBillingBatch batch,
    required List<RoomUtilityBillStatement> statements,
    required Map<String, UtilityRoomBillAccount> accounts,
    required List<UtilityRoomPaymentRecord> payments,
  }) {
    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(38, 32, 38, 32),
      header: (context) =>
          _header(context, houseName, batch, 'Room utility statement'),
      footer: _footer,
      build: (context) {
        final widgets = <pw.Widget>[];
        for (var index = 0; index < statements.length; index++) {
          if (index > 0) widgets.add(pw.NewPage());
          final statement = statements[index];
          final account = accounts[statement.roomId]!;
          final roomPayments = payments
              .where((payment) => payment.roomId == statement.roomId)
              .toList(growable: false);
          widgets.addAll([
            _statusBanner(account.status),
            pw.SizedBox(height: 14),
            pw.Text(
              statement.roomName,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                color: _ink,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              '${batch.billingBatchReference} - issued ${_date(batch.issuedOn)}',
              style: _smallMuted,
            ),
            pw.SizedBox(height: 16),
            _sectionTitle('Utility periods'),
            pw.SizedBox(height: 6),
            _keyValueTable([
              (
                'Electricity measurement',
                '${_date(batch.electricityMeasurementStart)} to ${_date(batch.electricityMeasurementEnd)}',
              ),
              (
                'Water statement',
                '${_date(batch.waterPeriodStart)} to ${_date(batch.waterPeriodEndExclusive.addDays(-1))}',
              ),
              ('Electricity batch', batch.electricityBatchReference),
              ('Water batch', batch.waterBatchReference),
            ]),
            pw.SizedBox(height: 16),
            _sectionTitle('Charge breakdown'),
            pw.SizedBox(height: 6),
            _keyValueTable([
              ('Electricity', _peso(statement.electricityCentavos)),
              ('Water', _peso(statement.waterCentavos)),
              ('Rent (not included)', _peso(0)),
              ('Total bill', _peso(statement.totalCentavos)),
              ('Paid', _peso(account.totalPaidCentavos)),
              ('Outstanding', _peso(account.outstandingCentavos)),
            ]),
            pw.SizedBox(height: 16),
            _sectionTitle('Payment history'),
            pw.SizedBox(height: 6),
            if (roomPayments.isEmpty)
              _notice('No payments have been recorded for this room bill.')
            else
              _table(
                headers: const ['Date', 'Method', 'Amount', 'Notes'],
                data: roomPayments
                    .map(
                      (payment) => [
                        _date(payment.paymentDate),
                        _method(payment.method),
                        _peso(payment.amountCentavos),
                        payment.notes ?? '',
                      ],
                    )
                    .toList(growable: false),
                numericColumns: const {2},
              ),
            pw.SizedBox(height: 18),
            pw.Text(
              'Generated from finalized snapshot ${batch.billingBatchReference}. Rent and boarder splitting are managed separately.',
              style: _smallMuted,
            ),
          ]);
        }
        return widgets;
      },
    );
  }

  pw.Widget _metadata(UtilityBillingBatch batch) => pw.Table(
    columnWidths: const {
      0: pw.FlexColumnWidth(),
      1: pw.FlexColumnWidth(),
      2: pw.FlexColumnWidth(),
    },
    children: [
      pw.TableRow(
        children: [
          _metadataCell('Bill created', _date(batch.issuedOn)),
          _metadataCell(
            'Electricity measurement',
            '${_date(batch.electricityMeasurementStart)} to ${_date(batch.electricityMeasurementEnd)}',
          ),
          _metadataCell(
            'Water statement',
            '${_date(batch.waterPeriodStart)} to ${_date(batch.waterPeriodEndExclusive.addDays(-1))}',
          ),
        ],
      ),
      pw.TableRow(
        children: [
          _metadataCell('Billing batch', batch.billingBatchReference),
          _metadataCell('Electricity batch', batch.electricityBatchReference),
          _metadataCell('Water batch', batch.waterBatchReference),
        ],
      ),
    ],
  );

  pw.Widget _metadataCell(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(right: 12, bottom: 8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: _tinyMuted),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
      ],
    ),
  );

  pw.Widget _header(
    pw.Context context,
    String houseName,
    UtilityBillingBatch batch,
    String title,
  ) => pw.Container(
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
              houseName,
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: _teal,
              ),
            ),
            pw.Text(title, style: _smallMuted),
          ],
        ),
        pw.Text(batch.billingBatchReference, style: _smallMuted),
      ],
    ),
  );

  pw.Widget _footer(pw.Context context) => pw.Container(
    padding: const pw.EdgeInsets.only(top: 7),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _line)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('Boarding House Manager', style: _tinyMuted),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: _tinyMuted,
        ),
      ],
    ),
  );

  pw.Widget _statusBanner(BillPaymentStatus status) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: pw.BoxDecoration(
      color: _tealLight,
      border: pw.Border.all(color: _teal),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
    ),
    child: pw.Text(
      _status(status).toUpperCase(),
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
        color: _tealDark,
      ),
    ),
  );

  pw.Widget _keyValueTable(List<(String, String)> values) => pw.Table(
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

  pw.Widget _table({
    required List<String> headers,
    required List<List<String>> data,
    required Set<int> numericColumns,
  }) => pw.TableHelper.fromTextArray(
    headers: headers,
    data: data,
    headerDecoration: const pw.BoxDecoration(color: _teal),
    headerStyle: pw.TextStyle(
      color: PdfColors.white,
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
    ),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _line),
      bottom: pw.BorderSide(color: _line),
    ),
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

  List<pw.Widget> _notes(UtilityBillingBatch batch) {
    if (batch.warnings.isEmpty && batch.totalUnallocatedCentavos == 0) {
      return const [];
    }
    return [
      pw.SizedBox(height: 16),
      _sectionTitle('Notes'),
      pw.SizedBox(height: 5),
      if (batch.totalUnallocatedCentavos > 0)
        pw.Bullet(
          text:
              '${_peso(batch.totalUnallocatedCentavos)} is landlady-paid / unallocated and is not charged to a room.',
          style: _smallMuted,
        ),
      ...batch.warnings.map(
        (warning) => pw.Bullet(text: warning, style: _smallMuted),
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

  static String _date(BusinessDate value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static String _peso(int centavos) {
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

  static String _status(BillPaymentStatus status) => switch (status) {
    BillPaymentStatus.unpaid => 'Unpaid',
    BillPaymentStatus.partiallyPaid => 'Partially paid',
    BillPaymentStatus.paid => 'Paid',
  };

  static String _method(PaymentMethod method) => switch (method) {
    PaymentMethod.cash => 'Cash',
    PaymentMethod.gcash => 'GCash',
    PaymentMethod.bankTransfer => 'Bank transfer',
    PaymentMethod.other => 'Other',
  };

  static String _filePart(String value, {required String fallback}) {
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

class UtilityBillingPdfException implements Exception {
  const UtilityBillingPdfException(this.message, {required this.code});

  final String message;
  final String code;

  @override
  String toString() => 'UtilityBillingPdfException($code): $message';
}
