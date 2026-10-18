import 'package:boarding_house_manager/features/electricity/domain/electricity_models.dart';
import 'package:boarding_house_manager/features/property_management/domain/boarder.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/property_management/domain/occupancy.dart';
import 'package:boarding_house_manager/features/property_management/domain/room.dart';
import 'package:boarding_house_manager/features/water/domain/water_calculator.dart';
import 'package:boarding_house_manager/features/water/domain/water_models.dart';
import 'package:boarding_house_manager/features/water/domain/water_values.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boarding_house_manager/features/water/domain/water_selection.dart';

import 'dart:convert';

void main() {
  const calculator = WaterCalculator();

  group('landlady selected normal water', () {
    final rooms = [_room('201', '201'), _room('202', '202')];
    final boarders = [
      _boarder('a', 'Ana'),
      _boarder('b', 'Bea'),
      _boarder('c', 'Carlo'),
    ];
    final occupancies = [
      _occupancy('oa', 'a', '201', _d(2026, 1, 1)),
      _occupancy('ob', 'b', '201', _d(2026, 1, 1)),
      _occupancy('oc', 'c', '202', _d(2026, 1, 1)),
    ];
    List<WaterBoarderDecision> candidates(List<Occupancy> values) =>
        waterCandidates(
          start: _d(2026, 1, 1),
          end: _d(2026, 1, 31),
          rooms: rooms,
          boarders: boarders,
          occupancies: values,
        );
    WaterCalculationResult calculate(
      List<WaterBoarderDecision> decisions, {
      int bill = 9000,
      List<Occupancy>? values,
    }) => calculator.calculate(
      _input(
        bill: bill,
        method: WaterBillingMethod.selectedBoarders,
        rooms: rooms,
        boarders: boarders,
        occupancies: values ?? occupancies,
        decisions: decisions,
      ),
    );

    test(
      'full occupants selected; exclusion redistributes equal shares by room',
      () {
        final decisions = candidates(occupancies);
        expect(
          decisions.every((d) => d.inclusion == WaterInclusion.included),
          isTrue,
        );
        expect(
          calculate(decisions).roomAllocations.map((r) => r.roomChargeCentavos),
          [6000, 3000],
        );
        decisions[2] = decisions[2].decide(inclusion: WaterInclusion.excluded);
        expect(
          () => calculate(decisions),
          _throwsCode('invalid-boarder-selection'),
        );
        decisions[2] = decisions[2].decide(
          exclusionReason: 'Away for statement period',
        );
        final result = calculate(decisions);
        expect(result.includedBoarderCount, 2);
        expect(result.roomAllocations.map((r) => r.roomChargeCentavos), [
          9000,
          0,
        ]);
        expect(
          result.decisions.last.exclusionReason,
          'Away for statement period',
        );
      },
    );

    test('partial arrivals and departures need explicit decisions and pay equal shares', () {
      final values = [
        occupancies[0],
        _occupancy('ob', 'b', '201', _d(2026, 1, 16)),
        _occupancy('oc', 'c', '202', _d(2025, 12, 1), moveOut: _d(2026, 1, 11)),
      ];
      final decisions = candidates(values);
      expect(decisions.map((d) => d.occupiedDays), [30, 15, 10]);
      expect(
        decisions.skip(1).every((d) => d.inclusion == WaterInclusion.pending),
        isTrue,
      );
      expect(
        () => calculate(decisions, values: values),
        _throwsCode('invalid-boarder-selection'),
      );
      final result = calculate(
        decisions
            .map((d) => d.decide(inclusion: WaterInclusion.included))
            .toList(),
        values: values,
      );
      expect(result.boarderShares.map((s) => s.amountCentavos), [
        3000,
        3000,
        3000,
      ]);
    });

    test('transfer counted once, requires explicit room and explanation', () {
      final values = [
        occupancies[1],
        occupancies[2],
        _occupancy('oa', 'a', '201', _d(2026, 1, 1), moveOut: _d(2026, 1, 16)),
        _occupancy('oa2', 'a', '202', _d(2026, 1, 16)),
      ];
      final decisions = candidates(values);
      expect(decisions.length, 3);
      expect(decisions.first.occupiedDays, 30);
      expect(decisions.first.billingRoomId, isNull);
      expect(
        () => calculate(decisions, values: values),
        _throwsCode('invalid-boarder-selection'),
      );
      decisions[0] = decisions[0].decide(
        billingRoomId: '202',
        roomReason: 'Charge destination room by agreement',
      );
      final result = calculate(decisions, values: values);
      expect(result.roomAllocations.map((r) => r.roomChargeCentavos), [
        3000,
        6000,
      ]);
      expect(result.boarderShares.length, 3);
    });

    test('zero included blocks even zero bill; rounding stable under reordered input', () {
      final decisions = candidates(occupancies);
      expect(
        () => calculate(
          decisions
              .map(
                (d) => d.decide(
                  inclusion: WaterInclusion.excluded,
                  exclusionReason: 'Away',
                ),
              )
              .toList(),
          bill: 0,
        ),
        _throwsCode('invalid-boarder-selection'),
      );
      expect(
        calculate(
          decisions.reversed.toList(),
          bill: 100,
        ).boarderShares.map((s) => s.amountCentavos),
        [34, 33, 33],
      );
      expect(
        calculate(
          decisions,
          bill: 1,
        ).boarderShares.map((s) => s.amountCentavos),
        [1, 0, 0],
      );
    });

    test('boundary dates exclude non-overlapping occupants', () {
      final values = [
        occupancies.first,
        _occupancy('ob', 'b', '201', _d(2026, 1, 31)),
        _occupancy('oc', 'c', '202', _d(2025, 12, 1), moveOut: _d(2026, 1, 1)),
      ];
      expect(candidates(values).map((d) => d.boarderId), ['a']);
    });

    test('stale or omitted eligibility rejected; stored decisions immutable and round-trip', () {
      final decisions = candidates(occupancies);
      final result = calculate(decisions);
      expect(
        () => calculate(decisions.take(2).toList()),
        _throwsCode('stale-water-selection'),
      );
      expect(
        () => calculate(
          decisions,
          values: [
            occupancies[0],
            occupancies[1],
            _occupancy('oc', 'c', '202', _d(2026, 1, 16)),
          ],
        ),
        _throwsCode('stale-water-selection'),
      );
      expect(() => result.decisions.clear(), throwsUnsupportedError);
      final saved = jsonDecode(
        jsonEncode(result.decisions.map((d) => d.toMap()).toList()),
      ) as List;
      final restored = saved
          .map(
            (d) => WaterBoarderDecision.fromMap(
              Map<String, dynamic>.from(d as Map),
            ),
          )
          .toList();
      final historical = calculateSelectedWater(
        start: result.startDate,
        end: result.endDateExclusive,
        amount: result.waterBillCentavos,
        decisions: restored,
      );
      expect(historical.roomAllocations.map((r) => r.roomChargeCentavos), [
        6000,
        3000,
      ]);
    });
  });

  group('WaterValues', () {
    test('parses exact centavos without floating point', () {
      expect(WaterValues.parsePesosToCentavos('1,200'), 120000);
      expect(WaterValues.parsePesosToCentavos('1200.5'), 120050);
      expect(WaterValues.parsePesosToCentavos('0.01'), 1);
    });

    test('rejects invalid and out-of-range amounts', () {
      expect(
        () => WaterValues.parsePesosToCentavos('-1'),
        _throwsCode('invalid-water-bill-format'),
      );
      expect(
        () => WaterValues.parsePesosToCentavos('10.001'),
        _throwsCode('invalid-water-bill-format'),
      );
      expect(
        () => WaterValues.parsePesosToCentavos('10000000000000.01'),
        _throwsCode('value-out-of-range'),
      );
    });
  });

  group('normal person-day water billing', () {
    test('allocates PHP 1200 as 800 and 400 for 30 and 15 days', () {
      final room = _room('room-a', 'Room A');
      final boarders = [_boarder('a', 'Boarder A'), _boarder('b', 'Boarder B')];
      final result = calculator.calculate(
        _input(
          bill: 120000,
          rooms: [room],
          boarders: boarders,
          occupancies: [
            _occupancy('oa', 'a', room.roomId, _d(2026, 1, 1)),
            _occupancy('ob', 'b', room.roomId, _d(2026, 1, 16)),
          ],
        ),
      );

      expect(result.totalPersonDays, 45);
      expect(result.boarderShares.map((item) => item.amountCentavos), [
        80000,
        40000,
      ]);
      expect(result.totalAllocatedCentavos, 120000);
      expect(result.totalUnallocatedCentavos, 0);
      expect(result.roomAllocations.single.roomChargeCentavos, 120000);
    });

    test('uses deterministic largest remainder for three equal occupants', () {
      final room = _room('room-a', 'Room A');
      final boarders = [
        _boarder('a', 'A'),
        _boarder('b', 'B'),
        _boarder('c', 'C'),
      ];
      final result = calculator.calculate(
        _input(
          bill: 100,
          rooms: [room],
          boarders: boarders,
          occupancies: [
            for (final boarder in boarders)
              _occupancy(
                'o-${boarder.boarderId}',
                boarder.boarderId,
                room.roomId,
                _d(2026, 1, 1),
              ),
          ],
        ),
      );

      expect(result.boarderShares.map((item) => item.amountCentavos), [
        34,
        33,
        33,
      ]);
      expect(
        result.boarderShares.fold<int>(
          0,
          (sum, item) => sum + item.amountCentavos,
        ),
        100,
      );
    });

    test('counts a same-day transfer once and preserves room splits', () {
      final rooms = [_room('room-a', 'Room A'), _room('room-b', 'Room B')];
      final boarder = _boarder('a', 'Boarder A');
      final result = calculator.calculate(
        _input(
          bill: 3000,
          rooms: rooms,
          boarders: [boarder],
          occupancies: [
            _occupancy(
              'oa',
              'a',
              'room-a',
              _d(2026, 1, 1),
              moveOut: _d(2026, 1, 16),
            ),
            _occupancy('ob', 'a', 'room-b', _d(2026, 1, 16)),
          ],
        ),
      );

      expect(result.totalPersonDays, 30);
      expect(result.boarderShares.single.amountCentavos, 3000);
      expect(result.roomAllocations.map((item) => item.roomChargeCentavos), [
        1500,
        1500,
      ]);
    });

    test('keeps the whole bill unallocated when nobody occupied', () {
      final result = calculator.calculate(
        _input(bill: 50000, rooms: [_room('room-a', 'Room A')]),
      );

      expect(result.totalAllocatedCentavos, 0);
      expect(result.totalUnallocatedCentavos, 50000);
      expect(result.warnings, isNotEmpty);
    });
  });

  group('summer electricity-percentage water billing', () {
    test('allocates PHP 1000 as 750 and 250 using 900 and 300 charges', () {
      final rooms = [_room('room-a', 'Room A'), _room('room-b', 'Room B')];
      final boarders = [_boarder('a', 'Boarder A'), _boarder('b', 'Boarder B')];
      final electricity = _electricityRecord(
        rooms: rooms,
        baseCharges: const [90000, 30000],
        consumptionWh: const [10000, 10000],
      );
      final result = calculator.calculate(
        _input(
          bill: 100000,
          method: WaterBillingMethod.electricityPercentage,
          rooms: rooms,
          boarders: boarders,
          occupancies: [
            _occupancy('oa', 'a', 'room-a', _d(2026, 1, 1)),
            _occupancy('ob', 'b', 'room-b', _d(2026, 1, 1)),
          ],
          electricityRecord: electricity,
        ),
      );

      expect(result.totalElectricityBasis, 120000);
      expect(result.roomAllocations.map((item) => item.roomChargeCentavos), [
        75000,
        25000,
      ]);
      expect(result.boarderShares.map((item) => item.amountCentavos), [
        75000,
        25000,
      ]);
      expect(
        result.totalAllocatedCentavos + result.totalUnallocatedCentavos,
        100000,
      );
    });

    test('can use consumption instead of electricity charges', () {
      final rooms = [_room('room-a', 'Room A'), _room('room-b', 'Room B')];
      final boarders = [_boarder('a', 'A'), _boarder('b', 'B')];
      final result = calculator.calculate(
        _input(
          bill: 10000,
          method: WaterBillingMethod.electricityPercentage,
          basis: SummerElectricityBasis.roomConsumption,
          rooms: rooms,
          boarders: boarders,
          occupancies: [
            _occupancy('oa', 'a', 'room-a', _d(2026, 1, 1)),
            _occupancy('ob', 'b', 'room-b', _d(2026, 1, 1)),
          ],
          electricityRecord: _electricityRecord(
            rooms: rooms,
            baseCharges: const [50000, 50000],
            consumptionWh: const [3000, 1000],
          ),
        ),
      );

      expect(result.roomAllocations.map((item) => item.roomChargeCentavos), [
        7500,
        2500,
      ]);
      expect(result.totalElectricityBasis, 4000);
    });

    test('splits a room share by occupancy days', () {
      final room = _room('room-a', 'Room A');
      final boarders = [_boarder('a', 'A'), _boarder('b', 'B')];
      final result = calculator.calculate(
        _input(
          bill: 90000,
          method: WaterBillingMethod.electricityPercentage,
          rooms: [room],
          boarders: boarders,
          occupancies: [
            _occupancy('oa', 'a', room.roomId, _d(2026, 1, 1)),
            _occupancy('ob', 'b', room.roomId, _d(2026, 1, 16)),
          ],
          electricityRecord: _electricityRecord(
            rooms: [room],
            baseCharges: const [10000],
            consumptionWh: const [1000],
          ),
        ),
      );

      expect(result.boarderShares.map((item) => item.amountCentavos), [
        60000,
        30000,
      ]);
    });

    test('keeps an empty room share explicitly unallocated', () {
      final rooms = [_room('room-a', 'Room A'), _room('room-b', 'Room B')];
      final boarder = _boarder('a', 'A');
      final result = calculator.calculate(
        _input(
          bill: 10000,
          method: WaterBillingMethod.electricityPercentage,
          rooms: rooms,
          boarders: [boarder],
          occupancies: [_occupancy('oa', 'a', 'room-a', _d(2026, 1, 1))],
          electricityRecord: _electricityRecord(
            rooms: rooms,
            baseCharges: const [5000, 5000],
            consumptionWh: const [500, 500],
          ),
        ),
      );

      expect(result.totalAllocatedCentavos, 5000);
      expect(result.totalUnallocatedCentavos, 5000);
      expect(result.warnings.single, contains('Room B'));
    });

    test('rejects zero, missing, or mismatched electricity basis', () {
      final room = _room('room-a', 'Room A');
      expect(
        () => calculator.calculate(
          _input(
            method: WaterBillingMethod.electricityPercentage,
            rooms: [room],
          ),
        ),
        _throwsCode('missing-electricity-record'),
      );
      expect(
        () => calculator.calculate(
          _input(
            method: WaterBillingMethod.electricityPercentage,
            rooms: [room],
            electricityRecord: _electricityRecord(
              rooms: [room],
              baseCharges: const [0],
              consumptionWh: const [0],
            ),
          ),
        ),
        _throwsCode('no-electricity-basis'),
      );
      expect(
        () => calculator.calculate(
          _input(
            method: WaterBillingMethod.electricityPercentage,
            rooms: [room],
            electricityRecord: _electricityRecord(
              rooms: [room],
              baseCharges: const [100],
              consumptionWh: const [100],
              end: _d(2026, 2, 1),
            ),
          ),
        ),
        _throwsCode('missing-electricity-record'),
      );
    });
  });

  group('room-day water billing', () {
    test('counts an occupied room once even with multiple boarders', () {
      final roomA = _room('room-a', 'Room A');
      final roomB = _room('room-b', 'Room B');
      final boarders = [
        _boarder('a', 'A'),
        _boarder('b', 'B'),
        _boarder('c', 'C'),
      ];
      final result = calculator.calculate(
        _input(
          bill: 9000,
          method: WaterBillingMethod.roomDays,
          rooms: [roomA, roomB],
          boarders: boarders,
          occupancies: [
            _occupancy('oa', 'a', roomA.roomId, _d(2026, 1, 1)),
            _occupancy('ob', 'b', roomA.roomId, _d(2026, 1, 1)),
            _occupancy('oc', 'c', roomB.roomId, _d(2026, 1, 16)),
          ],
        ),
      );

      expect(result.totalPersonDays, 45);
      expect(result.boarderShares, isEmpty);
      expect(result.roomAllocations.map((item) => item.roomChargeCentavos), [
        6000,
        3000,
      ]);
      expect(result.totalAllocatedCentavos, 9000);
    });

    test('leaves the bill unallocated when every room is vacant', () {
      final result = calculator.calculate(
        _input(
          method: WaterBillingMethod.roomDays,
          rooms: [_room('room-a', 'Room A')],
        ),
      );

      expect(result.totalPersonDays, 0);
      expect(result.totalAllocatedCentavos, 0);
      expect(result.totalUnallocatedCentavos, 10000);
    });
  });

  test(
    'default settings recommend electricity percentage in summer months',
    () {
      final settings = WaterSettings.defaults();
      expect(
        settings.methodFor(_d(2026, 4, 1)),
        WaterBillingMethod.electricityPercentage,
      );
      expect(
        settings.methodFor(_d(2026, 6, 1)),
        WaterBillingMethod.selectedBoarders,
      );
    },
  );
}

Matcher _throwsCode(String code) => throwsA(
  isA<WaterValidationException>().having((error) => error.code, 'code', code),
);

BusinessDate _d(int year, int month, int day) => BusinessDate(year, month, day);

Room _room(String id, String name) => Room(
  roomId: id,
  roomName: name,
  description: '',
  status: RoomStatus.active,
  defaultMonthlyRentCentavos: null,
  activeOccupancyCount: 0,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Boarder _boarder(String id, String name) => Boarder(
  boarderId: id,
  fullName: name,
  contact: null,
  notes: null,
  status: BoarderStatus.active,
  currentOccupancyId: null,
  currentRoomId: null,
  currentMoveInDate: null,
  lastMoveOutDate: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Occupancy _occupancy(
  String id,
  String boarderId,
  String roomId,
  BusinessDate moveIn, {
  BusinessDate? moveOut,
}) => Occupancy(
  occupancyId: id,
  boarderId: boarderId,
  roomId: roomId,
  moveInDate: moveIn,
  moveOutDate: moveOut,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

WaterCalculationInput _input({
  int bill = 10000,
  WaterBillingMethod method = WaterBillingMethod.personDays,
  SummerElectricityBasis basis = SummerElectricityBasis.roomElectricityCharge,
  List<Room> rooms = const [],
  List<Boarder> boarders = const [],
  List<Occupancy> occupancies = const [],
  ElectricityBillingRecord? electricityRecord,
  List<WaterBoarderDecision> decisions = const [],
}) => WaterCalculationInput(
  startDate: _d(2026, 1, 1),
  endDateExclusive: _d(2026, 1, 31),
  waterBillCentavos: bill,
  method: method,
  summerBasis: basis,
  rooms: rooms,
  boarders: boarders,
  occupancies: occupancies,
  electricityRecord: electricityRecord,
  decisions: decisions,
);

ElectricityBillingRecord _electricityRecord({
  required List<Room> rooms,
  required List<int> baseCharges,
  required List<int> consumptionWh,
  BusinessDate? end,
}) {
  final charges = <RoomElectricityCharge>[];
  for (var index = 0; index < rooms.length; index++) {
    charges.add(
      RoomElectricityCharge(
        roomId: rooms[index].roomId,
        roomName: rooms[index].roomName,
        segments: const [],
        adjustments: const [],
        boarderShares: const [],
        consumptionWh: consumptionWh[index],
        baseChargeCentavos: baseCharges[index],
        adjustmentCentavos: 0,
        finalChargeCentavos: baseCharges[index],
        allocatedCentavos: baseCharges[index],
        unallocatedCentavos: 0,
        hasEstimatedShares: false,
      ),
    );
  }
  return ElectricityBillingRecord(
    billingRecordId: 'electricity-jan',
    startDate: _d(2026, 1, 1),
    endDateExclusive: end ?? _d(2026, 1, 31),
    rateMicropesosPerKwh: 10000000,
    roomCharges: charges,
    totalConsumptionWh: consumptionWh.fold(0, (sum, item) => sum + item),
    totalBaseChargeCentavos: baseCharges.fold(0, (sum, item) => sum + item),
    totalAdjustmentsCentavos: 0,
    totalChargeCentavos: baseCharges.fold(0, (sum, item) => sum + item),
    totalAllocatedCentavos: baseCharges.fold(0, (sum, item) => sum + item),
    totalUnallocatedCentavos: 0,
    warnings: const [],
    recordedAt: DateTime.utc(2026, 2, 1),
  );
}
