import 'package:boarding_house_manager/features/property_management/domain/boarder.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/property_management/domain/occupancy.dart';
import 'package:boarding_house_manager/features/property_management/domain/room.dart';
import 'package:boarding_house_manager/features/property_management/presentation/widgets/property_formatters.dart';
import 'package:boarding_house_manager/features/water/domain/water_calculator.dart';
import 'package:boarding_house_manager/features/water/domain/water_models.dart';
import 'package:boarding_house_manager/features/water/domain/water_selection.dart';
import 'package:boarding_house_manager/features/water/domain/water_batch_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes.dart';
import '../../../helpers/pump_app.dart';

void main() {
  for (final status in [
    WaterBillingBatchStatus.draft,
    WaterBillingBatchStatus.finalized,
  ]) {
    testWidgets(
      'saved normal $status restores decisions without changing shares',
      (tester) async {
        final fixture = _WaterFixture.create();
        final end = BusinessDate.todayInManila();
        final occupancy = fixture.properties.occupancies.values
            .expand((v) => v)
            .toList();
        final start = occupancy.first.moveInDate;
        final candidates = waterCandidates(
          start: start,
          end: end,
          rooms: fixture.properties.rooms,
          boarders: fixture.properties.boarders,
          occupancies: occupancy,
        );
        final decisions = [
          candidates.first,
          candidates.last.decide(
            inclusion: WaterInclusion.excluded,
            exclusionReason: 'Away for this bill',
          ),
        ];
        final result = calculateSelectedWater(
          start: start,
          end: end,
          amount: 9000,
          decisions: decisions,
        );
        final now = DateTime.now();
        fixture.water.batches = [
          WaterBillingBatch(
            batchId: 'saved-normal',
            batchReference: 'WB-SAVED',
            status: status,
            startDate: start,
            endDateExclusive: end,
            receiptDate: end,
            waterBillCentavos: 9000,
            method: result.method,
            summerBasis: result.summerBasis,
            electricityBatchId: null,
            electricityBatchReference: null,
            electricityMeasurementStart: null,
            electricityMeasurementEnd: null,
            referencePeriodMismatchConfirmed: false,
            referenceExplanation: null,
            notes: null,
            totalPersonDays: result.totalPersonDays,
            totalElectricityBasis: 0,
            totalAllocatedCentavos: 9000,
            totalUnallocatedCentavos: 0,
            roomAllocations: result.roomAllocations,
            boarderShares: result.boarderShares,
            decisions: decisions,
            warnings: const [],
            version: 1,
            createdAt: now,
            updatedAt: now,
            finalizedAt: status == WaterBillingBatchStatus.finalized
                ? now
                : null,
            usedAt: null,
            voidReason: null,
            voidedAt: null,
          ),
        ];
        if (status == WaterBillingBatchStatus.finalized) {
          // Historical display must depend on the snapshot, not live occupancy.
          fixture.properties.occupancies.clear();
        }
        final auth = FakeAuthRepository(initialUser: verifiedUser);
        final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
        addTearDown(auth.dispose);
        await pumpTestApp(
          tester,
          authRepository: auth,
          ownerRepository: owners,
          propertyRepository: fixture.properties,
          waterRepository: fixture.water,
        );
        GoRouter.of(tester.element(find.byType(NavigationBar))).go(
          '/billing/water/batches/saved-normal${status == WaterBillingBatchStatus.draft ? "/edit" : ""}',
        );
        await tester.pumpAndSettle();
        expect(find.text('Share: ₱90.00'), findsOneWidget);
        expect(find.text('Share: ₱0.00'), findsOneWidget);
        if (status == WaterBillingBatchStatus.draft) {
          expect(
            tester
                .widget<ChoiceChip>(find.byKey(const Key('exclude-boarder-b')))
                .selected,
            isTrue,
          );
          expect(find.text('Away for this bill'), findsOneWidget);
        } else {
          expect(find.text('Reason: Away for this bill'), findsOneWidget);
          expect(find.byKey(const Key('include-boarder-a')), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'normal selection redistributes live, requires exclusion reason, and preserves review decisions',
    (tester) async {
      final fixture = _WaterFixture.create();
      final auth = FakeAuthRepository(initialUser: verifiedUser);
      final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
      addTearDown(auth.dispose);
      await pumpTestApp(
        tester,
        authRepository: auth,
        ownerRepository: owners,
        propertyRepository: fixture.properties,
        waterRepository: fixture.water,
      );
      GoRouter.of(tester.element(find.byType(NavigationBar)))
          .go('/billing/water/batches/new');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('water-batch-amount')), '90');
      await tester.pumpAndSettle();
      expect(find.text('Share: ₱45.00'), findsNWidgets(2));
      tester
          .widget<ChoiceChip>(find.byKey(const Key('exclude-boarder-b')))
          .onSelected!(true);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('review-water-batch')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const Key('exclude-reason-boarder-b')),
        'Away during the statement period',
      );
      await tester.pumpAndSettle();
      expect(find.text('Share: ₱90.00'), findsOneWidget);
      expect(find.text('Share: ₱0.00'), findsOneWidget);
      tester
          .widget<FilledButton>(find.byKey(const Key('review-water-batch')))
          .onPressed!();
      await tester.pumpAndSettle();
      expect(
        find.text('Reason: Away during the statement period'),
        findsOneWidget,
      );
      tester
          .widget<FilledButton>(find.byKey(const Key('finalize-water-batch')))
          .onPressed!();
      await tester.pumpAndSettle();
      final result = fixture.water.lastResult!;
      expect(result.method, WaterBillingMethod.selectedBoarders);
      expect(result.includedBoarderCount, 1);
      expect(result.decisions.last.inclusion, WaterInclusion.excluded);
      expect(
        result.decisions.last.exclusionReason,
        'Away during the statement period',
      );
      expect(result.boarderShares.single.amountCentavos, 9000);
    },
  );

  testWidgets('billing hub and water overview reflow on a narrow phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    });
    final fixture = _WaterFixture.create(includeRecord: true);
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);

    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      propertyRepository: fixture.properties,
      waterRepository: fixture.water,
    );
    await _openWater(tester);

    expect(find.text('Water allocation'), findsOneWidget);
    expect(find.text('Allocation settings'), findsOneWidget);
    expect(find.text('Water batches'), findsOneWidget);
    expect(find.text('Historical water records'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('person-day calculation previews exact boarder shares', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final fixture = _WaterFixture.create();
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);
    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      propertyRepository: fixture.properties,
      waterRepository: fixture.water,
    );

    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go('/billing/water/new');
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'The narrow large-text form should not overflow.',
    );
    await tester.enterText(find.byKey(const Key('water-bill-field')), '1200');
    final review = find.byKey(const Key('review-water-button'));
    tester.widget<FilledButton>(review).onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('Allocation preview'), findsOneWidget);
    expect(find.text('Ana Cruz'), findsOneWidget);
    expect(find.text('Ben Lim'), findsOneWidget);
    expect(find.text(formatPeso(60000)), findsNWidgets(2));
    expect(find.byKey(const Key('save-water-record-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'independent water batch reviews and finalizes on a narrow phone',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 812);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final fixture = _WaterFixture.create();
      final auth = FakeAuthRepository(initialUser: verifiedUser);
      final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
      addTearDown(auth.dispose);
      await pumpTestApp(
        tester,
        authRepository: auth,
        ownerRepository: owners,
        propertyRepository: fixture.properties,
        waterRepository: fixture.water,
      );

      GoRouter.of(tester.element(find.byType(NavigationBar)))
          .go('/billing/water/batches/new');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const Key('water-batch-amount')),
        '1200',
      );
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(find.byKey(const Key('review-water-batch')))
          .onPressed!();
      await tester.pumpAndSettle();

      expect(find.text('Review water allocation'), findsOneWidget);
      tester
          .widget<FilledButton>(find.byKey(const Key('finalize-water-batch')))
          .onPressed!();
      await tester.pumpAndSettle();

      expect(fixture.water.createWaterBatchCalls, 1);
      expect(fixture.water.finalizeWaterBatchCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('electricity percentage explains a missing exact-date source', (
    tester,
  ) async {
    final fixture = _WaterFixture.create();
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);
    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      propertyRepository: fixture.properties,
      waterRepository: fixture.water,
    );
    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go('/billing/water/new');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Electricity %'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No electricity record has these exact dates'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('review-water-button')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('saved water history opens as a read-only snapshot', (
    tester,
  ) async {
    final fixture = _WaterFixture.create(includeRecord: true);
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);
    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      propertyRepository: fixture.properties,
      waterRepository: fixture.water,
    );
    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go('/billing/water/water-period-1');
    await tester.pumpAndSettle();

    expect(find.text('Read-only historical record'), findsOneWidget);
    expect(find.text('Boarder shares'), findsOneWidget);
    expect(find.text('Room breakdown'), findsOneWidget);
    expect(find.text('Ana Cruz'), findsWidgets);
    expect(find.text('Ben Lim'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openWater(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Billing'),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('water-billing-card')), findsOneWidget);
  GoRouter.of(tester.element(find.byType(NavigationBar))).go('/billing/water');
  await tester.pumpAndSettle();
}

class _WaterFixture {
  const _WaterFixture({required this.properties, required this.water});

  factory _WaterFixture.create({bool includeRecord = false}) {
    final now = DateTime.utc(2026, 10, 14);
    final end = BusinessDate.todayInManila();
    var start = BusinessDate(end.year, end.month, 1);
    if (!start.isBefore(end)) start = end.addDays(-1);
    final room = Room(
      roomId: 'room-a',
      roomName: 'Room A',
      description: '',
      status: RoomStatus.active,
      defaultMonthlyRentCentavos: 350000,
      activeOccupancyCount: 2,
      createdAt: now,
      updatedAt: now,
    );
    Boarder boarder(String id, String name, String occupancyId) => Boarder(
      boarderId: id,
      fullName: name,
      contact: null,
      notes: null,
      status: BoarderStatus.active,
      currentOccupancyId: occupancyId,
      currentRoomId: room.roomId,
      currentMoveInDate: start,
      lastMoveOutDate: null,
      createdAt: now,
      updatedAt: now,
    );
    final boarders = [
      boarder('boarder-a', 'Ana Cruz', 'occupancy-a'),
      boarder('boarder-b', 'Ben Lim', 'occupancy-b'),
    ];
    Occupancy occupancy(String id, String boarderId) => Occupancy(
      occupancyId: id,
      boarderId: boarderId,
      roomId: room.roomId,
      moveInDate: start,
      moveOutDate: null,
      createdAt: now,
      updatedAt: now,
    );
    final occupancies = [
      occupancy('occupancy-a', 'boarder-a'),
      occupancy('occupancy-b', 'boarder-b'),
    ];
    final properties = FakePropertyRepository()
      ..rooms = [room]
      ..boarders = boarders;
    properties.occupancies['boarder-a'] = [occupancies[0]];
    properties.occupancies['boarder-b'] = [occupancies[1]];
    final water = FakeWaterRepository();
    if (includeRecord) {
      final result = const WaterCalculator().calculate(
        WaterCalculationInput(
          startDate: start,
          endDateExclusive: end,
          waterBillCentavos: 120000,
          method: WaterBillingMethod.personDays,
          summerBasis: SummerElectricityBasis.roomElectricityCharge,
          rooms: [room],
          boarders: boarders,
          occupancies: occupancies,
        ),
      );
      water.records = [
        WaterBillingRecord.fromResult(
          waterRecordId: 'water-period-1',
          result: result,
          recordedAt: now,
        ),
      ];
    }
    return _WaterFixture(properties: properties, water: water);
  }

  final FakePropertyRepository properties;
  final FakeWaterRepository water;
}
