import 'package:flutter/foundation.dart';

@immutable
class OwnerWorkspace {
  const OwnerWorkspace({
    required this.ownerUid,
    required this.ownerName,
    required this.ownerEmail,
    required this.houseName,
    this.currencyCode = 'PHP',
    this.businessTimeZone = 'Asia/Manila',
  });

  final String ownerUid;
  final String ownerName;
  final String ownerEmail;
  final String houseName;
  final String currencyCode;
  final String businessTimeZone;
}
