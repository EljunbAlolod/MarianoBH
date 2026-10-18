import 'package:boarding_house_manager/features/property_management/domain/boarder.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/property_management/domain/occupancy.dart';
import 'package:boarding_house_manager/features/property_management/domain/room.dart';
import 'package:boarding_house_manager/features/rent/domain/rent_calculator.dart';
import 'package:boarding_house_manager/features/rent/domain/rent_models.dart';
import 'package:boarding_house_manager/features/rent/domain/rent_values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calculator = RentCalculator();

  test('prorates PHP 3100 to PHP 1600 for 16 of 31 days', () {
    final room = _room('a', 'Room A', 310000);
    final boarder = _boarder('a', 'Ana');
    final result = calculator.calculate(
      _input(
        mode: RentBillingMode.perBoarder,
        rooms: [room],
        boarders: [boarder],
        occupancies: [
          _occupancy('oa', boarder.boarderId, room.roomId, _d(2026, 10, 16)),
        ],
      ),
    );

    expect(result.periodDays, 31);
    expect(result.boarderCharges.single.occupancyDays, 16);
    expect(result.totalRentCentavos, 160000);
    expect(result.grandTotalCentavos, 160000);
  });

  test('per-boarder mode charges each occupant using the room rate', () {
    final room = _room('a', 'Room A', 310000);
    final boarders = [_boarder('a', 'Ana'), _boarder('b', 'Ben')];
    final result = calculator.calculate(
      _input(
        mode: RentBillingMode.perBoarder,
        rooms: [room],
        boarders: boarders,
        occupancies: [
          _occupancy('oa', 'a', 'a', _d(2026, 10, 1)),
          _occupancy('ob', 'b', 'a', _d(2026, 10, 16)),
        ],
      ),
    );

    expect(result.totalRentCentavos, 470000);
    expect(result.boarderCharges.map((item) => item.rentCentavos), [
      310000,
      160000,
    ]);
  });

  test('per-room mode charges the room once and splits by person-days', () {
    final room = _room('a', 'Room A', 310000);
    final boarders = [_boarder('a', 'Ana'), _boarder('b', 'Ben')];
    final result = calculator.calculate(
      _input(
        mode: RentBillingMode.perRoom,
        rooms: [room],
        boarders: boarders,
        occupancies: [
          _occupancy('oa', 'a', 'a', _d(2026, 10, 1)),
          _occupancy('ob', 'b', 'a', _d(2026, 10, 16)),
        ],
      ),
    );

    expect(result.totalRentCentavos, 310000);
    expect(result.roomAllocations.single.occupiedDays, 31);
    expect(result.roomAllocations.single.personDays, 47);
    expect(
      result.boarderCharges.fold(0, (sum, item) => sum + item.rentCentavos),
      310000,
    );
  });

  test('per-room mode prorates a room occupied only for the last 16 days', () {
    final room = _room('a', 'Room A', 310000);
    final boarder = _boarder('a', 'Ana');
    final result = calculator.calculate(
      _input(
        mode: RentBillingMode.perRoom,
        rooms: [room],
        boarders: [boarder],
        occupancies: [_occupancy('oa', 'a', 'a', _d(2026, 10, 16))],
      ),
    );

    expect(result.roomAllocations.single.occupiedDays, 16);
    expect(result.totalRentCentavos, 160000);
  });

  test(
    'same-day transfer counts every date once at the applicable room rate',
    () {
      final rooms = [
        _room('a', 'Room A', 310000),
        _room('b', 'Room B', 620000),
      ];
      final boarder = _boarder('a', 'Ana');
      final result = calculator.calculate(
        _input(
          mode: RentBillingMode.perBoarder,
          rooms: rooms,
          boarders: [boarder],
          occupancies: [
            _occupancy(
              'oa',
              'a',
              'a',
              _d(2026, 10, 1),
              moveOut: _d(2026, 10, 16),
            ),
            _occupancy('ob', 'a', 'b', _d(2026, 10, 16)),
          ],
        ),
      );

      expect(result.boarderCharges.single.occupancyDays, 31);
      expect(result.boarderCharges.single.roomIds, ['a', 'b']);
      expect(result.totalRentCentavos, 470000);
    },
  );

  test('documented charges and credits preserve the underlying rent', () {
    final room = _room('a', 'Room A', 310000);
    final boarder = _boarder('a', 'Ana');
    final result = calculator.calculate(
      _input(
        mode: RentBillingMode.perBoarder,
        rooms: [room],
        boarders: [boarder],
        occupancies: [_occupancy('oa', 'a', 'a', _d(2026, 10, 1))],
        adjustments: [
          _adjustment('fee', 'a', BillingAdjustmentType.charge, 2500),
          _adjustment('credit', 'a', BillingAdjustmentType.credit, 1000),
        ],
      ),
    );

    expect(result.totalRentCentavos, 310000);
    expect(result.totalAdjustmentCentavos, 1500);
    expect(result.grandTotalCentavos, 311500);
    expect(result.boarderCharges.single.totalCentavos, 311500);
  });

  test('rent-disabled mode keeps only documented adjustments', () {
    final room = _room('a', 'Room A', null);
    final boarder = _boarder('a', 'Ana');
    final result = calculator.calculate(
      _input(
        mode: RentBillingMode.disabled,
        rooms: [room],
        boarders: [boarder],
        occupancies: [_occupancy('oa', 'a', 'a', _d(2026, 10, 1))],
        adjustments: [
          _adjustment('fee', 'a', BillingAdjustmentType.charge, 2500),
        ],
      ),
    );

    expect(result.roomAllocations, isEmpty);
    expect(result.totalRentCentavos, 0);
    expect(result.grandTotalCentavos, 2500);
  });

  test('largest remainder preserves a one-cent shared room rent', () {
    final room = _room('a', 'Room A', 1);
    final boarders = [
      _boarder('a', 'Ana'),
      _boarder('b', 'Ben'),
      _boarder('c', 'Cara'),
    ];
    final result = calculator.calculate(
      _input(
        mode: RentBillingMode.perRoom,
        rooms: [room],
        boarders: boarders,
        occupancies: [
          for (final boarder in boarders)
            _occupancy(
              'o${boarder.boarderId}',
              boarder.boarderId,
              'a',
              _d(2026, 10, 1),
            ),
        ],
      ),
    );

    expect(result.totalRentCentavos, 1);
    expect(result.boarderCharges.map((item) => item.rentCentavos), [1, 0, 0]);
  });

  test('rejects missing occupied-room rent and overlapping occupancy', () {
    final room = _room('a', 'Room A', null);
    final boarder = _boarder('a', 'Ana');
    expect(
      () => calculator.calculate(
        _input(
          mode: RentBillingMode.perBoarder,
          rooms: [room],
          boarders: [boarder],
          occupancies: [_occupancy('oa', 'a', 'a', _d(2026, 10, 1))],
        ),
      ),
      _throwsCode('missing-room-rent'),
    );
    expect(
      () => calculator.calculate(
        _input(
          mode: RentBillingMode.disabled,
          rooms: [room],
          boarders: [boarder],
          occupancies: [
            _occupancy(
              'oa',
              'a',
              'a',
              _d(2026, 10, 1),
              moveOut: _d(2026, 10, 20),
            ),
            _occupancy('ob', 'a', 'a', _d(2026, 10, 19)),
          ],
        ),
      ),
      _throwsCode('overlapping-occupancy'),
    );
  });

  test('rejects a credit that makes a boarder total negative', () {
    final room = _room('a', 'Room A', null);
    final boarder = _boarder('a', 'Ana');
    expect(
      () => calculator.calculate(
        _input(
          mode: RentBillingMode.disabled,
          rooms: [room],
          boarders: [boarder],
          occupancies: [_occupancy('oa', 'a', 'a', _d(2026, 10, 1))],
          adjustments: [
            _adjustment('credit', 'a', BillingAdjustmentType.credit, 100),
          ],
        ),
      ),
      _throwsCode('negative-boarder-total'),
    );
  });

  test('no occupancy produces a reconciled zero record', () {
    final result = calculator.calculate(_input(mode: RentBillingMode.perRoom));
    expect(result.totalRentCentavos, 0);
    expect(result.grandTotalCentavos, 0);
    expect(result.boarderCharges, isEmpty);
    expect(result.warnings, isNotEmpty);
  });
}

Matcher _throwsCode(String code) => throwsA(
  isA<RentValidationException>().having((error) => error.code, 'code', code),
);

BusinessDate _d(int year, int month, int day) => BusinessDate(year, month, day);

Room _room(String id, String name, int? rent) => Room(
  roomId: id,
  roomName: name,
  description: '',
  status: RoomStatus.active,
  defaultMonthlyRentCentavos: rent,
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

BillingAdjustment _adjustment(
  String id,
  String boarderId,
  BillingAdjustmentType type,
  int amount,
) => BillingAdjustment(
  adjustmentId: id,
  boarderId: boarderId,
  type: type,
  amountCentavos: amount,
  reason: 'Documented correction',
  adjustmentDate: _d(2026, 10, 20),
);

RentCalculationInput _input({
  required RentBillingMode mode,
  List<Room> rooms = const [],
  List<Boarder> boarders = const [],
  List<Occupancy> occupancies = const [],
  List<BillingAdjustment> adjustments = const [],
}) => RentCalculationInput(
  startDate: _d(2026, 10, 1),
  endDateExclusive: _d(2026, 11, 1),
  mode: mode,
  rooms: rooms,
  boarders: boarders,
  occupancies: occupancies,
  adjustments: adjustments,
);
