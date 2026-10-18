import 'package:boarding_house_manager/core/validation/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators', () {
    test('accepts a normal email address', () {
      expect(Validators.email('owner@example.com'), isNull);
    });

    test('rejects malformed email addresses', () {
      expect(Validators.email('owner-at-example'), isNotNull);
    });

    test('requires an eight-character password', () {
      expect(Validators.password('short'), isNotNull);
      expect(Validators.password('long-enough'), isNull);
    });
  });
}
