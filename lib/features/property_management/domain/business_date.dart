import 'package:flutter/foundation.dart';

/// A calendar date in the boarding house business time zone.
///
/// It is deliberately stored as midnight UTC so a date chosen on an Android
/// phone cannot shift to the previous/next day when it is sent to Firestore.
@immutable
class BusinessDate implements Comparable<BusinessDate> {
  BusinessDate(int year, int month, int day)
    : value = _checkedUtcDate(year, month, day);

  factory BusinessDate.fromDateTime(DateTime value) {
    return BusinessDate(value.year, value.month, value.day);
  }

  /// Returns today's calendar date in the configured Asia/Manila business
  /// timezone. Manila is UTC+08:00 year-round and does not observe DST.
  factory BusinessDate.todayInManila({DateTime? instant}) {
    final manila = (instant ?? DateTime.now()).toUtc().add(
      const Duration(hours: 8),
    );
    return BusinessDate(manila.year, manila.month, manila.day);
  }

  factory BusinessDate.fromUtcDateTime(DateTime value) {
    final utc = value.toUtc();
    if (utc.hour != 0 ||
        utc.minute != 0 ||
        utc.second != 0 ||
        utc.millisecond != 0 ||
        utc.microsecond != 0) {
      throw const FormatException('Business dates must be UTC midnight.');
    }
    return BusinessDate(utc.year, utc.month, utc.day);
  }

  factory BusinessDate.parse(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) {
      throw const FormatException('Use YYYY-MM-DD for a business date.');
    }
    return BusinessDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  final DateTime value;

  int get year => value.year;
  int get month => value.month;
  int get day => value.day;

  DateTime get asUtcDateTime => value;

  bool isBefore(BusinessDate other) => compareTo(other) < 0;
  bool isAfter(BusinessDate other) => compareTo(other) > 0;

  BusinessDate addDays(int days) {
    final result = value.add(Duration(days: days));
    return BusinessDate(result.year, result.month, result.day);
  }

  int daysUntil(BusinessDate other) => other.value.difference(value).inDays;

  @override
  int compareTo(BusinessDate other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) {
    return other is BusinessDate && value == other.value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${year.toString().padLeft(4, '0')}-${twoDigits(month)}-${twoDigits(day)}';
  }

  static DateTime _checkedUtcDate(int year, int month, int day) {
    if (year < 1 || year > 9999) {
      throw RangeError.range(year, 1, 9999, 'year');
    }
    final result = DateTime.utc(year, month, day);
    if (result.year != year || result.month != month || result.day != day) {
      throw RangeError('Invalid calendar date: $year-$month-$day');
    }
    return result;
  }
}
