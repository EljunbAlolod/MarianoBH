import 'package:flutter/foundation.dart';

@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.isEmailVerified,
    this.displayName,
  });

  final String id;
  final String email;
  final bool isEmailVerified;
  final String? displayName;

  AppUser copyWith({
    String? email,
    bool? isEmailVerified,
    String? displayName,
  }) {
    return AppUser(
      id: id,
      email: email ?? this.email,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      displayName: displayName ?? this.displayName,
    );
  }
}
