import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/property_management/domain/occupancy.dart';
import 'package:boarding_house_manager/features/property_management/domain/property_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BusinessDate', () {
    test('round-trips a strict ISO date at UTC midnight', () {
      final date = BusinessDate.parse('2026-02-03');

      expect(date.toString(), '2026-02-03');
      expect(date.asUtcDateTime, DateTime.utc(2026, 2, 3));
      expect(date.asUtcDateTime.isUtc, isTrue);
    });

    test('rejects invalid dates and non-midnight UTC values', () {
      expect(() => BusinessDate(2026, 2, 29), throwsRangeError);
      expect(
        () => BusinessDate.fromUtcDateTime(DateTime.utc(2026, 2, 3, 1)),
        throwsFormatException,
      );
    });

    test('compares dates without local timezone conversions', () {
      final first = BusinessDate(2026, 10, 4);
      final next = BusinessDate(2026, 10, 5);

      expect(first.isBefore(next), isTrue);
      expect(next.isAfter(first), isTrue);
    });

    test('derives today from the Asia/Manila business timezone', () {
      final justBeforeMidnightUtc = DateTime.utc(2026, 10, 13, 16, 30);

      expect(
        BusinessDate.todayInManila(instant: justBeforeMidnightUtc),
        BusinessDate(2026, 10, 14),
      );
    });
  });

  test('occupancy uses a half-open date interval', () {
    final occupancy = Occupancy(
      occupancyId: 'occupancy-1',
      boarderId: 'boarder-1',
      roomId: 'room-1',
      moveInDate: BusinessDate(2026, 1, 10),
      moveOutDate: BusinessDate(2026, 1, 20),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    expect(occupancy.contains(BusinessDate(2026, 1, 10)), isTrue);
    expect(occupancy.contains(BusinessDate(2026, 1, 19)), isTrue);
    expect(occupancy.contains(BusinessDate(2026, 1, 20)), isFalse);
  });

  group('PropertyValidation', () {
    test(
      'normalizes optional text and preserves money as integer centavos',
      () {
        expect(
          PropertyValidation.optionalText(
            '  ',
            label: 'Contact',
            maxLength: PropertyValidation.contactMaxLength,
          ),
          isNull,
        );
        expect(PropertyValidation.rentCentavos(123456), 123456);
      },
    );

    test('rejects empty required values and negative money', () {
      expect(
        () => PropertyValidation.requiredText(
          '  ',
          label: 'Room name',
          maxLength: PropertyValidation.roomNameMaxLength,
        ),
        throwsA(isA<PropertyRepositoryException>()),
      );
      expect(
        () => PropertyValidation.rentCentavos(-1),
        throwsA(isA<PropertyRepositoryException>()),
      );
    });

    test('rejects future lifecycle dates', () {
      expect(
        () => PropertyValidation.recordedDate(
          BusinessDate(2026, 10, 14),
          now: DateTime(2026, 10, 13),
          label: 'Move-in date',
        ),
        throwsA(
          isA<PropertyRepositoryException>().having(
            (error) => error.code,
            'code',
            'future-date',
          ),
        ),
      );
    });
  });
}
