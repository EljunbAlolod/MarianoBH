/// Exact value parsing and arithmetic for electricity billing.
///
/// Meter readings are stored as whole watt-hours and rates as micro-pesos per
/// kilowatt-hour. Monetary results are stored as whole centavos. No operation
/// in this file uses binary floating point.
abstract final class ElectricityValues {
  static const int wattHoursPerKilowattHour = 1000;
  static const int micropesosPerPeso = 1000000;
  static const int micropesosPerCentavo = 10000;

  /// Storage limits mirrored by Firestore security rules.
  static const int maximumMeterReadingWh = 1000000000000;
  static const int maximumRateMicropesosPerKwh = 1000000000;
  static const int maximumBillingTotalCentavos = 1000000000000000;

  /// Divisor for `Wh * micro-pesos/kWh -> centavos`.
  static const int chargeDivisor =
      wattHoursPerKilowattHour * micropesosPerCentavo;

  static final BigInt maxFirestoreInteger = BigInt.parse('9223372036854775807');

  /// Parses a non-negative kWh value with at most three decimal places.
  static int parseKilowattHoursToWattHours(String value) {
    return _parseScaledDecimal(
      value,
      scale: wattHoursPerKilowattHour,
      decimalPlaces: 3,
      label: 'Meter reading',
      code: 'invalid-reading-format',
      maximum: maximumMeterReadingWh,
    );
  }

  /// Parses a non-negative PHP/kWh rate with at most six decimal places.
  static int parsePesosPerKwhToMicropesos(String value) {
    return _parseScaledDecimal(
      value,
      scale: micropesosPerPeso,
      decimalPlaces: 6,
      label: 'Electricity rate',
      code: 'invalid-rate-format',
      maximum: maximumRateMicropesosPerKwh,
    );
  }

  static String formatWattHoursAsKilowattHours(int wattHours) {
    _requireNonNegative(wattHours, 'Meter reading');
    return _formatScaledInteger(
      wattHours,
      scale: wattHoursPerKilowattHour,
      decimalPlaces: 3,
    );
  }

  static String formatMicropesosAsPesosPerKwh(int micropesos) {
    _requireNonNegative(micropesos, 'Electricity rate');
    return _formatScaledInteger(
      micropesos,
      scale: micropesosPerPeso,
      decimalPlaces: 6,
    );
  }

  /// Calculates a charge using round-half-up to the nearest centavo.
  static int chargeCentavos({
    required int consumptionWh,
    required int rateMicropesosPerKwh,
  }) {
    _requireNonNegative(consumptionWh, 'Electricity consumption');
    _requireNonNegative(rateMicropesosPerKwh, 'Electricity rate');
    final numerator =
        BigInt.from(consumptionWh) * BigInt.from(rateMicropesosPerKwh);
    final result = divideRoundHalfUp(numerator, BigInt.from(chargeDivisor));
    return checkedFirestoreInt(result, label: 'Electricity charge');
  }

  /// Rounds a non-negative rational number using the financial half-up rule.
  static BigInt divideRoundHalfUp(BigInt numerator, BigInt denominator) {
    if (numerator.isNegative || denominator <= BigInt.zero) {
      throw const ElectricityValidationException(
        'Exact rounding requires a non-negative numerator and positive denominator.',
        code: 'invalid-arithmetic',
      );
    }
    return (numerator + (denominator ~/ BigInt.two)) ~/ denominator;
  }

  static int checkedFirestoreInt(BigInt value, {required String label}) {
    if (value.isNegative || value > maxFirestoreInteger) {
      throw ElectricityValidationException(
        '$label is outside the supported range.',
        code: 'value-out-of-range',
      );
    }
    return value.toInt();
  }

  static int _parseScaledDecimal(
    String value, {
    required int scale,
    required int decimalPlaces,
    required String label,
    required String code,
    required int maximum,
  }) {
    final clean = value.trim().replaceAll(',', '');
    final match = RegExp('^(\\d+)(?:\\.(\\d{1,$decimalPlaces}))?\$')
        .firstMatch(clean);
    if (match == null) {
      throw ElectricityValidationException(
        '$label must be a non-negative number with no more than '
        '$decimalPlaces decimal places.',
        code: code,
      );
    }
    final whole = BigInt.parse(match.group(1)!);
    final fractionText = (match.group(2) ?? '').padRight(decimalPlaces, '0');
    final fraction = fractionText.isEmpty
        ? BigInt.zero
        : BigInt.parse(fractionText);
    final result = whole * BigInt.from(scale) + fraction;
    final parsed = checkedFirestoreInt(result, label: label);
    if (parsed > maximum) {
      throw ElectricityValidationException(
        '$label is outside the supported range.',
        code: 'value-out-of-range',
      );
    }
    return parsed;
  }

  static String _formatScaledInteger(
    int value, {
    required int scale,
    required int decimalPlaces,
  }) {
    final whole = value ~/ scale;
    final fraction = (value % scale).toString().padLeft(decimalPlaces, '0');
    final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.isEmpty ? '$whole' : '$whole.$trimmed';
  }

  static void _requireNonNegative(int value, String label) {
    if (value < 0) {
      throw ElectricityValidationException(
        '$label cannot be negative.',
        code: 'negative-value',
      );
    }
  }
}

class ElectricityValidationException implements Exception {
  const ElectricityValidationException(this.message, {required this.code});

  final String message;
  final String code;

  @override
  String toString() => 'ElectricityValidationException($code): $message';
}
