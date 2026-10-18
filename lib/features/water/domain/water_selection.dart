import '../../property_management/domain/boarder.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/domain/occupancy.dart';
import '../../property_management/domain/room.dart';
import 'water_values.dart';
import 'water_models.dart';

enum WaterInclusion { pending, included, excluded }

/// Immutable evidence, independent of subsequent room/occupancy edits.
class WaterOccupancySnapshot {
  const WaterOccupancySnapshot({
    required this.occupancyId,
    required this.roomId,
    required this.roomName,
    required this.moveIn,
    required this.moveOut,
    required this.overlapStart,
    required this.overlapEnd,
  });
  final String occupancyId, roomId, roomName;
  final BusinessDate moveIn, overlapStart, overlapEnd;
  final BusinessDate? moveOut;
  int get days => overlapStart.daysUntil(overlapEnd);
  Map<String, dynamic> toMap() => {
    'occupancyId': occupancyId,
    'roomId': roomId,
    'roomName': roomName,
    'moveIn': '$moveIn',
    'moveOut': moveOut?.toString(),
    'overlapStart': '$overlapStart',
    'overlapEnd': '$overlapEnd',
  };
  factory WaterOccupancySnapshot.fromMap(Map<String, dynamic> data) =>
      WaterOccupancySnapshot(
        occupancyId: data['occupancyId'] as String,
        roomId: data['roomId'] as String,
        roomName: data['roomName'] as String,
        moveIn: BusinessDate.parse(data['moveIn'] as String),
        moveOut: data['moveOut'] == null
            ? null
            : BusinessDate.parse(data['moveOut'] as String),
        overlapStart: BusinessDate.parse(data['overlapStart'] as String),
        overlapEnd: BusinessDate.parse(data['overlapEnd'] as String),
      );
}

class WaterBoarderDecision {
  WaterBoarderDecision({
    required this.boarderId,
    required this.boarderName,
    required this.fullPeriod,
    required List<WaterOccupancySnapshot> occupancies,
    required this.inclusion,
    this.exclusionReason = '',
    this.billingRoomId,
    this.roomReason = '',
  }) : occupancies = List.unmodifiable(occupancies);
  final String boarderId, boarderName;
  final bool fullPeriod;
  final List<WaterOccupancySnapshot> occupancies;
  final WaterInclusion inclusion;
  final String exclusionReason, roomReason;
  final String? billingRoomId;
  int get occupiedDays => occupancies.fold(0, (sum, item) => sum + item.days);
  Set<String> get roomIds => occupancies.map((item) => item.roomId).toSet();
  bool get transferred => roomIds.length > 1;
  WaterBoarderDecision decide({
    WaterInclusion? inclusion,
    String? exclusionReason,
    String? billingRoomId,
    String? roomReason,
  }) => WaterBoarderDecision(
    boarderId: boarderId,
    boarderName: boarderName,
    fullPeriod: fullPeriod,
    occupancies: occupancies,
    inclusion: inclusion ?? this.inclusion,
    exclusionReason: exclusionReason ?? this.exclusionReason,
    billingRoomId: billingRoomId ?? this.billingRoomId,
    roomReason: roomReason ?? this.roomReason,
  );
  Map<String, dynamic> toMap() => {
    'boarderId': boarderId,
    'boarderName': boarderName,
    'fullPeriod': fullPeriod,
    'occupancies': occupancies.map((item) => item.toMap()).toList(),
    'inclusion': inclusion.name,
    'exclusionReason': exclusionReason,
    'billingRoomId': billingRoomId,
    'roomReason': roomReason,
  };
  factory WaterBoarderDecision.fromMap(Map<String, dynamic> data) =>
      WaterBoarderDecision(
        boarderId: data['boarderId'] as String,
        boarderName: data['boarderName'] as String,
        fullPeriod: data['fullPeriod'] as bool,
        occupancies: (data['occupancies'] as List)
            .map(
              (item) => WaterOccupancySnapshot.fromMap(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
        inclusion: WaterInclusion.values.byName(data['inclusion'] as String),
        exclusionReason: data['exclusionReason'] as String,
        billingRoomId: data['billingRoomId'] as String?,
        roomReason: data['roomReason'] as String,
      );
}

/// Statement dates, never receipt dates, determine eligibility. Days are evidence only.
List<WaterBoarderDecision> waterCandidates({
  required BusinessDate start,
  required BusinessDate end,
  required List<Room> rooms,
  required List<Boarder> boarders,
  required List<Occupancy> occupancies,
}) {
  if (!start.isBefore(end)) return [];
  final byRoom = {for (final room in rooms) room.roomId: room};
  final byBoarder = {
    for (final boarder in boarders) boarder.boarderId: boarder,
  };
  final grouped = <String, List<WaterOccupancySnapshot>>{};
  for (final item in occupancies) {
    final from = item.moveInDate.isAfter(start) ? item.moveInDate : start;
    final to = item.moveOutDate != null && item.moveOutDate!.isBefore(end)
        ? item.moveOutDate!
        : end;
    if (!from.isBefore(to)) continue;
    if (!byRoom.containsKey(item.roomId) ||
        !byBoarder.containsKey(item.boarderId)) {
      throw const WaterValidationException(
        'Occupancy references an unavailable room or boarder.',
        code: 'missing-occupancy-reference',
      );
    }
    grouped
        .putIfAbsent(item.boarderId, () => [])
        .add(
          WaterOccupancySnapshot(
            occupancyId: item.occupancyId,
            roomId: item.roomId,
            roomName: byRoom[item.roomId]!.roomName,
            moveIn: item.moveInDate,
            moveOut: item.moveOutDate,
            overlapStart: from,
            overlapEnd: to,
          ),
        );
  }
  final result = <WaterBoarderDecision>[];
  for (final entry in grouped.entries) {
    final intervals = entry.value
      ..sort((a, b) => a.overlapStart.compareTo(b.overlapStart));
    for (var i = 1; i < intervals.length; i++) {
      if (intervals[i].overlapStart.isBefore(intervals[i - 1].overlapEnd)) {
        throw const WaterValidationException(
          'A boarder has overlapping occupancies.',
          code: 'overlapping-occupancy',
        );
      }
    }
    final full =
        intervals.fold<int>(0, (sum, item) => sum + item.days) ==
        start.daysUntil(end);
    final roomIds = intervals.map((item) => item.roomId).toSet();
    result.add(
      WaterBoarderDecision(
        boarderId: entry.key,
        boarderName: byBoarder[entry.key]!.fullName,
        fullPeriod: full,
        occupancies: intervals,
        inclusion: full ? WaterInclusion.included : WaterInclusion.pending,
        billingRoomId: roomIds.length == 1 ? roomIds.single : null,
      ),
    );
  }
  return result..sort((a, b) => a.boarderId.compareTo(b.boarderId));
}

WaterCalculationResult calculateSelectedWater({
  required BusinessDate start,
  required BusinessDate end,
  required int amount,
  required List<WaterBoarderDecision> decisions,
}) {
  void invalid(String message) => throw WaterValidationException(
    message,
    code: 'invalid-boarder-selection',
  );
  if (!start.isBefore(end) ||
      amount < 0 ||
      amount > WaterValues.maximumBillCentavos) {
    invalid('Enter valid statement dates and water amount.');
  }
  final ids = <String>{};
  final occupancyIds = <String>{};
  for (final d in decisions) {
    if (!ids.add(d.boarderId) || d.occupancies.isEmpty) {
      invalid('Each eligible boarder must appear exactly once.');
    }
    final intervals = [...d.occupancies]
      ..sort((a, b) => a.overlapStart.compareTo(b.overlapStart));
    BusinessDate? previousEnd;
    for (final o in intervals) {
      final from = o.moveIn.isAfter(start) ? o.moveIn : start;
      final to = o.moveOut != null && o.moveOut!.isBefore(end)
          ? o.moveOut!
          : end;
      if (!occupancyIds.add(o.occupancyId) ||
          !from.isBefore(to) ||
          o.overlapStart != from ||
          o.overlapEnd != to ||
          (previousEnd != null && from.isBefore(previousEnd))) {
        invalid('Occupancy evidence is invalid or overlaps.');
      }
      previousEnd = to;
    }
    if (d.fullPeriod != (d.occupiedDays == start.daysUntil(end))) {
      invalid('Coverage classification is inconsistent.');
    }
    if (d.inclusion == WaterInclusion.pending) {
      invalid('Review every partial-period boarder before continuing.');
    }
    if (d.inclusion == WaterInclusion.excluded &&
        (d.exclusionReason.trim().length < 3 ||
            d.exclusionReason.length > 500)) {
      invalid(
        'Enter an exclusion reason (3–500 characters) for ${d.boarderName}.',
      );
    }
    if (d.inclusion == WaterInclusion.included &&
        (!d.roomIds.contains(d.billingRoomId) ||
            (d.transferred &&
                (d.roomReason.trim().length < 3 ||
                    d.roomReason.length > 500)))) {
      invalid(
        'Choose a billing room and explain the transfer decision for ${d.boarderName}.',
      );
    }
  }
  final included =
      decisions.where((d) => d.inclusion == WaterInclusion.included).toList()
        ..sort((a, b) => a.boarderId.compareTo(b.boarderId));
  if (included.isEmpty) {
    invalid(
      'Include at least one boarder. No allocation is possible with zero included boarders.',
    );
  }
  final shares = <BoarderWaterShare>[];
  final rooms = <String, List<RoomBoarderWaterShare>>{};
  final names = <String, String>{};
  // Include zero-charge rooms in the preview and snapshot too.
  for (final d in decisions) {
    for (final o in d.occupancies) {
      rooms.putIfAbsent(o.roomId, () => []);
      names[o.roomId] = o.roomName;
    }
  }
  for (var i = 0; i < included.length; i++) {
    final d = included[i];
    final cents =
        amount ~/ included.length + (i < amount % included.length ? 1 : 0);
    final occupancyIds = d.occupancies.map((o) => o.occupancyId).toList();
    shares.add(
      BoarderWaterShare(
        boarderId: d.boarderId,
        boarderName: d.boarderName,
        occupancyIds: occupancyIds,
        roomIds: [d.billingRoomId!],
        occupancyDays: d.occupiedDays,
        amountCentavos: cents,
      ),
    );
    rooms[d.billingRoomId]!.add(
      RoomBoarderWaterShare(
        boarderId: d.boarderId,
        boarderName: d.boarderName,
        occupancyIds: occupancyIds,
        occupancyDays: d.occupiedDays,
        amountCentavos: cents,
      ),
    );
  }
  final roomIds = rooms.keys.toList()..sort();
  return WaterCalculationResult(
    startDate: start,
    endDateExclusive: end,
    waterBillCentavos: amount,
    method: WaterBillingMethod.selectedBoarders,
    summerBasis: SummerElectricityBasis.roomElectricityCharge,
    electricityRecordId: null,
    totalPersonDays: decisions.fold(0, (sum, d) => sum + d.occupiedDays),
    totalElectricityBasis: 0,
    totalAllocatedCentavos: amount,
    totalUnallocatedCentavos: 0,
    roomAllocations: roomIds.map((id) {
      final total = rooms[id]!.fold<int>(0, (sum, s) => sum + s.amountCentavos);
      return WaterRoomAllocation(
        roomId: id,
        roomName: names[id]!,
        electricityBasisValue: 0,
        occupancyDays: decisions.fold<int>(
          0,
          (sum, d) =>
              sum +
              d.occupancies
                  .where((o) => o.roomId == id)
                  .fold<int>(0, (n, o) => n + o.days),
        ),
        roomChargeCentavos: total,
        allocatedCentavos: total,
        unallocatedCentavos: 0,
        boarderShares: rooms[id]!,
      );
    }).toList(),
    boarderShares: shares,
    warnings: const [],
    decisions: decisions,
  );
}
