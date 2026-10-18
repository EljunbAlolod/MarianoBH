import '../../electricity/domain/electricity_models.dart';
import '../../property_management/domain/boarder.dart';
import '../../property_management/domain/occupancy.dart';
import '../../property_management/domain/room.dart';
import 'water_models.dart';
import 'water_values.dart';
import 'water_selection.dart';

import 'dart:convert';

/// Pure, deterministic water allocation using integer centavos and person-days.
class WaterCalculator {
  const WaterCalculator();

  WaterCalculationResult calculate(WaterCalculationInput input) {
    _validatePeriodAndBill(input);
    final roomsById = _uniqueRooms(input.rooms);
    final boardersById = _uniqueBoarders(input.boarders);
    _validateOccupancies(input.occupancies, roomsById, boardersById);
    final slices = _occupancySlices(input);
    return switch (input.method) {
      WaterBillingMethod.selectedBoarders => _calculateSelected(input),
      WaterBillingMethod.personDays => _calculatePersonDays(
        input: input,
        slices: slices,
        roomsById: roomsById,
        boardersById: boardersById,
      ),
      WaterBillingMethod.roomDays => _calculateRoomDays(
        input: input,
        slices: slices,
        roomsById: roomsById,
      ),
      WaterBillingMethod.electricityPercentage =>
        _calculateElectricityPercentage(
          input: input,
          slices: slices,
          roomsById: roomsById,
          boardersById: boardersById,
        ),
    };
  }

  WaterCalculationResult _calculateSelected(WaterCalculationInput input) {
    final eligible = waterCandidates(
      start: input.startDate,
      end: input.endDateExclusive,
      rooms: input.rooms,
      boarders: input.boarders,
      occupancies: input.occupancies,
    );
    final decisions = {for (final d in input.decisions) d.boarderId: d};
    if (eligible.length != input.decisions.length ||
        eligible.any((candidate) {
          final d = decisions[candidate.boarderId];
          return d == null ||
              d.boarderName != candidate.boarderName ||
              d.fullPeriod != candidate.fullPeriod ||
              jsonEncode(d.occupancies.map((o) => o.toMap()).toList()) !=
                  jsonEncode(
                    candidate.occupancies.map((o) => o.toMap()).toList(),
                  );
        })) {
      throw const WaterValidationException(
        'Occupancy changed. Refresh and review the eligible boarders.',
        code: 'stale-water-selection',
      );
    }
    return calculateSelectedWater(
      start: input.startDate,
      end: input.endDateExclusive,
      amount: input.waterBillCentavos,
      decisions: input.decisions,
    );
  }

  WaterCalculationResult _calculateRoomDays({
    required WaterCalculationInput input,
    required List<_OccupancySlice> slices,
    required Map<String, Room> roomsById,
  }) {
    final offsetsByRoom = <String, Set<int>>{};
    for (final occupancy in input.occupancies) {
      final overlapStart = occupancy.moveInDate.isAfter(input.startDate)
          ? occupancy.moveInDate
          : input.startDate;
      final moveOut = occupancy.moveOutDate;
      final overlapEnd =
          moveOut != null && moveOut.isBefore(input.endDateExclusive)
          ? moveOut
          : input.endDateExclusive;
      if (!overlapStart.isBefore(overlapEnd)) continue;
      final offsets = offsetsByRoom.putIfAbsent(
        occupancy.roomId,
        () => <int>{},
      );
      final first = input.startDate.daysUntil(overlapStart);
      for (var day = 0; day < overlapStart.daysUntil(overlapEnd); day++) {
        offsets.add(first + day);
      }
    }
    final ordered =
        offsetsByRoom.entries.where((entry) => entry.value.isNotEmpty).toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final totalRoomDays = _sum(
      ordered.map((entry) => entry.value.length),
      label: 'Total occupied room-days',
    );
    if (ordered.isEmpty) {
      return WaterCalculationResult(
        startDate: input.startDate,
        endDateExclusive: input.endDateExclusive,
        waterBillCentavos: input.waterBillCentavos,
        method: input.method,
        summerBasis: input.summerBasis,
        electricityRecordId: null,
        totalPersonDays: 0,
        totalElectricityBasis: 0,
        totalAllocatedCentavos: 0,
        totalUnallocatedCentavos: input.waterBillCentavos,
        roomAllocations: const [],
        boarderShares: const [],
        warnings: const [
          'No room was occupied during this period. The water bill remains landlady-paid.',
        ],
      );
    }
    final amounts = _allocateLargestRemainder(
      total: input.waterBillCentavos,
      weights: ordered.map((entry) => entry.value.length).toList(),
      tieBreakKeys: ordered.map((entry) => entry.key).toList(),
    );
    final roomAllocations = <WaterRoomAllocation>[];
    for (var index = 0; index < ordered.length; index++) {
      final entry = ordered[index];
      final room = roomsById[entry.key]!;
      roomAllocations.add(
        WaterRoomAllocation(
          roomId: room.roomId,
          roomName: room.roomName,
          electricityBasisValue: 0,
          occupancyDays: entry.value.length,
          roomChargeCentavos: amounts[index],
          allocatedCentavos: amounts[index],
          unallocatedCentavos: 0,
          boarderShares: const [],
        ),
      );
    }
    roomAllocations.sort(_compareRoomAllocations);
    final roomTotal = _sum(
      roomAllocations.map((item) => item.roomChargeCentavos),
      label: 'Room water total',
    );
    if (roomTotal != input.waterBillCentavos) {
      throw const WaterValidationException(
        'Water allocations did not reconcile to the original bill.',
        code: 'non-reconciling-total',
      );
    }
    return WaterCalculationResult(
      startDate: input.startDate,
      endDateExclusive: input.endDateExclusive,
      waterBillCentavos: input.waterBillCentavos,
      method: input.method,
      summerBasis: input.summerBasis,
      electricityRecordId: null,
      totalPersonDays: totalRoomDays,
      totalElectricityBasis: 0,
      totalAllocatedCentavos: input.waterBillCentavos,
      totalUnallocatedCentavos: 0,
      roomAllocations: roomAllocations,
      boarderShares: const [],
      warnings: const [],
    );
  }

  WaterCalculationResult _calculatePersonDays({
    required WaterCalculationInput input,
    required List<_OccupancySlice> slices,
    required Map<String, Room> roomsById,
    required Map<String, Boarder> boardersById,
  }) {
    final weights = _boarderWeights(slices);
    final totalPersonDays = _sum(
      weights.values.map((item) => item.days),
      label: 'Total person-days',
    );
    if (weights.isEmpty) {
      return WaterCalculationResult(
        startDate: input.startDate,
        endDateExclusive: input.endDateExclusive,
        waterBillCentavos: input.waterBillCentavos,
        method: input.method,
        summerBasis: input.summerBasis,
        electricityRecordId: null,
        totalPersonDays: 0,
        totalElectricityBasis: 0,
        totalAllocatedCentavos: 0,
        totalUnallocatedCentavos: input.waterBillCentavos,
        roomAllocations: const [],
        boarderShares: const [],
        warnings: const [
          'No eligible boarder occupied the billing period. The water bill remains unallocated / landlady-paid.',
        ],
      );
    }

    final ordered = weights.values.toList()
      ..sort((a, b) => a.boarderId.compareTo(b.boarderId));
    final boarderAmounts = _allocateLargestRemainder(
      total: input.waterBillCentavos,
      weights: ordered.map((item) => item.days).toList(),
      tieBreakKeys: ordered.map((item) => item.boarderId).toList(),
    );
    final roomAccumulators = <String, _RoomAccumulator>{};
    final boarderShares = <BoarderWaterShare>[];

    for (var index = 0; index < ordered.length; index++) {
      final weight = ordered[index];
      final amount = boarderAmounts[index];
      final roomWeights = weight.rooms.values.toList()
        ..sort((a, b) => a.roomId.compareTo(b.roomId));
      final roomAmounts = _allocateLargestRemainder(
        total: amount,
        weights: roomWeights.map((item) => item.days).toList(),
        tieBreakKeys: roomWeights.map((item) => item.roomId).toList(),
      );
      for (var roomIndex = 0; roomIndex < roomWeights.length; roomIndex++) {
        final roomWeight = roomWeights[roomIndex];
        final room = roomsById[roomWeight.roomId]!;
        final accumulator = roomAccumulators.putIfAbsent(
          room.roomId,
          () => _RoomAccumulator(roomId: room.roomId, roomName: room.roomName),
        );
        accumulator.occupancyDays += roomWeight.days;
        accumulator.boarderShares.add(
          RoomBoarderWaterShare(
            boarderId: weight.boarderId,
            boarderName: boardersById[weight.boarderId]!.fullName,
            occupancyIds: _sorted(roomWeight.occupancyIds),
            occupancyDays: roomWeight.days,
            amountCentavos: roomAmounts[roomIndex],
          ),
        );
      }
      boarderShares.add(
        BoarderWaterShare(
          boarderId: weight.boarderId,
          boarderName: boardersById[weight.boarderId]!.fullName,
          occupancyIds: _sorted(weight.occupancyIds),
          roomIds: _sorted(weight.rooms.keys),
          occupancyDays: weight.days,
          amountCentavos: amount,
        ),
      );
    }

    final roomAllocations = roomAccumulators.values.map((item) {
      item.boarderShares.sort((a, b) => a.boarderId.compareTo(b.boarderId));
      final roomCharge = _sum(
        item.boarderShares.map((share) => share.amountCentavos),
        label: '${item.roomName} water charge',
      );
      return WaterRoomAllocation(
        roomId: item.roomId,
        roomName: item.roomName,
        electricityBasisValue: 0,
        occupancyDays: item.occupancyDays,
        roomChargeCentavos: roomCharge,
        allocatedCentavos: roomCharge,
        unallocatedCentavos: 0,
        boarderShares: item.boarderShares,
      );
    }).toList()..sort(_compareRoomAllocations);

    _verifyResult(
      bill: input.waterBillCentavos,
      allocated: input.waterBillCentavos,
      unallocated: 0,
      roomAllocations: roomAllocations,
      boarderShares: boarderShares,
    );
    return WaterCalculationResult(
      startDate: input.startDate,
      endDateExclusive: input.endDateExclusive,
      waterBillCentavos: input.waterBillCentavos,
      method: input.method,
      summerBasis: input.summerBasis,
      electricityRecordId: null,
      totalPersonDays: totalPersonDays,
      totalElectricityBasis: 0,
      totalAllocatedCentavos: input.waterBillCentavos,
      totalUnallocatedCentavos: 0,
      roomAllocations: roomAllocations,
      boarderShares: boarderShares,
      warnings: const [],
    );
  }

  WaterCalculationResult _calculateElectricityPercentage({
    required WaterCalculationInput input,
    required List<_OccupancySlice> slices,
    required Map<String, Room> roomsById,
    required Map<String, Boarder> boardersById,
  }) {
    final electricity = input.electricityRecord;
    if (electricity == null ||
        electricity.startDate != input.startDate ||
        electricity.endDateExclusive != input.endDateExclusive) {
      throw const WaterValidationException(
        'Summer allocation needs a saved electricity record with exactly the same start and end dates.',
        code: 'missing-electricity-record',
      );
    }
    final electricityRooms = <String, RoomElectricityCharge>{};
    for (final roomCharge in electricity.roomCharges) {
      if (!roomsById.containsKey(roomCharge.roomId) ||
          electricityRooms.containsKey(roomCharge.roomId)) {
        throw const WaterValidationException(
          'The linked electricity record has an invalid room breakdown.',
          code: 'invalid-electricity-record',
        );
      }
      electricityRooms[roomCharge.roomId] = roomCharge;
    }
    final occupiedRoomIds = slices.map((item) => item.roomId).toSet();
    if (occupiedRoomIds.any(
      (roomId) => !electricityRooms.containsKey(roomId),
    )) {
      throw const WaterValidationException(
        'Every occupied room needs an electricity basis for the selected period.',
        code: 'incomplete-electricity-basis',
      );
    }

    final orderedElectricityRooms = electricityRooms.values.toList()
      ..sort((a, b) => a.roomId.compareTo(b.roomId));
    final basisValues = orderedElectricityRooms.map((room) {
      return switch (input.summerBasis) {
        SummerElectricityBasis.roomElectricityCharge => room.baseChargeCentavos,
        SummerElectricityBasis.roomConsumption => room.consumptionWh,
      };
    }).toList();
    final totalBasis = _sum(basisValues, label: 'Total electricity basis');
    if (totalBasis == 0) {
      throw const WaterValidationException(
        'The selected electricity basis totals zero. Choose person-days or save a period with positive electricity usage.',
        code: 'no-electricity-basis',
      );
    }
    final roomAmounts = _allocateLargestRemainder(
      total: input.waterBillCentavos,
      weights: basisValues,
      tieBreakKeys: orderedElectricityRooms.map((item) => item.roomId).toList(),
    );
    final slicesByRoom = <String, List<_OccupancySlice>>{};
    for (final slice in slices) {
      slicesByRoom.putIfAbsent(slice.roomId, () => []).add(slice);
    }
    final roomAllocations = <WaterRoomAllocation>[];
    final warnings = <String>[];

    for (var index = 0; index < orderedElectricityRooms.length; index++) {
      final source = orderedElectricityRooms[index];
      final roomAmount = roomAmounts[index];
      final roomSlices = slicesByRoom[source.roomId] ?? const [];
      final roomWeights = _boarderWeights(roomSlices).values.toList()
        ..sort((a, b) => a.boarderId.compareTo(b.boarderId));
      final roomPersonDays = _sum(
        roomWeights.map((item) => item.days),
        label: '${source.roomName} person-days',
      );
      final shares = <RoomBoarderWaterShare>[];
      var allocated = 0;
      var unallocated = 0;
      if (roomWeights.isEmpty) {
        unallocated = roomAmount;
        if (roomAmount > 0) {
          warnings.add(
            '${source.roomName} has a water share but no eligible occupant; ${_centavoText(roomAmount)} remains unallocated / landlady-paid.',
          );
        }
      } else {
        final amounts = _allocateLargestRemainder(
          total: roomAmount,
          weights: roomWeights.map((item) => item.days).toList(),
          tieBreakKeys: roomWeights.map((item) => item.boarderId).toList(),
        );
        for (
          var shareIndex = 0;
          shareIndex < roomWeights.length;
          shareIndex++
        ) {
          final weight = roomWeights[shareIndex];
          shares.add(
            RoomBoarderWaterShare(
              boarderId: weight.boarderId,
              boarderName: boardersById[weight.boarderId]!.fullName,
              occupancyIds: _sorted(weight.occupancyIds),
              occupancyDays: weight.days,
              amountCentavos: amounts[shareIndex],
            ),
          );
          allocated += amounts[shareIndex];
        }
      }
      if (basisValues[index] == 0 && roomPersonDays > 0) {
        warnings.add(
          '${source.roomName} has eligible occupants but a zero electricity basis, so its water share is ₱0.00.',
        );
      }
      roomAllocations.add(
        WaterRoomAllocation(
          roomId: source.roomId,
          roomName: source.roomName,
          electricityBasisValue: basisValues[index],
          occupancyDays: roomPersonDays,
          roomChargeCentavos: roomAmount,
          allocatedCentavos: allocated,
          unallocatedCentavos: unallocated,
          boarderShares: shares,
        ),
      );
    }
    roomAllocations.sort(_compareRoomAllocations);
    final boarderShares = _aggregateBoarderShares(
      roomAllocations,
      slices,
      boardersById,
    );
    final allocated = _sum(
      roomAllocations.map((item) => item.allocatedCentavos),
      label: 'Allocated water total',
    );
    final unallocated = _sum(
      roomAllocations.map((item) => item.unallocatedCentavos),
      label: 'Unallocated water total',
    );
    final totalPersonDays = _sum(
      _boarderWeights(slices).values.map((item) => item.days),
      label: 'Total person-days',
    );
    _verifyResult(
      bill: input.waterBillCentavos,
      allocated: allocated,
      unallocated: unallocated,
      roomAllocations: roomAllocations,
      boarderShares: boarderShares,
    );
    return WaterCalculationResult(
      startDate: input.startDate,
      endDateExclusive: input.endDateExclusive,
      waterBillCentavos: input.waterBillCentavos,
      method: input.method,
      summerBasis: input.summerBasis,
      electricityRecordId: electricity.billingRecordId,
      totalPersonDays: totalPersonDays,
      totalElectricityBasis: totalBasis,
      totalAllocatedCentavos: allocated,
      totalUnallocatedCentavos: unallocated,
      roomAllocations: roomAllocations,
      boarderShares: boarderShares,
      warnings: warnings,
    );
  }

  void _validatePeriodAndBill(WaterCalculationInput input) {
    if (!input.startDate.isBefore(input.endDateExclusive)) {
      throw const WaterValidationException(
        'The billing period end must be after its start.',
        code: 'invalid-period',
      );
    }
    if (input.waterBillCentavos < 0 ||
        input.waterBillCentavos > WaterValues.maximumBillCentavos) {
      throw const WaterValidationException(
        'The water bill is outside the supported range.',
        code: 'value-out-of-range',
      );
    }
  }

  Map<String, Room> _uniqueRooms(List<Room> rooms) {
    final result = <String, Room>{};
    for (final room in rooms) {
      if (room.roomId.trim().isEmpty || result.containsKey(room.roomId)) {
        throw const WaterValidationException(
          'Room identifiers must be non-empty and unique.',
          code: 'duplicate-room',
        );
      }
      result[room.roomId] = room;
    }
    return result;
  }

  Map<String, Boarder> _uniqueBoarders(List<Boarder> boarders) {
    final result = <String, Boarder>{};
    for (final boarder in boarders) {
      if (boarder.boarderId.trim().isEmpty ||
          result.containsKey(boarder.boarderId)) {
        throw const WaterValidationException(
          'Boarder identifiers must be non-empty and unique.',
          code: 'duplicate-boarder',
        );
      }
      result[boarder.boarderId] = boarder;
    }
    return result;
  }

  void _validateOccupancies(
    List<Occupancy> occupancies,
    Map<String, Room> roomsById,
    Map<String, Boarder> boardersById,
  ) {
    final ids = <String>{};
    final byBoarder = <String, List<Occupancy>>{};
    for (final occupancy in occupancies) {
      if (occupancy.occupancyId.trim().isEmpty ||
          !ids.add(occupancy.occupancyId)) {
        throw const WaterValidationException(
          'Occupancy identifiers must be non-empty and unique.',
          code: 'duplicate-occupancy',
        );
      }
      if (!roomsById.containsKey(occupancy.roomId) ||
          !boardersById.containsKey(occupancy.boarderId)) {
        throw const WaterValidationException(
          'An occupancy refers to a missing room or boarder.',
          code: 'invalid-occupancy-reference',
        );
      }
      final moveOut = occupancy.moveOutDate;
      if (moveOut != null && !occupancy.moveInDate.isBefore(moveOut)) {
        throw const WaterValidationException(
          'An occupancy has an invalid date range.',
          code: 'invalid-occupancy',
        );
      }
      byBoarder.putIfAbsent(occupancy.boarderId, () => []).add(occupancy);
    }
    for (final entries in byBoarder.values) {
      entries.sort((a, b) => a.moveInDate.compareTo(b.moveInDate));
      for (var index = 1; index < entries.length; index++) {
        final previous = entries[index - 1];
        final current = entries[index];
        if (previous.moveOutDate == null ||
            current.moveInDate.isBefore(previous.moveOutDate!)) {
          throw const WaterValidationException(
            'A boarder has overlapping occupancies.',
            code: 'overlapping-occupancy',
          );
        }
      }
    }
  }

  List<_OccupancySlice> _occupancySlices(WaterCalculationInput input) {
    final result = <_OccupancySlice>[];
    for (final occupancy in input.occupancies) {
      final start = occupancy.moveInDate.isAfter(input.startDate)
          ? occupancy.moveInDate
          : input.startDate;
      final moveOut = occupancy.moveOutDate;
      final end = moveOut != null && moveOut.isBefore(input.endDateExclusive)
          ? moveOut
          : input.endDateExclusive;
      if (!start.isBefore(end)) continue;
      result.add(
        _OccupancySlice(
          occupancyId: occupancy.occupancyId,
          boarderId: occupancy.boarderId,
          roomId: occupancy.roomId,
          days: start.daysUntil(end),
        ),
      );
    }
    return result;
  }

  Map<String, _BoarderWeight> _boarderWeights(List<_OccupancySlice> slices) {
    final result = <String, _BoarderWeight>{};
    for (final slice in slices) {
      final boarder = result.putIfAbsent(
        slice.boarderId,
        () => _BoarderWeight(slice.boarderId),
      );
      boarder.days += slice.days;
      boarder.occupancyIds.add(slice.occupancyId);
      final room = boarder.rooms.putIfAbsent(
        slice.roomId,
        () => _RoomWeight(slice.roomId),
      );
      room.days += slice.days;
      room.occupancyIds.add(slice.occupancyId);
    }
    return result;
  }

  List<BoarderWaterShare> _aggregateBoarderShares(
    List<WaterRoomAllocation> rooms,
    List<_OccupancySlice> slices,
    Map<String, Boarder> boardersById,
  ) {
    final aggregates = <String, _BoarderShareAccumulator>{};
    for (final room in rooms) {
      for (final share in room.boarderShares) {
        final item = aggregates.putIfAbsent(
          share.boarderId,
          () => _BoarderShareAccumulator(share.boarderId),
        );
        item.amountCentavos += share.amountCentavos;
        item.rooms.add(room.roomId);
      }
    }
    for (final slice in slices) {
      final item = aggregates[slice.boarderId];
      if (item == null) continue;
      item.days += slice.days;
      item.occupancyIds.add(slice.occupancyId);
    }
    return aggregates.values.map((item) {
      return BoarderWaterShare(
        boarderId: item.boarderId,
        boarderName: boardersById[item.boarderId]!.fullName,
        occupancyIds: _sorted(item.occupancyIds),
        roomIds: _sorted(item.rooms),
        occupancyDays: item.days,
        amountCentavos: item.amountCentavos,
      );
    }).toList()..sort((a, b) => a.boarderId.compareTo(b.boarderId));
  }

  List<int> _allocateLargestRemainder({
    required int total,
    required List<int> weights,
    required List<String> tieBreakKeys,
  }) {
    if (total < 0 ||
        weights.length != tieBreakKeys.length ||
        weights.any((weight) => weight < 0)) {
      throw const WaterValidationException(
        'A water allocation request is invalid.',
        code: 'invalid-allocation',
      );
    }
    final totalWeight = weights.fold<BigInt>(
      BigInt.zero,
      (sum, value) => sum + BigInt.from(value),
    );
    if (totalWeight == BigInt.zero) {
      if (total == 0) return List.filled(weights.length, 0);
      throw const WaterValidationException(
        'A positive amount cannot be divided using a zero basis.',
        code: 'zero-allocation-basis',
      );
    }
    final amounts = List<int>.filled(weights.length, 0);
    final remainders = <_Remainder>[];
    var floorTotal = 0;
    for (var index = 0; index < weights.length; index++) {
      final numerator = BigInt.from(total) * BigInt.from(weights[index]);
      final floor = numerator ~/ totalWeight;
      amounts[index] = floor.toInt();
      floorTotal += amounts[index];
      if (weights[index] > 0) {
        remainders.add(
          _Remainder(
            index: index,
            value: numerator.remainder(totalWeight),
            tieBreakKey: tieBreakKeys[index],
          ),
        );
      }
    }
    remainders.sort((a, b) {
      final remainder = b.value.compareTo(a.value);
      return remainder != 0
          ? remainder
          : a.tieBreakKey.compareTo(b.tieBreakKey);
    });
    final leftover = total - floorTotal;
    if (leftover < 0 || leftover > remainders.length) {
      throw const WaterValidationException(
        'Water allocation did not reconcile.',
        code: 'non-reconciling-total',
      );
    }
    for (var index = 0; index < leftover; index++) {
      amounts[remainders[index].index]++;
    }
    return amounts;
  }

  void _verifyResult({
    required int bill,
    required int allocated,
    required int unallocated,
    required List<WaterRoomAllocation> roomAllocations,
    required List<BoarderWaterShare> boarderShares,
  }) {
    final roomTotal = _sum(
      roomAllocations.map((item) => item.roomChargeCentavos),
      label: 'Room water total',
    );
    final boarderTotal = _sum(
      boarderShares.map((item) => item.amountCentavos),
      label: 'Boarder water total',
    );
    if (bill != allocated + unallocated ||
        roomTotal != bill ||
        boarderTotal != allocated ||
        roomAllocations.any(
          (room) =>
              room.roomChargeCentavos !=
              room.allocatedCentavos + room.unallocatedCentavos,
        )) {
      throw const WaterValidationException(
        'Water allocations did not reconcile to the original bill.',
        code: 'non-reconciling-total',
      );
    }
  }

  int _sum(Iterable<int> values, {required String label}) {
    var total = BigInt.zero;
    for (final value in values) {
      if (value < 0) {
        throw WaterValidationException(
          '$label cannot contain a negative value.',
          code: 'negative-value',
        );
      }
      total += BigInt.from(value);
    }
    if (total > BigInt.from(WaterValues.maximumBillCentavos)) {
      throw WaterValidationException(
        '$label is outside the supported range.',
        code: 'value-out-of-range',
      );
    }
    return total.toInt();
  }

  List<String> _sorted(Iterable<String> values) => values.toList()..sort();

  static int _compareRoomAllocations(
    WaterRoomAllocation a,
    WaterRoomAllocation b,
  ) {
    final name = a.roomName.toLowerCase().compareTo(b.roomName.toLowerCase());
    return name != 0 ? name : a.roomId.compareTo(b.roomId);
  }

  String _centavoText(int centavos) {
    final whole = centavos ~/ 100;
    final fraction = (centavos % 100).toString().padLeft(2, '0');
    return '₱$whole.$fraction';
  }
}

class _OccupancySlice {
  const _OccupancySlice({
    required this.occupancyId,
    required this.boarderId,
    required this.roomId,
    required this.days,
  });

  final String occupancyId;
  final String boarderId;
  final String roomId;
  final int days;
}

class _BoarderWeight {
  _BoarderWeight(this.boarderId);

  final String boarderId;
  int days = 0;
  final Set<String> occupancyIds = {};
  final Map<String, _RoomWeight> rooms = {};
}

class _RoomWeight {
  _RoomWeight(this.roomId);

  final String roomId;
  int days = 0;
  final Set<String> occupancyIds = {};
}

class _RoomAccumulator {
  _RoomAccumulator({required this.roomId, required this.roomName});

  final String roomId;
  final String roomName;
  int occupancyDays = 0;
  final List<RoomBoarderWaterShare> boarderShares = [];
}

class _BoarderShareAccumulator {
  _BoarderShareAccumulator(this.boarderId);

  final String boarderId;
  int days = 0;
  int amountCentavos = 0;
  final Set<String> occupancyIds = {};
  final Set<String> rooms = {};
}

class _Remainder {
  const _Remainder({
    required this.index,
    required this.value,
    required this.tieBreakKey,
  });

  final int index;
  final BigInt value;
  final String tieBreakKey;
}
