abstract final class WaterValues {
  static const int maximumBillCentavos = 1000000000000000;

  static int parsePesosToCentavos(String value) {
    final clean = value.trim().replaceAll(',', '');
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(clean);
    if (match == null) {
      throw const WaterValidationException(
        'Enter a non-negative amount such as 1200 or 1200.50.',
        code: 'invalid-water-bill-format',
      );
    }
    final pesos = BigInt.parse(match.group(1)!);
    final fractionText = (match.group(2) ?? '').padRight(2, '0');
    final fraction = BigInt.parse(fractionText.isEmpty ? '0' : fractionText);
    final result = pesos * BigInt.from(100) + fraction;
    if (result > BigInt.from(maximumBillCentavos)) {
      throw const WaterValidationException(
        'The water bill is outside the supported range.',
        code: 'value-out-of-range',
      );
    }
    return result.toInt();
  }
}

class WaterValidationException implements Exception {
  const WaterValidationException(this.message, {required this.code});

  final String message;
  final String code;

  @override
  String toString() => 'WaterValidationException($code): $message';
}
