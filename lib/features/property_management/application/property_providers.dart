import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/boarder.dart';
import '../domain/occupancy.dart';
import '../domain/property_repository.dart';
import '../domain/room.dart';

final propertyRepositoryProvider = Provider<PropertyRepository>((ref) {
  throw StateError('propertyRepositoryProvider must be overridden at startup.');
});

/// Pass the ready session's `workspace.ownerUid` to this provider.
final roomsProvider = StreamProvider.family<List<Room>, String>((ref, ownerId) {
  return ref.watch(propertyRepositoryProvider).watchRooms(ownerId);
});

/// Pass the ready session's `workspace.ownerUid` to this provider.
final boardersProvider = StreamProvider.family<List<Boarder>, String>((
  ref,
  ownerId,
) {
  return ref.watch(propertyRepositoryProvider).watchBoarders(ownerId);
});

@immutable
class OccupanciesQuery {
  const OccupanciesQuery({required this.ownerId, required this.boarderId});

  final String ownerId;
  final String boarderId;

  @override
  bool operator ==(Object other) {
    return other is OccupanciesQuery &&
        ownerId == other.ownerId &&
        boarderId == other.boarderId;
  }

  @override
  int get hashCode => Object.hash(ownerId, boarderId);
}

final occupanciesProvider =
    StreamProvider.family<List<Occupancy>, OccupanciesQuery>((ref, query) {
      return ref
          .watch(propertyRepositoryProvider)
          .watchOccupancies(query.ownerId, query.boarderId);
    });

/// All immutable occupancy intervals used by utility allocation engines.
final allOccupanciesProvider = StreamProvider.family<List<Occupancy>, String>((
  ref,
  ownerId,
) {
  return ref.watch(propertyRepositoryProvider).watchAllOccupancies(ownerId);
});
