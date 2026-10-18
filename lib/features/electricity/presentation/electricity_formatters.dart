import '../../property_management/domain/business_date.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../domain/electricity_values.dart';
import '../domain/electricity_batch_models.dart';

String formatElectricityReading(int wattHours) =>
    '${ElectricityValues.formatWattHoursAsKilowattHours(wattHours)} kWh';

String formatElectricityRate(int micropesosPerKwh) =>
    '₱${ElectricityValues.formatMicropesosAsPesosPerKwh(micropesosPerKwh)} / kWh';

String formatElectricityPeriod(
  BusinessDate startDate,
  BusinessDate endDateExclusive,
) {
  final lastBillableDate = endDateExclusive.addDays(-1);
  return '${formatBusinessDate(startDate)} – ${formatBusinessDate(lastBillableDate)}';
}

String formatSignedPeso(int centavos) {
  if (centavos == 0) return formatPeso(0);
  return centavos < 0
      ? '-${formatPeso(-centavos)}'
      : '+${formatPeso(centavos)}';
}

String formatElectricityBatchStatus(ElectricityReadingBatchStatus status) =>
    switch (status) {
      ElectricityReadingBatchStatus.draft => 'Draft',
      ElectricityReadingBatchStatus.finalized => 'Finalized',
      ElectricityReadingBatchStatus.usedInBilling => 'Used in billing',
      ElectricityReadingBatchStatus.voided => 'Voided',
    };

String formatElectricityDateTime(DateTime value) {
  final local = value.toLocal();
  final date = formatBusinessDate(BusinessDate.fromDateTime(local));
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '$date, $hour:$minute $period';
}
