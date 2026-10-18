import '../../domain/business_date.dart';

String formatPeso(int? centavos) {
  if (centavos == null) return 'Not set';
  final whole = centavos ~/ 100;
  final fraction = (centavos % 100).toString().padLeft(2, '0');
  final digits = whole.toString();
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(',');
    grouped.write(digits[index]);
  }
  return '₱$grouped.$fraction';
}

int? parsePesoToCentavos(String value) {
  final clean = value.trim().replaceAll(',', '');
  if (clean.isEmpty) return null;
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(clean);
  if (match == null) {
    throw const FormatException('Enter an amount such as 3500 or 3500.50.');
  }
  final pesos = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return pesos * 100 + int.parse(fraction.isEmpty ? '0' : fraction);
}

String centavosToInput(int? centavos) {
  if (centavos == null) return '';
  final whole = centavos ~/ 100;
  final fraction = (centavos % 100).toString().padLeft(2, '0');
  return '$whole.$fraction';
}

String formatBusinessDate(BusinessDate date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
