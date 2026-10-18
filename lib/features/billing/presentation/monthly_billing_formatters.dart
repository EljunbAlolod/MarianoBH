import '../../property_management/domain/business_date.dart';
import '../domain/monthly_billing_models.dart';

String formatMonthlyPeriod(BusinessDate start, BusinessDate endExclusive) {
  return '${_short(start)} - ${_short(endExclusive.addDays(-1))}';
}

String formatPaymentStatus(BillPaymentStatus status) => switch (status) {
  BillPaymentStatus.unpaid => 'Unpaid',
  BillPaymentStatus.partiallyPaid => 'Partially paid',
  BillPaymentStatus.paid => 'Paid',
};

String formatPaymentMethod(PaymentMethod method) => switch (method) {
  PaymentMethod.cash => 'Cash',
  PaymentMethod.gcash => 'GCash',
  PaymentMethod.bankTransfer => 'Bank transfer',
  PaymentMethod.other => 'Other',
};

String _short(BusinessDate value) {
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
