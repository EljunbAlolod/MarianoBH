import 'package:boarding_house_manager/features/electricity/domain/electricity_calculator.dart';
import 'package:boarding_house_manager/features/electricity/domain/electricity_models.dart';
import 'package:boarding_house_manager/features/electricity/domain/electricity_values.dart';
import 'package:boarding_house_manager/features/property_management/domain/boarder.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/property_management/domain/occupancy.dart';
import 'package:boarding_house_manager/features/property_management/domain/room.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calculator = ElectricityCalculator();

  group('ElectricityValues', () {
    test('parses and formats readings and rates without floating point', () {
      expect(
        ElectricityValues.parseKilowattHoursToWattHours('1,250.375'),
        1250375,
      );
      expect(
        ElectricityValues.parsePesosPerKwhToMicropesos('12.345678'),
        12345678,
      );
      expect(
        ElectricityValues.formatWattHoursAsKilowattHours(1250375),
        '1250.375',
      );
      expect(ElectricityValues.formatMicropesosAsPesosPerKwh(12000000), '12');
    });

    test('rejects negative, excessive-scale, and overflowing values', () {
      expect(
        () => ElectricityValues.parseKilowattHoursToWattHours('-1'),
        _throwsCode('invalid-reading-format'),
      );
      expect(
        () => ElectricityValues.parseKilowattHoursToWattHours('1.0001'),
        _throwsCode('invalid-reading-format'),
      );
      expect(
        () => ElectricityValues.parsePesosPerKwhToMicropesos('12.1234567'),
        _throwsCode('invalid-rate-format'),
      );
      expect(
        () => ElectricityValues.parseKilowattHoursToWattHours(
          '9223372036854775808',
        ),
        _throwsCode('value-out-of-range'),
      );
      expect(
        () => ElectricityValues.parseKilowattHoursToWattHours('1000000000.001'),
        _throwsCode('value-out-of-range'),
      );
      expect(
        () => ElectricityValues.parsePesosPerKwhToMicropesos('1000.000001'),
        _throwsCode('value-out-of-range'),
      );
    });

    test('calculates the specification example and rounds half up', () {
      expect(
        ElectricityValues.chargeCentavos(
          consumptionWh: 90000,
          rateMicropesosPerKwh: 12000000,
        ),
        108000,
      );
      expect(
        ElectricityValues.chargeCentavos(
          consumptionWh: 1,
          rateMicropesosPerKwh: 5000000,
        ),
        1,
      );
      expect(
        ElectricityValues.chargeCentavos(
          consumptionWh: 1,
          rateMicropesosPerKwh: 4999999,
        ),
        0,
      );
    });
  });

  group('ElectricityCalculator', () {
    test('calculates 1250 to 1340 kWh at PHP 12 exactly', () {
      final room = _room('room-101', 'Room 101');
      final boarder = _boarder('juan', 'Juan');
      final meter = _meterFixture(
        meterId: 'meter-101',
        roomId: room.roomId,
        points: [
          (_d(2026, 10, 1), 1250000, MeterReadingKind.opening),
          (_d(2026, 11, 1), 1340000, MeterReadingKind.regular),
        ],
      );

      final result = calculator.calculate(
        _input(
          start: _d(2026, 10, 1),
          end: _d(2026, 11, 1),
          rate: 12000000,
          rooms: [room],
          boarders: [boarder],
          occupancies: [
            _occupancy(
              'occ-juan',
              boarder.boarderId,
              room.roomId,
              _d(2026, 10, 1),
            ),
          ],
          fixtures: [meter],
        ),
      );

      expect(result.totalConsumptionWh, 90000);
      expect(result.totalChargeCentavos, 108000);
      expect(result.totalAllocatedCentavos, 108000);
      expect(result.totalUnallocatedCentavos, 0);
      expect(
        result.roomCharges.single.boarderShares.single.amountCentavos,
        108000,
      );
      expect(result.roomCharges.single.hasEstimatedShares, isFalse);
    });

    test('splits equally when two boarders occupy the whole interval', () {
      final room = _room('room-101', 'Room 101');
      final first = _boarder('a', 'Ana');
      final second = _boarder('b', 'Ben');
      final fixture = _simpleFixture(room.roomId, consumptionWh: 90000);

      final result = calculator.calculate(
        _input(
          rooms: [room],
          boarders: [first, second],
          occupancies: [
            _occupancy('occ-a', 'a', room.roomId, _d(2026, 10, 1)),
            _occupancy('occ-b', 'b', room.roomId, _d(2026, 10, 1)),
          ],
          fixtures: [fixture],
        ),
      );

      expect(
        result.roomCharges.single.boarderShares.map(
          (share) => share.amountCentavos,
        ),
        [54000, 54000],
      );
      expect(result.roomCharges.single.hasEstimatedShares, isTrue);
      expect(result.warnings, isNotEmpty);
    });

    test('uses occupancy days for a partial-period boarder', () {
      final room = _room('room-101', 'Room 101');
      final first = _boarder('a', 'A');
      final second = _boarder('b', 'B');
      final fixture = _meterFixture(
        meterId: 'meter-room-101',
        roomId: room.roomId,
        points: [
          (_d(2026, 4, 1), 0, MeterReadingKind.opening),
          (_d(2026, 5, 1), 100000, MeterReadingKind.regular),
        ],
      );

      final result = calculator.calculate(
        _input(
          start: _d(2026, 4, 1),
          end: _d(2026, 5, 1),
          rooms: [room],
          boarders: [first, second],
          occupancies: [
            _occupancy('occ-a', 'a', room.roomId, _d(2026, 4, 1)),
            _occupancy('occ-b', 'b', room.roomId, _d(2026, 4, 16)),
          ],
          fixtures: [fixture],
        ),
      );

      final shares = result.roomCharges.single.boarderShares;
      expect(shares[0].occupancyDays, 30);
      expect(shares[0].amountCentavos, 80000);
      expect(shares[1].occupancyDays, 15);
      expect(shares[1].amountCentavos, 40000);
      expect(
        shares.fold<int>(0, (sum, item) => sum + item.amountCentavos),
        120000,
      );
    });

    test('uses deterministic largest remainder for three-way rounding', () {
      final room = _room('room-1', 'Room 1');
      final boarders = [
        _boarder('a', 'A'),
        _boarder('b', 'B'),
        _boarder('c', 'C'),
      ];

      final result = calculator.calculate(
        _input(
          rate: 1000000,
          rooms: [room],
          boarders: boarders,
          occupancies: [
            for (final boarder in boarders)
              _occupancy(
                'occ-${boarder.boarderId}',
                boarder.boarderId,
                room.roomId,
                _d(2026, 10, 1),
              ),
          ],
          fixtures: [_simpleFixture(room.roomId, consumptionWh: 1000)],
        ),
      );

      expect(
        result.roomCharges.single.boarderShares.map(
          (share) => share.amountCentavos,
        ),
        [34, 33, 33],
      );
      expect(result.totalChargeCentavos, 100);
    });

    test('same-date transfer is counted once across two rooms', () {
      final firstRoom = _room('room-a', 'Room A');
      final secondRoom = _room('room-b', 'Room B');
      final boarder = _boarder('boarder', 'Boarder');

      final result = calculator.calculate(
        _input(
          rooms: [firstRoom, secondRoom],
          boarders: [boarder],
          occupancies: [
            _occupancy(
              'occ-a',
              boarder.boarderId,
              firstRoom.roomId,
              _d(2026, 10, 1),
              moveOut: _d(2026, 10, 16),
            ),
            _occupancy(
              'occ-b',
              boarder.boarderId,
              secondRoom.roomId,
              _d(2026, 10, 16),
            ),
          ],
          fixtures: [
            _simpleFixture(firstRoom.roomId, consumptionWh: 10000),
            _simpleFixture(secondRoom.roomId, consumptionWh: 20000),
          ],
        ),
      );

      final days = result.roomCharges
          .expand((room) => room.boarderShares)
          .fold<int>(0, (sum, share) => sum + share.occupancyDays);
      expect(days, 31);
      expect(result.totalChargeCentavos, 36000);
      expect(result.totalAllocatedCentavos, result.totalChargeCentavos);
    });

    test('intermediate readings split usage at an occupancy boundary', () {
      final room = _room('room-1', 'Room 1');
      final first = _boarder('a', 'A');
      final second = _boarder('b', 'B');
      final withIntermediate = _meterFixture(
        meterId: 'meter-room-1',
        roomId: room.roomId,
        points: [
          (_d(2026, 1, 1), 0, MeterReadingKind.opening),
          (_d(2026, 1, 6), 10000, MeterReadingKind.intermediate),
          (_d(2026, 1, 11), 30000, MeterReadingKind.regular),
        ],
      );
      final occupancies = [
        _occupancy(
          'occ-a',
          'a',
          room.roomId,
          _d(2026, 1, 1),
          moveOut: _d(2026, 1, 6),
        ),
        _occupancy('occ-b', 'b', room.roomId, _d(2026, 1, 6)),
      ];

      final result = calculator.calculate(
        _input(
          start: _d(2026, 1, 1),
          end: _d(2026, 1, 11),
          rate: 1000000,
          rooms: [room],
          boarders: [first, second],
          occupancies: occupancies,
          fixtures: [withIntermediate],
        ),
      );

      expect(result.roomCharges.single.segments, hasLength(2));
      expect(
        result.roomCharges.single.boarderShares.map(
          (share) => share.amountCentavos,
        ),
        [1000, 2000],
      );
      expect(result.roomCharges.single.hasEstimatedShares, isFalse);

      final withoutIntermediate = _meterFixture(
        meterId: 'meter-room-1',
        roomId: room.roomId,
        points: [
          (_d(2026, 1, 1), 0, MeterReadingKind.opening),
          (_d(2026, 1, 11), 30000, MeterReadingKind.regular),
        ],
      );
      final estimated = calculator.calculate(
        _input(
          start: _d(2026, 1, 1),
          end: _d(2026, 1, 11),
          rate: 1000000,
          rooms: [room],
          boarders: [first, second],
          occupancies: occupancies,
          fixtures: [withoutIntermediate],
        ),
      );
      expect(
        estimated.roomCharges.single.boarderShares.map(
          (share) => share.amountCentavos,
        ),
        [1500, 1500],
      );
      expect(estimated.roomCharges.single.hasEstimatedShares, isTrue);
    });

    test('requires readings on both billing boundaries', () {
      final room = _room('room-1', 'Room 1');
      final fixture = _meterFixture(
        meterId: 'meter-room-1',
        roomId: room.roomId,
        points: [
          (_d(2026, 9, 30), 0, MeterReadingKind.opening),
          (_d(2026, 11, 1), 30000, MeterReadingKind.regular),
        ],
      );

      expect(
        () => calculator.calculate(_input(rooms: [room], fixtures: [fixture])),
        _throwsCode('missing-boundary-reading'),
      );
    });

    test('keeps charges explicitly unallocated when no one occupied', () {
      final room = _room('room-1', 'Room 1');
      final result = calculator.calculate(
        _input(
          rate: 1000000,
          rooms: [room],
          fixtures: [_simpleFixture(room.roomId, consumptionWh: 1000)],
        ),
      );

      expect(result.totalChargeCentavos, 100);
      expect(result.totalAllocatedCentavos, 0);
      expect(result.totalUnallocatedCentavos, 100);
      expect(result.roomCharges.single.boarderShares, isEmpty);
      expect(result.warnings.single, contains('unallocated'));
    });

    test('applies documented surcharges and discounts and reconciles', () {
      final room = _room('room-1', 'Room 1');
      final boarder = _boarder('a', 'A');
      final result = calculator.calculate(
        _input(
          rate: 1000000,
          rooms: [room],
          boarders: [boarder],
          occupancies: [_occupancy('occ-a', 'a', room.roomId, _d(2026, 10, 1))],
          fixtures: [_simpleFixture(room.roomId, consumptionWh: 1000)],
          adjustments: [
            ElectricityAdjustment(
              adjustmentId: 'surcharge',
              roomId: room.roomId,
              type: ElectricityAdjustmentType.surcharge,
              magnitudeCentavos: 25,
              reason: 'Documented transformer loss',
              adjustmentDate: _d(2026, 10, 20),
            ),
            ElectricityAdjustment(
              adjustmentId: 'discount',
              roomId: room.roomId,
              type: ElectricityAdjustmentType.discount,
              magnitudeCentavos: 10,
              reason: 'Approved correction',
              adjustmentDate: _d(2026, 10, 21),
            ),
          ],
        ),
      );

      final charge = result.roomCharges.single;
      expect(charge.baseChargeCentavos, 100);
      expect(charge.adjustmentCentavos, 15);
      expect(charge.finalChargeCentavos, 115);
      expect(charge.allocatedCentavos + charge.unallocatedCentavos, 115);
      expect(
        result.totalBaseChargeCentavos + result.totalAdjustmentsCentavos,
        115,
      );
    });

    test('rejects a discount that would create a negative room charge', () {
      final room = _room('room-1', 'Room 1');
      expect(
        () => calculator.calculate(
          _input(
            rate: 1000000,
            rooms: [room],
            fixtures: [_simpleFixture(room.roomId, consumptionWh: 1000)],
            adjustments: [
              ElectricityAdjustment(
                adjustmentId: 'too-large',
                roomId: room.roomId,
                type: ElectricityAdjustmentType.discount,
                magnitudeCentavos: 101,
                reason: 'Invalid excessive discount',
                adjustmentDate: _d(2026, 10, 20),
              ),
            ],
          ),
        ),
        _throwsCode('negative-room-charge'),
      );
    });

    test('preserves reset sequences and never subtracts across meters', () {
      final room = _room('room-1', 'Room 1');
      final boarder = _boarder('a', 'A');
      final first = _meterFixture(
        meterId: 'meter-old',
        roomId: room.roomId,
        status: ElectricityMeterStatus.retired,
        replacementMeterId: 'meter-new',
        points: [
          (_d(2026, 1, 1), 100000, MeterReadingKind.opening),
          (_d(2026, 1, 6), 110000, MeterReadingKind.closing),
        ],
      );
      final second = _meterFixture(
        meterId: 'meter-new',
        roomId: room.roomId,
        sequence: 2,
        startKind: ElectricityMeterStartKind.reset,
        transitionReason: 'Meter reset by utility technician',
        previousMeterId: 'meter-old',
        points: [
          (_d(2026, 1, 6), 5000, MeterReadingKind.opening),
          (_d(2026, 1, 11), 25000, MeterReadingKind.regular),
        ],
      );

      final result = calculator.calculate(
        _input(
          start: _d(2026, 1, 1),
          end: _d(2026, 1, 11),
          rate: 1000000,
          rooms: [room],
          boarders: [boarder],
          occupancies: [_occupancy('occ-a', 'a', room.roomId, _d(2026, 1, 1))],
          fixtures: [first, second],
        ),
      );

      expect(result.totalConsumptionWh, 30000);
      expect(result.totalChargeCentavos, 3000);
      expect(result.roomCharges.single.segments, hasLength(2));
      expect(result.roomCharges.single.segments.map((item) => item.meterId), [
        'meter-old',
        'meter-new',
      ]);
    });

    test('supports an explicit correction meter transition', () {
      final room = _room('room-1', 'Room 1');
      final old = _meterFixture(
        meterId: 'bad-sequence',
        roomId: room.roomId,
        status: ElectricityMeterStatus.retired,
        replacementMeterId: 'corrected-sequence',
        points: [
          (_d(2026, 10, 1), 1000, MeterReadingKind.opening),
          (_d(2026, 10, 15), 2000, MeterReadingKind.closing),
        ],
      );
      final corrected = _meterFixture(
        meterId: 'corrected-sequence',
        roomId: room.roomId,
        sequence: 2,
        startKind: ElectricityMeterStartKind.correction,
        transitionReason: 'Corrected a mistyped historical reading',
        previousMeterId: 'bad-sequence',
        points: [
          (_d(2026, 10, 15), 1500, MeterReadingKind.opening),
          (_d(2026, 11, 1), 2500, MeterReadingKind.regular),
        ],
      );

      final result = calculator.calculate(
        _input(rooms: [room], fixtures: [old, corrected]),
      );
      expect(result.totalConsumptionWh, 2000);
    });

    test('rejects negative consumption and duplicate reading dates', () {
      final room = _room('room-1', 'Room 1');
      final decreasing = _meterFixture(
        meterId: 'meter-room-1',
        roomId: room.roomId,
        points: [
          (_d(2026, 10, 1), 2000, MeterReadingKind.opening),
          (_d(2026, 11, 1), 1000, MeterReadingKind.regular),
        ],
      );
      expect(
        () =>
            calculator.calculate(_input(rooms: [room], fixtures: [decreasing])),
        _throwsCode('negative-consumption'),
      );

      final duplicateDate = _meterFixture(
        meterId: 'meter-room-1',
        roomId: room.roomId,
        points: [
          (_d(2026, 10, 1), 0, MeterReadingKind.opening),
          (_d(2026, 10, 1), 1000, MeterReadingKind.intermediate),
          (_d(2026, 11, 1), 2000, MeterReadingKind.regular),
        ],
      );
      expect(
        () => calculator.calculate(
          _input(rooms: [room], fixtures: [duplicateDate]),
        ),
        _throwsCode('duplicate-reading-date'),
      );
    });

    test('reconciles multiple rooms and produces immutable snapshots', () {
      final roomA = _room('a', 'A');
      final roomB = _room('b', 'B');
      final result = calculator.calculate(
        _input(
          rate: 1000000,
          rooms: [roomB, roomA],
          fixtures: [
            _simpleFixture(roomA.roomId, consumptionWh: 1000),
            _simpleFixture(roomB.roomId, consumptionWh: 2000),
          ],
        ),
      );

      expect(result.roomCharges.map((item) => item.roomId), ['a', 'b']);
      expect(result.totalChargeCentavos, 300);
      expect(
        result.totalAllocatedCentavos + result.totalUnallocatedCentavos,
        result.totalChargeCentavos,
      );

      final record = ElectricityBillingRecord.fromResult(
        billingRecordId: '2026-10-01__2026-11-01',
        result: result,
        recordedAt: DateTime.utc(2026, 11, 1),
      );
      expect(
        () => record.roomCharges.add(result.roomCharges.first),
        throwsUnsupportedError,
      );
      expect(record.totalChargeCentavos, result.totalChargeCentavos);
    });
  });

  group('meter reading correction eligibility', () {
    test('allows only the active unbilled head reading', () {
      final fixture = _meterFixture(
        meterId: 'meter-room-1',
        roomId: 'room-1',
        points: [
          (_d(2026, 10, 1), 100000, MeterReadingKind.opening),
          (_d(2026, 10, 14), 125000, MeterReadingKind.regular),
        ],
      );

      expect(
        meterReadingCorrectionEligibility(
          reading: fixture.readings.last,
          activeMeter: fixture.meter,
        ),
        MeterReadingCorrectionEligibility.eligible,
      );
      expect(
        meterReadingCorrectionEligibility(
          reading: fixture.readings.first,
          activeMeter: fixture.meter,
        ),
        MeterReadingCorrectionEligibility.newerReadingExists,
      );
    });

    test('locks billed and unmigrated readings conservatively', () {
      final fixture = _meterFixture(
        meterId: 'meter-room-1',
        roomId: 'room-1',
        points: [(_d(2026, 10, 1), 100000, MeterReadingKind.opening)],
      );
      final source = fixture.readings.single;
      final billed = MeterReading(
        readingId: source.readingId,
        meterId: source.meterId,
        roomId: source.roomId,
        sequence: source.sequence,
        readingDate: source.readingDate,
        readingWh: source.readingWh,
        kind: source.kind,
        previousReadingId: source.previousReadingId,
        previousReadingDate: source.previousReadingDate,
        previousReadingWh: source.previousReadingWh,
        consumptionWh: source.consumptionWh,
        note: source.note,
        createdAt: source.createdAt,
        billingRecordIds: const ['bill-1'],
      );
      final legacy = MeterReading(
        readingId: source.readingId,
        meterId: source.meterId,
        roomId: source.roomId,
        sequence: source.sequence,
        readingDate: source.readingDate,
        readingWh: source.readingWh,
        kind: source.kind,
        previousReadingId: source.previousReadingId,
        previousReadingDate: source.previousReadingDate,
        previousReadingWh: source.previousReadingWh,
        consumptionWh: source.consumptionWh,
        note: source.note,
        createdAt: source.createdAt,
        lockTrackingComplete: false,
      );

      expect(
        meterReadingCorrectionEligibility(
          reading: billed,
          activeMeter: fixture.meter,
        ),
        MeterReadingCorrectionEligibility.billed,
      );
      expect(
        meterReadingCorrectionEligibility(
          reading: legacy,
          activeMeter: fixture.meter,
        ),
        MeterReadingCorrectionEligibility.migrationRequired,
      );
    });
  });
}

Matcher _throwsCode(String code) {
  return throwsA(
    isA<ElectricityValidationException>().having(
      (error) => error.code,
      'code',
      code,
    ),
  );
}

BusinessDate _d(int year, int month, int day) => BusinessDate(year, month, day);

Room _room(String id, String name) {
  return Room(
    roomId: id,
    roomName: name,
    description: '',
    status: RoomStatus.active,
    defaultMonthlyRentCentavos: null,
    activeOccupancyCount: 0,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

Boarder _boarder(String id, String name) {
  return Boarder(
    boarderId: id,
    fullName: name,
    contact: null,
    notes: null,
    status: BoarderStatus.inactive,
    currentOccupancyId: null,
    currentRoomId: null,
    currentMoveInDate: null,
    lastMoveOutDate: null,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

Occupancy _occupancy(
  String id,
  String boarderId,
  String roomId,
  BusinessDate moveIn, {
  BusinessDate? moveOut,
}) {
  return Occupancy(
    occupancyId: id,
    boarderId: boarderId,
    roomId: roomId,
    moveInDate: moveIn,
    moveOutDate: moveOut,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

_MeterFixture _simpleFixture(String roomId, {required int consumptionWh}) {
  return _meterFixture(
    meterId: 'meter-$roomId',
    roomId: roomId,
    points: [
      (_d(2026, 10, 1), 0, MeterReadingKind.opening),
      (_d(2026, 11, 1), consumptionWh, MeterReadingKind.regular),
    ],
  );
}

_MeterFixture _meterFixture({
  required String meterId,
  required String roomId,
  required List<(BusinessDate, int, MeterReadingKind)> points,
  int sequence = 1,
  ElectricityMeterStatus status = ElectricityMeterStatus.active,
  ElectricityMeterStartKind startKind = ElectricityMeterStartKind.initial,
  String? transitionReason,
  String? previousMeterId,
  String? replacementMeterId,
}) {
  final readings = <MeterReading>[];
  for (var index = 0; index < points.length; index++) {
    final point = points[index];
    final previous = index == 0 ? null : readings[index - 1];
    readings.add(
      MeterReading(
        readingId: '$meterId-r$index',
        meterId: meterId,
        roomId: roomId,
        sequence: sequence,
        readingDate: point.$1,
        readingWh: point.$2,
        kind: point.$3,
        previousReadingId: previous?.readingId,
        previousReadingDate: previous?.readingDate,
        previousReadingWh: previous?.readingWh,
        consumptionWh: previous == null ? 0 : point.$2 - previous.readingWh,
        note: null,
        createdAt: DateTime.utc(2026),
      ),
    );
  }
  final last = readings.last;
  return _MeterFixture(
    meter: ElectricityMeter(
      meterId: meterId,
      roomId: roomId,
      sequence: sequence,
      status: status,
      startedOn: points.first.$1,
      endedOn: status == ElectricityMeterStatus.retired ? points.last.$1 : null,
      startKind: startKind,
      transitionReason: transitionReason,
      previousMeterId: previousMeterId,
      replacementMeterId: replacementMeterId,
      lastReadingId: last.readingId,
      lastReadingDate: last.readingDate,
      lastReadingWh: last.readingWh,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
    readings: readings,
  );
}

ElectricityCalculationInput _input({
  BusinessDate? start,
  BusinessDate? end,
  int rate = 12000000,
  List<Room> rooms = const [],
  List<Boarder> boarders = const [],
  List<Occupancy> occupancies = const [],
  List<_MeterFixture> fixtures = const [],
  List<ElectricityAdjustment> adjustments = const [],
}) {
  return ElectricityCalculationInput(
    startDate: start ?? _d(2026, 10, 1),
    endDateExclusive: end ?? _d(2026, 11, 1),
    rateMicropesosPerKwh: rate,
    rooms: rooms,
    meters: fixtures.map((fixture) => fixture.meter).toList(),
    readings: fixtures.expand((fixture) => fixture.readings).toList(),
    occupancies: occupancies,
    boarders: boarders,
    adjustments: adjustments,
  );
}

class _MeterFixture {
  const _MeterFixture({required this.meter, required this.readings});

  final ElectricityMeter meter;
  final List<MeterReading> readings;
}
