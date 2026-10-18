import '../../property_management/domain/business_date.dart';
import '../domain/rent_models.dart';

String formatRentMode(RentBillingMode mode) => switch (mode) {
  RentBillingMode.disabled => 'Rent disabled',
  RentBillingMode.perBoarder => 'Per boarder',
  RentBillingMode.perRoom => 'Per room',
};

String describeRentMode(RentBillingMode mode) => switch (mode) {
  RentBillingMode.disabled => 'Only documented adjustments are calculated.',
  RentBillingMode.perBoarder => 'Each boarder uses the monthly rate of the room they occupied, prorated by their days.',
  RentBillingMode.perRoom => 'Each room is charged once for its occupied days, then split among occupants by person-days.',
};

String formatRentPeriod(BusinessDate start, BusinessDate endExclusive) {
  return '${_short(start)} - ${_short(endExclusive.addDays(-1))}';
}

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
