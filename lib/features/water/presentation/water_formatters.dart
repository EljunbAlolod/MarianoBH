import '../../property_management/domain/business_date.dart';
import '../domain/water_models.dart';

String formatWaterMethod(WaterBillingMethod method) => switch (method) {
  WaterBillingMethod.selectedBoarders => 'Normal — selected boarders',
  WaterBillingMethod.personDays => 'Person-days',
  WaterBillingMethod.roomDays => 'Occupied room-days',
  WaterBillingMethod.electricityPercentage => 'Electricity percentage',
};

String formatSummerBasis(SummerElectricityBasis basis) => switch (basis) {
  SummerElectricityBasis.roomElectricityCharge => 'Room electricity charge',
  SummerElectricityBasis.roomConsumption => 'Room electricity consumption',
};

String formatWaterPeriod(BusinessDate start, BusinessDate endExclusive) {
  final inclusiveEnd = endExclusive.addDays(-1);
  return '${_shortDate(start)} – ${_shortDate(inclusiveEnd)}';
}

String _shortDate(BusinessDate date) {
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
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String formatMonthList(List<int> months) {
  const labels = [
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
  final sorted = [...months]..sort();
  return sorted.map((month) => labels[month - 1]).join(', ');
}
