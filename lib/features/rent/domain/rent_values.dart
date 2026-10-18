abstract final class RentValues {
  static const maximumAmountCentavos = 1000000000000000;
}

class RentValidationException implements Exception {
  const RentValidationException(this.message, {required this.code});

  final String message;
  final String code;

  @override
  String toString() => 'RentValidationException($code): $message';
}
