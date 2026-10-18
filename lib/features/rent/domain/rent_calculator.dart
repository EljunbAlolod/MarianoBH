import '../../property_management/domain/business_date.dart';
import '../../property_management/domain/boarder.dart';
import '../../property_management/domain/occupancy.dart';
import '../../property_management/domain/room.dart';
import 'rent_models.dart';
import 'rent_values.dart';

/// Pure partial-month rent and adjustment calculation using integer centavos.
///
/// Occupancy and billing periods are half-open ranges: [start, end). This makes
/// a same-day room transfer bill the day in the new room exactly once.
class RentCalculator {
  const RentCalculator();

  RentCalculationResult calculate(RentCalculationInput input) {
    _validate(input);
    final slices = _slices(input);
    final roomsById = {for (final room in input.rooms) room.roomId: room};
    final boardersById = {
      for (final boarder in input.boarders) boarder.boarderId: boarder,
    };
    final groups = <String, _RoomBoarderGroup>{};
    final occupiedOffsetsByRoom = <String, Set<int>>{};

    for (final slice in slices) {
      final key = '${slice.roomId}\u0000${slice.boarderId}';
      final group = groups.putIfAbsent(
        key,
        () =>
            _RoomBoarderGroup(roomId: slice.roomId, boarderId: slice.boarderId),
      );
      group.occupancyIds.add(slice.occupancyId);
      group.days += slice.days;
      final occupied = occupiedOffsetsByRoom.putIfAbsent(
        slice.roomId,
        () => <int>{},
      );
      final offset = input.startDate.daysUntil(slice.start);
      for (var day = 0; day < slice.days; day++) {
        occupied.add(offset + day);
      }
    }

    final roomAllocations = switch (input.mode) {
      RentBillingMode.disabled => <RoomRentAllocation>[],
      RentBillingMode.perBoarder => _perBoarderRooms(
        input: input,
        groups: groups,
        roomsById: roomsById,
        boardersById: boardersById,
        occupiedOffsetsByRoom: occupiedOffsetsByRoom,
      ),
      RentBillingMode.perRoom => _perRoomRooms(
        input: input,
        groups: groups,
        roomsById: roomsById,
        boardersById: boardersById,
        occupiedOffsetsByRoom: occupiedOffsetsByRoom,
      ),
    };

    final rentByBoarder = <String, int>{};
    for (final room in roomAllocations) {
      for (final share in room.boarderShares) {
        rentByBoarder.update(
          share.boarderId,
          (value) => value + share.rentCentavos,
          ifAbsent: () => share.rentCentavos,
        );
      }
    }
    final adjustmentsByBoarder = <String, int>{};
    for (final adjustment in input.adjustments) {
      adjustmentsByBoarder.update(
        adjustment.boarderId,
        (value) => value + adjustment.signedCentavos,
        ifAbsent: () => adjustment.signedCentavos,
      );
    }

    final groupsByBoarder = <String, List<_RoomBoarderGroup>>{};
    for (final group in groups.values) {
      groupsByBoarder.putIfAbsent(group.boarderId, () => []).add(group);
    }
    final boarderCharges =
        groupsByBoarder.entries.map((entry) {
          final boarder = boardersById[entry.key]!;
          final rent = rentByBoarder[entry.key] ?? 0;
          final adjustment = adjustmentsByBoarder[entry.key] ?? 0;
          final total = rent + adjustment;
          if (total < 0) {
            throw RentValidationException(
              '${boarder.fullName} has credits greater than their rent and charges.',
              code: 'negative-boarder-total',
            );
          }
          final occupancyIds =
              entry.value.expand((group) => group.occupancyIds).toSet().toList()
                ..sort();
          final roomIds =
              entry.value.map((group) => group.roomId).toSet().toList()..sort();
          return BoarderRentCharge(
            boarderId: entry.key,
            boarderName: boarder.fullName,
            occupancyIds: occupancyIds,
            roomIds: roomIds,
            occupancyDays: entry.value.fold(
              0,
              (sum, group) => sum + group.days,
            ),
            rentCentavos: rent,
            adjustmentCentavos: adjustment,
            totalCentavos: total,
          );
        }).toList()..sort((a, b) {
          final byName = a.boarderName.toLowerCase().compareTo(
            b.boarderName.toLowerCase(),
          );
          return byName != 0 ? byName : a.boarderId.compareTo(b.boarderId);
        });

    final totalRent = _sum(
      boarderCharges.map((item) => item.rentCentavos),
      'rent total',
    );
    final totalAdjustments = boarderCharges.fold(
      0,
      (sum, item) => sum + item.adjustmentCentavos,
    );
    final grandTotal = totalRent + totalAdjustments;
    if (grandTotal < 0 || grandTotal > RentValues.maximumAmountCentavos) {
      throw const RentValidationException(
        'The calculated total is outside the supported amount range.',
        code: 'amount-out-of-range',
      );
    }
    final roomTotal = roomAllocations.fold(
      0,
      (sum, item) => sum + item.rentCentavos,
    );
    if (roomTotal != totalRent ||
        boarderCharges.fold(0, (sum, item) => sum + item.totalCentavos) !=
            grandTotal) {
      throw const RentValidationException(
        'Rent and adjustment totals did not reconcile.',
        code: 'calculation-did-not-reconcile',
      );
    }

    final warnings = <String>[];
    if (slices.isEmpty) {
      warnings.add('No boarder occupied a room during this period.');
    }
    if (input.mode == RentBillingMode.disabled) {
      warnings.add(
        'Rent is disabled; only documented adjustments are included.',
      );
    }
    if (boarderCharges.any(
      (item) =>
          item.occupancyDays <
          input.startDate.daysUntil(input.endDateExclusive),
    )) {
      warnings.add(
        'One or more boarders have partial-period rent based on their exact occupancy dates.',
      );
    }

    return RentCalculationResult(
      startDate: input.startDate,
      endDateExclusive: input.endDateExclusive,
      mode: input.mode,
      periodDays: input.startDate.daysUntil(input.endDateExclusive),
      totalRentCentavos: totalRent,
      totalAdjustmentCentavos: totalAdjustments,
      grandTotalCentavos: grandTotal,
      roomAllocations: roomAllocations,
      boarderCharges: boarderCharges,
      adjustments: input.adjustments,
      warnings: warnings,
    );
  }

  List<RoomRentAllocation> _perBoarderRooms({
    required RentCalculationInput input,
    required Map<String, _RoomBoarderGroup> groups,
    required Map<String, Room> roomsById,
    required Map<String, Boarder> boardersById,
    required Map<String, Set<int>> occupiedOffsetsByRoom,
  }) {
    final result = <RoomRentAllocation>[];
    for (final roomId in occupiedOffsetsByRoom.keys) {
      final room = roomsById[roomId]!;
      final monthlyRent = room.defaultMonthlyRentCentavos!;
      final roomGroups = groups.values.where((item) => item.roomId == roomId);
      final shares = roomGroups.map((group) {
        final rent = _roundFraction(
          monthlyRent,
          group.days,
          input.startDate.daysUntil(input.endDateExclusive),
        );
        return RoomBoarderRentShare(
          boarderId: group.boarderId,
          boarderName: boardersById[group.boarderId]!.fullName,
          occupancyIds: group.occupancyIds.toList()..sort(),
          occupancyDays: group.days,
          rentCentavos: rent,
        );
      }).toList()..sort(_compareRoomShare);
      result.add(
        RoomRentAllocation(
          roomId: roomId,
          roomName: room.roomName,
          monthlyRentCentavos: monthlyRent,
          occupiedDays: occupiedOffsetsByRoom[roomId]!.length,
          personDays: shares.fold(0, (sum, share) => sum + share.occupancyDays),
          rentCentavos: _sum(
            shares.map((share) => share.rentCentavos),
            'room rent',
          ),
          boarderShares: shares,
        ),
      );
    }
    result.sort(_compareRoom);
    return result;
  }

  List<RoomRentAllocation> _perRoomRooms({
    required RentCalculationInput input,
    required Map<String, _RoomBoarderGroup> groups,
    required Map<String, Room> roomsById,
    required Map<String, Boarder> boardersById,
    required Map<String, Set<int>> occupiedOffsetsByRoom,
  }) {
    final result = <RoomRentAllocation>[];
    for (final roomId in occupiedOffsetsByRoom.keys) {
      final room = roomsById[roomId]!;
      final monthlyRent = room.defaultMonthlyRentCentavos!;
      final occupiedDays = occupiedOffsetsByRoom[roomId]!.length;
      final roomRent = _roundFraction(
        monthlyRent,
        occupiedDays,
        input.startDate.daysUntil(input.endDateExclusive),
      );
      final roomGroups = groups.values
          .where((item) => item.roomId == roomId)
          .toList();
      final amounts = _largestRemainder(
        total: roomRent,
        entries: roomGroups
            .map((group) => _Weight(key: group.boarderId, weight: group.days))
            .toList(),
      );
      final shares = roomGroups.map((group) {
        return RoomBoarderRentShare(
          boarderId: group.boarderId,
          boarderName: boardersById[group.boarderId]!.fullName,
          occupancyIds: group.occupancyIds.toList()..sort(),
          occupancyDays: group.days,
          rentCentavos: amounts[group.boarderId]!,
        );
      }).toList()..sort(_compareRoomShare);
      result.add(
        RoomRentAllocation(
          roomId: roomId,
          roomName: room.roomName,
          monthlyRentCentavos: monthlyRent,
          occupiedDays: occupiedDays,
          personDays: shares.fold(0, (sum, share) => sum + share.occupancyDays),
          rentCentavos: roomRent,
          boarderShares: shares,
        ),
      );
    }
    result.sort(_compareRoom);
    return result;
  }

  void _validate(RentCalculationInput input) {
    final days = input.startDate.daysUntil(input.endDateExclusive);
    if (days <= 0 || days > 366) {
      throw const RentValidationException(
        'Choose a billing period from 1 to 366 days.',
        code: 'invalid-period',
      );
    }
    final rooms = <String>{};
    for (final room in input.rooms) {
      if (!rooms.add(room.roomId)) {
        throw const RentValidationException(
          'Room identifiers must be unique.',
          code: 'duplicate-room',
        );
      }
    }
    final boarders = <String>{};
    for (final boarder in input.boarders) {
      if (!boarders.add(boarder.boarderId)) {
        throw const RentValidationException(
          'Boarder identifiers must be unique.',
          code: 'duplicate-boarder',
        );
      }
    }
    final occupancies = <String>{};
    final byBoarder = <String, List<Occupancy>>{};
    for (final occupancy in input.occupancies) {
      if (!occupancies.add(occupancy.occupancyId)) {
        throw const RentValidationException(
          'Occupancy identifiers must be unique.',
          code: 'duplicate-occupancy',
        );
      }
      if (!rooms.contains(occupancy.roomId) ||
          !boarders.contains(occupancy.boarderId) ||
          (occupancy.moveOutDate != null &&
              !occupancy.moveInDate.isBefore(occupancy.moveOutDate!))) {
        throw const RentValidationException(
          'Occupancy history is incomplete or invalid.',
          code: 'invalid-occupancy',
        );
      }
      byBoarder.putIfAbsent(occupancy.boarderId, () => []).add(occupancy);
    }
    for (final items in byBoarder.values) {
      items.sort((a, b) => a.moveInDate.compareTo(b.moveInDate));
      for (var index = 1; index < items.length; index++) {
        final previousEnd = items[index - 1].moveOutDate;
        if (previousEnd == null ||
            items[index].moveInDate.isBefore(previousEnd)) {
          throw const RentValidationException(
            'A boarder has overlapping occupancy history.',
            code: 'overlapping-occupancy',
          );
        }
      }
    }
    if (input.mode != RentBillingMode.disabled) {
      final occupiedRoomIds = _slices(input)
          .map((slice) => slice.roomId)
          .toSet();
      for (final room in input.rooms.where(
        (item) => occupiedRoomIds.contains(item.roomId),
      )) {
        final rent = room.defaultMonthlyRentCentavos;
        if (rent == null) {
          throw RentValidationException(
            'Set a monthly rent for ${room.roomName} before calculating.',
            code: 'missing-room-rent',
          );
        }
        if (rent < 0 || rent > RentValues.maximumAmountCentavos) {
          throw const RentValidationException(
            'A room rent is outside the supported amount range.',
            code: 'amount-out-of-range',
          );
        }
      }
    }
    final adjustmentIds = <String>{};
    final eligibleBoarders = _slices(input)
        .map((slice) => slice.boarderId)
        .toSet();
    for (final adjustment in input.adjustments) {
      if (adjustment.adjustmentId.trim().isEmpty ||
          !adjustmentIds.add(adjustment.adjustmentId) ||
          !eligibleBoarders.contains(adjustment.boarderId) ||
          adjustment.amountCentavos <= 0 ||
          adjustment.amountCentavos > RentValues.maximumAmountCentavos ||
          adjustment.reason.trim().length < 3 ||
          adjustment.reason.trim().length > 500 ||
          adjustment.adjustmentDate.isBefore(input.startDate) ||
          !adjustment.adjustmentDate.isBefore(input.endDateExclusive)) {
        throw const RentValidationException(
          'An adjustment has invalid boarder, amount, reason, or date.',
          code: 'invalid-adjustment',
        );
      }
    }
  }

  List<_OccupancySlice> _slices(RentCalculationInput input) {
    final result = <_OccupancySlice>[];
    for (final occupancy in input.occupancies) {
      final start = occupancy.moveInDate.isAfter(input.startDate)
          ? occupancy.moveInDate
          : input.startDate;
      final occupancyEnd = occupancy.moveOutDate;
      final end =
          occupancyEnd != null && occupancyEnd.isBefore(input.endDateExclusive)
          ? occupancyEnd
          : input.endDateExclusive;
      if (start.isBefore(end)) {
        result.add(
          _OccupancySlice(
            occupancyId: occupancy.occupancyId,
            boarderId: occupancy.boarderId,
            roomId: occupancy.roomId,
            start: start,
            days: start.daysUntil(end),
          ),
        );
      }
    }
    return result;
  }

  int _roundFraction(int amount, int numerator, int denominator) {
    final product = BigInt.from(amount) * BigInt.from(numerator);
    final divisor = BigInt.from(denominator);
    final rounded = (product * BigInt.two + divisor) ~/ (divisor * BigInt.two);
    if (rounded > BigInt.from(RentValues.maximumAmountCentavos)) {
      throw const RentValidationException(
        'A calculated rent exceeds the supported amount range.',
        code: 'amount-out-of-range',
      );
    }
    return rounded.toInt();
  }

  Map<String, int> _largestRemainder({
    required int total,
    required List<_Weight> entries,
  }) {
    final weightTotal = entries.fold(0, (sum, item) => sum + item.weight);
    if (entries.isEmpty || weightTotal <= 0) return const {};
    final divisor = BigInt.from(weightTotal);
    final rows = entries.map((entry) {
      final numerator = BigInt.from(total) * BigInt.from(entry.weight);
      return _Remainder(
        key: entry.key,
        amount: (numerator ~/ divisor).toInt(),
        remainder: numerator.remainder(divisor),
      );
    }).toList();
    var remaining = total - rows.fold(0, (sum, row) => sum + row.amount);
    rows.sort((a, b) {
      final byRemainder = b.remainder.compareTo(a.remainder);
      return byRemainder != 0 ? byRemainder : a.key.compareTo(b.key);
    });
    for (var index = 0; index < remaining; index++) {
      rows[index].amount++;
    }
    return {for (final row in rows) row.key: row.amount};
  }

  int _sum(Iterable<int> values, String label) {
    var total = BigInt.zero;
    for (final value in values) {
      total += BigInt.from(value);
    }
    if (total > BigInt.from(RentValues.maximumAmountCentavos)) {
      throw RentValidationException(
        'The $label exceeds the supported amount range.',
        code: 'amount-out-of-range',
      );
    }
    return total.toInt();
  }

  int _compareRoomShare(RoomBoarderRentShare a, RoomBoarderRentShare b) {
    final byName = a.boarderName.toLowerCase().compareTo(
      b.boarderName.toLowerCase(),
    );
    return byName != 0 ? byName : a.boarderId.compareTo(b.boarderId);
  }

  int _compareRoom(RoomRentAllocation a, RoomRentAllocation b) {
    final byName = a.roomName.toLowerCase().compareTo(b.roomName.toLowerCase());
    return byName != 0 ? byName : a.roomId.compareTo(b.roomId);
  }
}

class _OccupancySlice {
  const _OccupancySlice({
    required this.occupancyId,
    required this.boarderId,
    required this.roomId,
    required this.start,
    required this.days,
  });

  final String occupancyId;
  final String boarderId;
  final String roomId;
  final BusinessDate start;
  final int days;
}

class _RoomBoarderGroup {
  _RoomBoarderGroup({required this.roomId, required this.boarderId});

  final String roomId;
  final String boarderId;
  final Set<String> occupancyIds = {};
  int days = 0;
}

class _Weight {
  const _Weight({required this.key, required this.weight});
  final String key;
  final int weight;
}

class _Remainder {
  _Remainder({
    required this.key,
    required this.amount,
    required this.remainder,
  });
  final String key;
  int amount;
  final BigInt remainder;
}
