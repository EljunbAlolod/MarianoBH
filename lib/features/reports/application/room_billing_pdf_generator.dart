import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../billing/domain/monthly_billing_models.dart';
import '../../billing/domain/room_billing_models.dart';
import '../../property_management/domain/business_date.dart';

class RoomBillingPdfGenerator {
  const RoomBillingPdfGenerator();

  String fileName(String houseName, RoomBillingCycle cycle) {
    final safeHouse = houseName
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final month =
        '${cycle.startDate.year}-${cycle.startDate.month.toString().padLeft(2, '0')}';
    return '${safeHouse.isEmpty ? 'BoardingHouse' : safeHouse}_Room_Bills_$month.pdf';
  }

  Future<Uint8List> build({
    required String houseName,
    required RoomBillingCycle cycle,
    required BillingCycleControl control,
    required List<RoomBillAccount> accounts,
    required List<RoomPaymentRecord> payments,
  }) async {
    final accountByRoom = {
      for (final account in accounts) account.roomId: account,
    };
    final paymentsByRoom = <String, List<RoomPaymentRecord>>{};
    for (final payment in payments) {
      paymentsByRoom.putIfAbsent(payment.roomId, () => []).add(payment);
    }
    final document = pw.Document(
      title: '$houseName room bills ${_period(cycle)}',
      author: houseName,
      creator: 'Boarding House Manager',
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
        build: (context) => [
          pw.Text(
            houseName,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Room billing statement · ${_period(cycle)}',
            style: const pw.TextStyle(fontSize: 13, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const ['Billed', 'Paid', 'Outstanding', 'Status'],
            data: [
              [
                _peso(control.totalBilledCentavos),
                _peso(control.totalPaidCentavos),
                _peso(control.outstandingCentavos),
                control.state == BillingCycleState.voided
                    ? 'Voided'
                    : _status(control.paymentStatus),
              ],
            ],
            headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 18),
          ...cycle.statements.expand((statement) {
            final account = accountByRoom[statement.roomId];
            final roomPayments = paymentsByRoom[statement.roomId] ?? const [];
            return [
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(6),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          statement.roomName,
                          style: pw.TextStyle(
                            fontSize: 15,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          account == null
                              ? 'Unavailable'
                              : _status(account.status),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '${_ranges(statement.occupiedRanges)} · ${statement.occupiedDays} occupied day${statement.occupiedDays == 1 ? '' : 's'}',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    if (statement.rentCentavos > 0)
                      _row('Rent (legacy bill)', statement.rentCentavos),
                    _row('Electricity', statement.electricityCentavos),
                    _row('Water', statement.waterCentavos),
                    pw.Divider(),
                    _row(
                      'Bill total',
                      statement.currentChargesCentavos,
                      bold: true,
                    ),
                    if (account != null) ...[
                      _row('Paid', account.totalPaidCentavos),
                      _row(
                        'Remaining',
                        account.outstandingCentavos,
                        bold: true,
                      ),
                    ],
                    if (roomPayments.isNotEmpty) ...[
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Payments',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      ...roomPayments.map(
                        (payment) => pw.Text(
                          '${_date(payment.paymentDate)} · ${_peso(payment.amountCentavos)} · ${payment.method.name}${payment.notes == null ? '' : ' · ${payment.notes}'}',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
            ];
          }),
          if (cycle.warnings.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              'Notes',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            ...cycle.warnings.map((warning) => pw.Bullet(text: warning)),
          ],
        ],
      ),
    );
    return document.save();
  }

  static pw.Widget _row(String label, int centavos, {bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label),
            pw.Text(
              _peso(centavos),
              style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
            ),
          ],
        ),
      );

  static String _period(RoomBillingCycle cycle) =>
      '${_date(cycle.startDate)} to ${_date(cycle.endDateExclusive.addDays(-1))}';

  static String _ranges(List<OccupiedDateRange> ranges) => ranges
      .map(
        (range) =>
            '${_date(range.startDate)}–${_date(range.endDateExclusive.addDays(-1))}',
      )
      .join(', ');

  static String _date(BusinessDate value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static String _peso(int centavos) =>
      'PHP ${(centavos / 100).toStringAsFixed(2)}';

  static String _status(BillPaymentStatus status) => switch (status) {
    BillPaymentStatus.unpaid => 'Unpaid',
    BillPaymentStatus.partiallyPaid => 'Partially paid',
    BillPaymentStatus.paid => 'Paid',
  };
}
