abstract final class Validators {
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static String? requiredText(
    String? value, {
    required String label,
    int maxLength = 120,
  }) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$label is required.';
    if (text.length > maxLength) {
      return '$label must be $maxLength characters or fewer.';
    }
    return null;
  }

  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Email address is required.';
    if (text.length > 254 || !_emailPattern.hasMatch(text)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required.';
    if (value.length < 8) return 'Use at least 8 characters.';
    return null;
  }
}
