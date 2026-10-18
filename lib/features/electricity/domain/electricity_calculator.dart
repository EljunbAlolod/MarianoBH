import '../../property_management/domain/boarder.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/domain/occupancy.dart';
import '../../property_management/domain/room.dart';
import 'electricity_models.dart';
import 'electricity_values.dart';

/// Pure, deterministic electricity calculation engine.
///
/// Dates use half-open ranges and all arithmetic is integer/BigInt based. The
/// calculator never reads Firebase state and never uses binary floating point.
class ElectricityCalculator {
  const ElectricityCalculator();

  ElectricityCalculationResult calculate(ElectricityCalculationInput input) {
    _validatePeriod(input);

    final roomsById = _uniqueRooms(input.rooms);
    final boardersById = _uniqueBoarders(input.boarders);
    _validateOccupancies(input.occupancies, boardersById);
    final metersByRoom = _validateMetersAndReadings(
      input.meters,
      input.readings,
      roomsById,
    );
    final adjustmentsByRoom = _validateAdjustments(input, roomsById);

    final rooms = [...input.rooms]..sort(_compareRooms);
    final roomCharges = <RoomElectricityCharge>[];
    final warnings = <String>[];

    for (final room in rooms) {
      final meters = metersByRoom[room.roomId];
      if (meters == null || meters.isEmpty) {
        throw ElectricityValidationException(
          '${room.roomName} has no electricity meter.',
          code: 'missing-meter',
        );
      }
      final roomCharge = _calculateRoom(
        input: input,
        room: room,
        meters: meters,
        boardersById: boardersById,
        adjustments: adjustmentsByRoom[room.roomId] ?? const [],
      );
      roomCharges.add(roomCharge);
      if (roomCharge.hasEstimatedShares) {
        warnings.add(
          '${room.roomName} includes occupancy-based electricity estimates.',
        );
      }
      if (roomCharge.unallocatedCentavos > 0) {
        warnings.add(
          '${room.roomName} has an unallocated electricity charge because no '
          'eligible boarder occupied at least one usage segment.',
        );
      }
    }

    final totalConsumption = _sumNonNegative(
      roomCharges.map((item) => item.consumptionWh),
      label: 'Total electricity consumption',
    );
    final totalBase = _sumNonNegative(
      roomCharges.map((item) => item.baseChargeCentavos),
      label: 'Total base electricity charge',
    );
    final totalAdjustments = _sumSigned(
      roomCharges.map((item) => item.adjustmentCentavos),
      label: 'Total electricity adjustments',
    );
    final totalCharge = _sumNonNegative(
      roomCharges.map((item) => item.finalChargeCentavos),
      label: 'Total electricity charge',
    );
    final totalAllocated = _sumNonNegative(
      roomCharges.map((item) => item.allocatedCentavos),
      label: 'Total allocated electricity charge',
    );
    final totalUnallocated = _sumNonNegative(
      roomCharges.map((item) => item.unallocatedCentavos),
      label: 'Total unallocated electricity charge',
    );
    if (totalConsumption > ElectricityValues.maximumMeterReadingWh ||
        totalBase > ElectricityValues.maximumBillingTotalCentavos ||
        totalAdjustments.abs() >
            ElectricityValues.maximumBillingTotalCentavos ||
        totalCharge > ElectricityValues.maximumBillingTotalCentavos ||
        totalAllocated > ElectricityValues.maximumBillingTotalCentavos ||
        totalUnallocated > ElectricityValues.maximumBillingTotalCentavos) {
      throw const ElectricityValidationException(
        'The electricity billing totals are outside the supported range.',
        code: 'value-out-of-range',
      );
    }
    if (totalBase + totalAdjustments != totalCharge ||
        totalAllocated + totalUnallocated != totalCharge) {
      throw const ElectricityValidationException(
        'Electricity totals did not reconcile.',
        code: 'non-reconciling-total',
      );
    }

    return ElectricityCalculationResult(
      startDate: input.startDate,
      endDateExclusive: input.endDateExclusive,
      rateMicropesosPerKwh: input.rateMicropesosPerKwh,
      roomCharges: roomCharges,
      totalConsumptionWh: totalConsumption,
      totalBaseChargeCentavos: totalBase,
      totalAdjustmentsCentavos: totalAdjustments,
      totalChargeCentavos: totalCharge,
      totalAllocatedCentavos: totalAllocated,
      totalUnallocatedCentavos: totalUnallocated,
      warnings: warnings,
    );
  }

  void _validatePeriod(ElectricityCalculationInput input) {
    if (!input.endDateExclusive.isAfter(input.startDate)) {
      throw const ElectricityValidationException(
        'The billing period end must be after its start.',
        code: 'invalid-period',
      );
    }
    if (input.rateMicropesosPerKwh <= 0 ||
        input.rateMicropesosPerKwh >
            ElectricityValues.maximumRateMicropesosPerKwh) {
      throw const ElectricityValidationException(
        'The electricity rate must be within the supported range.',
        code: 'invalid-rate',
      );
    }
  }

  Map<String, Room> _uniqueRooms(List<Room> rooms) {
    final result = <String, Room>{};
    for (final room in rooms) {
      if (room.roomId.trim().isEmpty || result.containsKey(room.roomId)) {
        throw const ElectricityValidationException(
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
        throw const ElectricityValidationException(
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
    Map<String, Boarder> boardersById,
  ) {
    final ids = <String>{};
    final byBoarder = <String, List<Occupancy>>{};
    for (final occupancy in occupancies) {
      if (occupancy.occupancyId.trim().isEmpty ||
          !ids.add(occupancy.occupancyId)) {
        throw const ElectricityValidationException(
          'Occupancy identifiers must be non-empty and unique.',
          code: 'duplicate-occupancy',
        );
      }
      if (!boardersById.containsKey(occupancy.boarderId)) {
        throw ElectricityValidationException(
          'Occupancy ${occupancy.occupancyId} refers to a missing boarder.',
          code: 'unknown-boarder',
        );
      }
      final moveOut = occupancy.moveOutDate;
      if (moveOut != null && !moveOut.isAfter(occupancy.moveInDate)) {
        throw const ElectricityValidationException(
          'An occupancy has an invalid date range.',
          code: 'invalid-occupancy',
        );
      }
      byBoarder.putIfAbsent(occupancy.boarderId, () => []).add(occupancy);
    }

    for (final entries in byBoarder.values) {
      entries.sort((a, b) {
        final byDate = a.moveInDate.compareTo(b.moveInDate);
        return byDate != 0 ? byDate : a.occupancyId.compareTo(b.occupancyId);
      });
      for (var index = 1; index < entries.length; index++) {
        final previous = entries[index - 1];
        final current = entries[index];
        if (previous.moveOutDate == null ||
            current.moveInDate.isBefore(previous.moveOutDate!)) {
          throw ElectricityValidationException(
            'Boarder ${current.boarderId} has overlapping occupancies.',
            code: 'overlapping-occupancy',
          );
        }
      }
    }
  }

  Map<String, List<ElectricityMeter>> _validateMetersAndReadings(
    List<ElectricityMeter> meters,
    List<MeterReading> readings,
    Map<String, Room> roomsById,
  ) {
    final metersById = <String, ElectricityMeter>{};
    final metersByRoom = <String, List<ElectricityMeter>>{};
    for (final meter in meters) {
      if (meter.meterId.trim().isEmpty ||
          metersById.containsKey(meter.meterId)) {
        throw const ElectricityValidationException(
          'Meter identifiers must be non-empty and unique.',
          code: 'duplicate-meter',
        );
      }
      if (!roomsById.containsKey(meter.roomId)) {
        throw ElectricityValidationException(
          'Meter ${meter.meterId} refers to a missing room.',
          code: 'unknown-room',
        );
      }
      _validateMeterMetadata(meter);
      metersById[meter.meterId] = meter;
      metersByRoom.putIfAbsent(meter.roomId, () => []).add(meter);
    }

    final readingIds = <String>{};
    final readingsByMeter = <String, List<MeterReading>>{};
    for (final reading in readings) {
      if (reading.readingId.trim().isEmpty ||
          !readingIds.add(reading.readingId)) {
        throw const ElectricityValidationException(
          'Reading identifiers must be non-empty and unique.',
          code: 'duplicate-reading',
        );
      }
      final meter = metersById[reading.meterId];
      if (meter == null ||
          reading.roomId != meter.roomId ||
          reading.sequence != meter.sequence) {
        throw ElectricityValidationException(
          'Reading ${reading.readingId} does not match its meter sequence.',
          code: 'reading-meter-mismatch',
        );
      }
      if (reading.readingWh < 0 || reading.consumptionWh < 0) {
        throw const ElectricityValidationException(
          'Meter consumption cannot be negative.',
          code: 'negative-consumption',
        );
      }
      if (reading.readingWh > ElectricityValues.maximumMeterReadingWh ||
          reading.consumptionWh > ElectricityValues.maximumMeterReadingWh) {
        throw const ElectricityValidationException(
          'Meter readings and consumption must be within the supported range.',
          code: 'invalid-reading-range',
        );
      }
      readingsByMeter.putIfAbsent(reading.meterId, () => []).add(reading);
    }

    for (final meter in meters) {
      final meterReadings = readingsByMeter[meter.meterId];
      if (meterReadings == null || meterReadings.isEmpty) {
        throw ElectricityValidationException(
          'Meter ${meter.meterId} has no readings.',
          code: 'missing-reading',
        );
      }
      _validateReadingChain(meter, meterReadings);
    }

    for (final roomMeters in metersByRoom.values) {
      roomMeters.sort((a, b) => a.sequence.compareTo(b.sequence));
      _validateMeterChain(roomMeters);
    }
    return metersByRoom;
  }

  void _validateMeterMetadata(ElectricityMeter meter) {
    if (meter.sequence < 1 ||
        meter.lastReadingId.trim().isEmpty ||
        meter.lastReadingWh < 0 ||
        meter.lastReadingWh > ElectricityValues.maximumMeterReadingWh ||
        meter.lastReadingDate.isBefore(meter.startedOn)) {
      throw ElectricityValidationException(
        'Meter ${meter.meterId} has invalid metadata.',
        code: 'invalid-meter',
      );
    }
    if (meter.startKind == ElectricityMeterStartKind.initial) {
      if (meter.sequence != 1 || meter.previousMeterId != null) {
        throw ElectricityValidationException(
          'Initial meter ${meter.meterId} must begin sequence 1.',
          code: 'invalid-meter',
        );
      }
    } else if (meter.sequence == 1 ||
        meter.previousMeterId == null ||
        (meter.transitionReason?.trim().isEmpty ?? true)) {
      throw ElectricityValidationException(
        'Meter ${meter.meterId} needs a previous meter and transition reason.',
        code: 'invalid-meter-transition',
      );
    }
    switch (meter.status) {
      case ElectricityMeterStatus.active:
        if (meter.endedOn != null || meter.replacementMeterId != null) {
          throw ElectricityValidationException(
            'Active meter ${meter.meterId} cannot have an end or replacement.',
            code: 'invalid-meter',
          );
        }
      case ElectricityMeterStatus.retired:
        if (meter.endedOn == null ||
            !meter.endedOn!.isAfter(meter.startedOn) ||
            meter.replacementMeterId == null ||
            meter.lastReadingDate != meter.endedOn) {
          throw ElectricityValidationException(
            'Retired meter ${meter.meterId} has incomplete transition metadata.',
            code: 'invalid-meter-transition',
          );
        }
    }
  }

  void _validateReadingChain(
    ElectricityMeter meter,
    List<MeterReading> readings,
  ) {
    readings.sort((a, b) {
      final byDate = a.readingDate.compareTo(b.readingDate);
      return byDate != 0 ? byDate : a.readingId.compareTo(b.readingId);
    });
    final first = readings.first;
    if (first.kind != MeterReadingKind.opening ||
        first.readingDate != meter.startedOn ||
        first.previousReadingId != null ||
        first.previousReadingDate != null ||
        first.previousReadingWh != null ||
        first.consumptionWh != 0) {
      throw ElectricityValidationException(
        'Meter ${meter.meterId} must start with a zero-consumption opening reading.',
        code: 'invalid-opening-reading',
      );
    }
    for (var index = 1; index < readings.length; index++) {
      final previous = readings[index - 1];
      final current = readings[index];
      if (!current.readingDate.isAfter(previous.readingDate)) {
        throw ElectricityValidationException(
          'Meter ${meter.meterId} has a duplicate or backdated reading.',
          code: 'duplicate-reading-date',
        );
      }
      if (current.kind == MeterReadingKind.opening ||
          current.previousReadingId != previous.readingId ||
          current.previousReadingDate != previous.readingDate ||
          current.previousReadingWh != previous.readingWh) {
        throw ElectricityValidationException(
          'Reading ${current.readingId} does not continue its meter sequence.',
          code: 'noncontiguous-readings',
        );
      }
      final consumption = current.readingWh - previous.readingWh;
      if (consumption < 0 || current.consumptionWh < 0) {
        throw const ElectricityValidationException(
          'Meter consumption cannot be negative.',
          code: 'negative-consumption',
        );
      }
      if (current.consumptionWh != consumption) {
        throw ElectricityValidationException(
          'Reading ${current.readingId} has inconsistent consumption.',
          code: 'invalid-consumption',
        );
      }
    }
    final last = readings.last;
    if (meter.lastReadingId != last.readingId ||
        meter.lastReadingDate != last.readingDate ||
        meter.lastReadingWh != last.readingWh) {
      throw ElectricityValidationException(
        'Meter ${meter.meterId} does not point to its latest reading.',
        code: 'stale-meter-reading',
      );
    }
    if (meter.status == ElectricityMeterStatus.retired &&
        last.kind != MeterReadingKind.closing) {
      throw ElectricityValidationException(
        'Retired meter ${meter.meterId} must end with a closing reading.',
        code: 'missing-closing-reading',
      );
    }
    if (meter.status == ElectricityMeterStatus.active &&
        last.kind == MeterReadingKind.closing) {
      throw ElectricityValidationException(
        'An active meter cannot end with a closing reading.',
        code: 'invalid-closing-reading',
      );
    }
  }

  void _validateMeterChain(List<ElectricityMeter> meters) {
    if (meters.first.sequence != 1 ||
        meters.first.startKind != ElectricityMeterStartKind.initial) {
      throw const ElectricityValidationException(
        'Every room meter history must start with an initial sequence.',
        code: 'noncontiguous-meter-transition',
      );
    }
    for (var index = 1; index < meters.length; index++) {
      final previous = meters[index - 1];
      final current = meters[index];
      if (previous.status != ElectricityMeterStatus.retired ||
          previous.replacementMeterId != current.meterId ||
          current.previousMeterId != previous.meterId ||
          current.sequence != previous.sequence + 1 ||
          current.startedOn != previous.endedOn) {
        throw const ElectricityValidationException(
          'Meter transitions must form one contiguous sequence.',
          code: 'noncontiguous-meter-transition',
        );
      }
    }
    if (meters.last.status != ElectricityMeterStatus.active) {
      throw const ElectricityValidationException(
        'Every room must have one current active meter.',
        code: 'missing-active-meter',
      );
    }
  }

  Map<String, List<ElectricityAdjustment>> _validateAdjustments(
    ElectricityCalculationInput input,
    Map<String, Room> roomsById,
  ) {
    final ids = <String>{};
    final result = <String, List<ElectricityAdjustment>>{};
    for (final adjustment in input.adjustments) {
      if (adjustment.adjustmentId.trim().isEmpty ||
          !ids.add(adjustment.adjustmentId) ||
          !roomsById.containsKey(adjustment.roomId) ||
          adjustment.magnitudeCentavos <= 0 ||
          adjustment.reason.trim().isEmpty ||
          adjustment.reason.trim().length > 500 ||
          adjustment.adjustmentDate.isBefore(input.startDate) ||
          !adjustment.adjustmentDate.isBefore(input.endDateExclusive)) {
        throw const ElectricityValidationException(
          'An electricity adjustment is invalid or outside this billing period.',
          code: 'invalid-adjustment',
        );
      }
      result.putIfAbsent(adjustment.roomId, () => []).add(adjustment);
    }
    for (final entries in result.values) {
      entries.sort((a, b) {
        final byDate = a.adjustmentDate.compareTo(b.adjustmentDate);
        return byDate != 0 ? byDate : a.adjustmentId.compareTo(b.adjustmentId);
      });
    }
    return result;
  }

  RoomElectricityCharge _calculateRoom({
    required ElectricityCalculationInput input,
    required Room room,
    required List<ElectricityMeter> meters,
    required Map<String, Boarder> boardersById,
    required List<ElectricityAdjustment> adjustments,
  }) {
    final rawSegments = _segmentsForPeriod(
      room: room,
      meters: meters,
      allReadings: input.readings,
      periodStart: input.startDate,
      periodEnd: input.endDateExclusive,
    );
    final consumptionWh = _sumNonNegative(
      rawSegments.map((item) => item.consumptionWh),
      label: '${room.roomName} electricity consumption',
    );
    final baseCharge = ElectricityValues.chargeCentavos(
      consumptionWh: consumptionWh,
      rateMicropesosPerKwh: input.rateMicropesosPerKwh,
    );
    final adjustmentTotal = _sumSigned(
      adjustments.map((item) => item.signedCentavos),
      label: '${room.roomName} electricity adjustment',
    );
    final finalBig = BigInt.from(baseCharge) + BigInt.from(adjustmentTotal);
    if (finalBig.isNegative) {
      throw ElectricityValidationException(
        '${room.roomName} adjustments would make its charge negative.',
        code: 'negative-room-charge',
      );
    }
    final finalCharge = ElectricityValues.checkedFirestoreInt(
      finalBig,
      label: '${room.roomName} final electricity charge',
    );

    final segmentAmounts = consumptionWh == 0
        ? List<int>.filled(rawSegments.length, 0)
        : _allocateLargestRemainder(
            total: finalCharge,
            weights: rawSegments
                .map((segment) => segment.consumptionWh)
                .toList(),
            tieBreakKeys: [
              for (var i = 0; i < rawSegments.length; i++)
                i.toString().padLeft(8, '0'),
            ],
          );
    var roomLevelUnallocated = consumptionWh == 0 ? finalCharge : 0;
    final segments = <ElectricitySegmentSnapshot>[];
    for (var index = 0; index < rawSegments.length; index++) {
      segments.add(
        _allocateSegment(
          raw: rawSegments[index],
          chargeCentavos: segmentAmounts[index],
          occupancies: input.occupancies,
          boardersById: boardersById,
        ),
      );
    }

    final aggregates = <String, _ShareAggregate>{};
    var segmentUnallocated = 0;
    var hasEstimated = false;
    for (final segment in segments) {
      segmentUnallocated += segment.unallocatedCentavos;
      hasEstimated =
          hasEstimated ||
          segment.allocationQuality == ElectricityAllocationQuality.estimated;
      for (final share in segment.boarderShares) {
        final aggregate = aggregates.putIfAbsent(
          share.boarderId,
          () => _ShareAggregate(
            boarderId: share.boarderId,
            boarderName: share.boarderName,
          ),
        );
        aggregate.amountCentavos += share.amountCentavos;
        aggregate.occupancyDays += share.occupancyDays;
        aggregate.occupancyIds.addAll(share.occupancyIds);
        aggregate.isEstimated = aggregate.isEstimated || share.isEstimated;
      }
    }
    final boarderShares = aggregates.values.map((aggregate) {
      final ids = aggregate.occupancyIds.toList()..sort();
      return BoarderElectricityShare(
        boarderId: aggregate.boarderId,
        boarderName: aggregate.boarderName,
        occupancyIds: ids,
        occupancyDays: aggregate.occupancyDays,
        amountCentavos: aggregate.amountCentavos,
        isEstimated: aggregate.isEstimated,
      );
    }).toList()..sort((a, b) => a.boarderId.compareTo(b.boarderId));

    final allocated = _sumNonNegative(
      boarderShares.map((item) => item.amountCentavos),
      label: '${room.roomName} allocated electricity charge',
    );
    final unallocated = segmentUnallocated + roomLevelUnallocated;
    if (allocated + unallocated != finalCharge) {
      throw ElectricityValidationException(
        '${room.roomName} electricity shares did not reconcile.',
        code: 'non-reconciling-total',
      );
    }
    return RoomElectricityCharge(
      roomId: room.roomId,
      roomName: room.roomName,
      segments: segments,
      adjustments: adjustments,
      boarderShares: boarderShares,
      consumptionWh: consumptionWh,
      baseChargeCentavos: baseCharge,
      adjustmentCentavos: adjustmentTotal,
      finalChargeCentavos: finalCharge,
      allocatedCentavos: allocated,
      unallocatedCentavos: unallocated,
      hasEstimatedShares: hasEstimated,
    );
  }

  List<_RawSegment> _segmentsForPeriod({
    required Room room,
    required List<ElectricityMeter> meters,
    required List<MeterReading> allReadings,
    required BusinessDate periodStart,
    required BusinessDate periodEnd,
  }) {
    var meterIndex = meters.indexWhere(
      (meter) =>
          !periodStart.isBefore(meter.startedOn) &&
          (meter.endedOn == null || periodStart.isBefore(meter.endedOn!)),
    );
    if (meterIndex < 0) {
      throw ElectricityValidationException(
        '${room.roomName} has no meter covering the billing period start.',
        code: 'missing-boundary-reading',
      );
    }

    final segments = <_RawSegment>[];
    var localStart = periodStart;
    while (true) {
      final meter = meters[meterIndex];
      final endedOn = meter.endedOn;
      final localEnd = endedOn != null && endedOn.isBefore(periodEnd)
          ? endedOn
          : periodEnd;
      final readings =
          allReadings
              .where(
                (reading) =>
                    reading.meterId == meter.meterId &&
                    !reading.readingDate.isBefore(localStart) &&
                    !reading.readingDate.isAfter(localEnd),
              )
              .toList()
            ..sort((a, b) => a.readingDate.compareTo(b.readingDate));
      if (readings.isEmpty ||
          readings.first.readingDate != localStart ||
          readings.last.readingDate != localEnd) {
        throw ElectricityValidationException(
          '${room.roomName} needs readings on $localStart and $localEnd.',
          code: 'missing-boundary-reading',
        );
      }
      for (var index = 1; index < readings.length; index++) {
        final previous = readings[index - 1];
        final current = readings[index];
        segments.add(
          _RawSegment(
            meterId: meter.meterId,
            sequence: meter.sequence,
            previous: previous,
            current: current,
          ),
        );
      }
      if (localEnd == periodEnd) break;
      meterIndex++;
      if (meterIndex >= meters.length ||
          meters[meterIndex].startedOn != localEnd) {
        throw ElectricityValidationException(
          '${room.roomName} has a gap between meter sequences.',
          code: 'noncontiguous-meter-transition',
        );
      }
      localStart = localEnd;
    }
    if (segments.isEmpty) {
      throw ElectricityValidationException(
        '${room.roomName} has no measurable interval in this period.',
        code: 'missing-boundary-reading',
      );
    }
    return segments;
  }

  ElectricitySegmentSnapshot _allocateSegment({
    required _RawSegment raw,
    required int chargeCentavos,
    required List<Occupancy> occupancies,
    required Map<String, Boarder> boardersById,
  }) {
    final weights = <String, _OccupancyWeight>{};
    for (final occupancy in occupancies) {
      if (occupancy.roomId != raw.roomId) continue;
      final overlapStart = occupancy.moveInDate.isAfter(raw.startDate)
          ? occupancy.moveInDate
          : raw.startDate;
      final occupancyEnd = occupancy.moveOutDate;
      final overlapEnd =
          occupancyEnd != null && occupancyEnd.isBefore(raw.endDateExclusive)
          ? occupancyEnd
          : raw.endDateExclusive;
      final days = overlapStart.isBefore(overlapEnd)
          ? overlapStart.daysUntil(overlapEnd)
          : 0;
      if (days == 0) continue;
      final weight = weights.putIfAbsent(
        occupancy.boarderId,
        () => _OccupancyWeight(occupancy.boarderId),
      );
      weight.days += days;
      weight.occupancyIds.add(occupancy.occupancyId);
    }

    if (weights.isEmpty) {
      return ElectricitySegmentSnapshot(
        meterId: raw.meterId,
        sequence: raw.sequence,
        previousReadingId: raw.previous.readingId,
        currentReadingId: raw.current.readingId,
        startDate: raw.startDate,
        endDateExclusive: raw.endDateExclusive,
        previousReadingWh: raw.previous.readingWh,
        currentReadingWh: raw.current.readingWh,
        consumptionWh: raw.consumptionWh,
        chargeCentavos: chargeCentavos,
        boarderShares: const [],
        unallocatedCentavos: chargeCentavos,
        allocationQuality: ElectricityAllocationQuality.unallocated,
      );
    }

    final orderedWeights = weights.values.toList()
      ..sort((a, b) => a.boarderId.compareTo(b.boarderId));
    final amounts = _allocateLargestRemainder(
      total: chargeCentavos,
      weights: orderedWeights.map((item) => item.days).toList(),
      tieBreakKeys: orderedWeights.map((item) => item.boarderId).toList(),
    );
    final segmentDays = raw.startDate.daysUntil(raw.endDateExclusive);
    final exact =
        orderedWeights.length == 1 && orderedWeights.single.days == segmentDays;
    final shares = <BoarderElectricityShare>[];
    for (var index = 0; index < orderedWeights.length; index++) {
      final weight = orderedWeights[index];
      final boarder = boardersById[weight.boarderId]!;
      final occupancyIds = weight.occupancyIds.toList()..sort();
      shares.add(
        BoarderElectricityShare(
          boarderId: boarder.boarderId,
          boarderName: boarder.fullName,
          occupancyIds: occupancyIds,
          occupancyDays: weight.days,
          amountCentavos: amounts[index],
          isEstimated: !exact,
        ),
      );
    }
    return ElectricitySegmentSnapshot(
      meterId: raw.meterId,
      sequence: raw.sequence,
      previousReadingId: raw.previous.readingId,
      currentReadingId: raw.current.readingId,
      startDate: raw.startDate,
      endDateExclusive: raw.endDateExclusive,
      previousReadingWh: raw.previous.readingWh,
      currentReadingWh: raw.current.readingWh,
      consumptionWh: raw.consumptionWh,
      chargeCentavos: chargeCentavos,
      boarderShares: shares,
      unallocatedCentavos: 0,
      allocationQuality: exact
          ? ElectricityAllocationQuality.exact
          : ElectricityAllocationQuality.estimated,
    );
  }

  List<int> _allocateLargestRemainder({
    required int total,
    required List<int> weights,
    required List<String> tieBreakKeys,
  }) {
    if (total < 0 || weights.length != tieBreakKeys.length) {
      throw const ElectricityValidationException(
        'An allocation request is invalid.',
        code: 'invalid-allocation',
      );
    }
    if (weights.any((weight) => weight < 0)) {
      throw const ElectricityValidationException(
        'Allocation weights cannot be negative.',
        code: 'invalid-allocation',
      );
    }
    final totalWeight = weights.fold<BigInt>(
      BigInt.zero,
      (sum, weight) => sum + BigInt.from(weight),
    );
    if (totalWeight == BigInt.zero) {
      if (total == 0) return List<int>.filled(weights.length, 0);
      throw const ElectricityValidationException(
        'A positive charge cannot be allocated with zero total weight.',
        code: 'invalid-allocation',
      );
    }
    final totalBig = BigInt.from(total);
    final amounts = List<int>.filled(weights.length, 0);
    final remainders = <_Remainder>[];
    var floorTotal = 0;
    for (var index = 0; index < weights.length; index++) {
      final numerator = totalBig * BigInt.from(weights[index]);
      final floor = numerator ~/ totalWeight;
      final amount = ElectricityValues.checkedFirestoreInt(
        floor,
        label: 'Allocated electricity share',
      );
      amounts[index] = amount;
      floorTotal += amount;
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
      final byRemainder = b.value.compareTo(a.value);
      return byRemainder != 0
          ? byRemainder
          : a.tieBreakKey.compareTo(b.tieBreakKey);
    });
    final leftover = total - floorTotal;
    if (leftover < 0 || leftover > remainders.length) {
      throw const ElectricityValidationException(
        'Largest-remainder allocation failed to reconcile.',
        code: 'non-reconciling-total',
      );
    }
    for (var index = 0; index < leftover; index++) {
      amounts[remainders[index].index]++;
    }
    return amounts;
  }

  int _sumNonNegative(Iterable<int> values, {required String label}) {
    var sum = BigInt.zero;
    for (final value in values) {
      if (value < 0) {
        throw ElectricityValidationException(
          '$label cannot contain a negative value.',
          code: 'negative-value',
        );
      }
      sum += BigInt.from(value);
    }
    return ElectricityValues.checkedFirestoreInt(sum, label: label);
  }

  int _sumSigned(Iterable<int> values, {required String label}) {
    var sum = BigInt.zero;
    for (final value in values) {
      sum += BigInt.from(value);
    }
    final minimum = -ElectricityValues.maxFirestoreInteger - BigInt.one;
    if (sum < minimum || sum > ElectricityValues.maxFirestoreInteger) {
      throw ElectricityValidationException(
        '$label is outside the supported range.',
        code: 'value-out-of-range',
      );
    }
    return sum.toInt();
  }

  static int _compareRooms(Room a, Room b) {
    final byName = a.roomName.toLowerCase().compareTo(b.roomName.toLowerCase());
    return byName != 0 ? byName : a.roomId.compareTo(b.roomId);
  }
}

class _RawSegment {
  const _RawSegment({
    required this.meterId,
    required this.sequence,
    required this.previous,
    required this.current,
  });

  final String meterId;
  final int sequence;
  final MeterReading previous;
  final MeterReading current;

  String get roomId => previous.roomId;
  BusinessDate get startDate => previous.readingDate;
  BusinessDate get endDateExclusive => current.readingDate;
  int get consumptionWh => current.consumptionWh;
}

class _OccupancyWeight {
  _OccupancyWeight(this.boarderId);

  final String boarderId;
  int days = 0;
  final Set<String> occupancyIds = {};
}

class _ShareAggregate {
  _ShareAggregate({required this.boarderId, required this.boarderName});

  final String boarderId;
  final String boarderName;
  int occupancyDays = 0;
  int amountCentavos = 0;
  bool isEstimated = false;
  final Set<String> occupancyIds = {};
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
