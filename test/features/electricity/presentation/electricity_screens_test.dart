import 'package:boarding_house_manager/features/electricity/domain/electricity_calculator.dart';
import 'package:boarding_house_manager/features/electricity/domain/electricity_models.dart';
import 'package:boarding_house_manager/features/electricity/presentation/electricity_formatters.dart';
import 'package:boarding_house_manager/features/property_management/domain/boarder.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/property_management/domain/occupancy.dart';
import 'package:boarding_house_manager/features/property_management/domain/room.dart';
import 'package:boarding_house_manager/features/property_management/presentation/widgets/property_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes.dart';
import '../../../helpers/pump_app.dart';

void main() {
  testWidgets('billing reflows on a narrow phone with 2x system text', (
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

    final fixture = _ElectricityFixture.create(includeRecord: true);
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);

    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      propertyRepository: fixture.properties,
      electricityRepository: fixture.electricity,
    );
    await _openBilling(tester);

    expect(find.text('Electricity meters'), findsOneWidget);
    expect(find.text('Room A'), findsOneWidget);
    expect(
      find.textContaining(formatElectricityReading(113000), findRichText: true),
      findsOneWidget,
    );
    expect(find.text('1'), findsWidgets);
    expect(
      find.byKey(const Key('correct-latest-reading-room-a')),
      findsOneWidget,
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'Billing cards and five-item navigation should not overflow.',
    );
  });

  testWidgets('calculation remains usable in dark landscape and reconciles', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(812, 375);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    });

    final fixture = _ElectricityFixture.create();
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);

    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      propertyRepository: fixture.properties,
      electricityRepository: fixture.electricity,
    );
    await _openBilling(tester);

    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go('/billing/electricity/new');
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('electricity-rate-field')),
      '12',
    );
    final review = find.byKey(const Key('review-electricity-button'));
    tester.widget<FilledButton>(review).onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('Calculation review'), findsOneWidget);
    expect(find.text('13 kWh'), findsWidgets);
    expect(find.text(formatPeso(15600)), findsWidgets);
    expect(find.text('Estimated shares'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(NavigationBar))).brightness,
      Brightness.dark,
    );
    expect(
      tester.takeException(),
      isNull,
      reason:
          'The form and calculation preview should scroll without overflow.',
    );
  });

  testWidgets('saved electricity history opens as a read-only snapshot', (
    tester,
  ) async {
    final fixture = _ElectricityFixture.create(includeRecord: true);
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);

    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      propertyRepository: fixture.properties,
      electricityRepository: fixture.electricity,
    );
    await _openBilling(tester);

    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go('/billing/electricity/electricity-period-1');
    await tester.pumpAndSettle();

    expect(find.text('Read-only historical record'), findsOneWidget);
    expect(find.text('Room breakdown'), findsOneWidget);
    expect(find.text('Room A'), findsOneWidget);
    expect(find.textContaining('Ana Cruz'), findsWidgets);
    expect(find.textContaining('Ben Lim'), findsWidgets);
    expect(find.text(formatPeso(15600)), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reading history and warning correction work on a narrow phone', (
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

    final fixture = _ElectricityFixture.create();
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);

    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      propertyRepository: fixture.properties,
      electricityRepository: fixture.electricity,
    );
    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go('/billing/electricity/rooms/room-a/readings');
    await tester.pumpAndSettle();

    expect(find.text('Reading history'), findsOneWidget);
    expect(find.text('Eligible'), findsOneWidget);
    expect(find.text('Read-only'), findsWidgets);
    expect(
      find.byKey(const Key('add-missing-historical-reading')),
      findsOneWidget,
    );
    final correctButton = find.byKey(const Key('correct-reading-reading-end'));
    await tester.scrollUntilVisible(
      correctButton,
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(correctButton);
    await tester.pumpAndSettle();

    expect(find.text('Correct reading'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('corrected-reading-value')),
      '114',
    );
    await tester.enterText(
      find.byKey(const Key('correction-reason')),
      'Corrected a transposed meter entry',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final reviewButton = find.byKey(const Key('review-reading-correction'));
    await tester.scrollUntilVisible(
      reviewButton,
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(reviewButton);
    await tester.pumpAndSettle();

    expect(find.text('Correct this meter reading?'), findsOneWidget);
    expect(
      find.textContaining('Existing billing records will not change'),
      findsOneWidget,
    );
    expect(find.textContaining('Consumption difference'), findsOneWidget);
    final confirmButton = find.byKey(const Key('confirm-reading-correction'));
    await tester.ensureVisible(confirmButton);
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(fixture.electricity.correctReadingCalls, 1);
    expect(fixture.electricity.lastReadingWh, 114000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reading batch reviews and finalizes every active room', (
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

    final fixture = _ElectricityFixture.create();
    final current = fixture.electricity.meters.single;
    fixture.electricity.meters = [
      ElectricityMeter(
        meterId: current.meterId,
        roomId: current.roomId,
        sequence: current.sequence,
        status: current.status,
        startedOn: current.startedOn,
        endedOn: current.endedOn,
        startKind: current.startKind,
        transitionReason: current.transitionReason,
        previousMeterId: current.previousMeterId,
        replacementMeterId: current.replacementMeterId,
        lastReadingId: current.lastReadingId,
        lastReadingDate: BusinessDate.todayInManila().addDays(-1),
        lastReadingWh: current.lastReadingWh,
        createdAt: current.createdAt,
        updatedAt: current.updatedAt,
      ),
    ];
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);

    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      propertyRepository: fixture.properties,
      electricityRepository: fixture.electricity,
    );
    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go('/billing/electricity/batches/new');
    await tester.pumpAndSettle();

    expect(find.text('Record all room meters'), findsOneWidget);
    expect(find.text('Room A'), findsOneWidget);
    expect(find.textContaining('Previous: 113 kWh'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byKey(const Key('batch-rate-field')), '13.186');
    await tester.enterText(
      find.byKey(const Key('batch-reading-room-a')),
      '120',
    );
    final review = find.byKey(const Key('review-reading-batch'));
    await tester.scrollUntilVisible(
      review,
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(review);
    await tester.pumpAndSettle();

    expect(find.text('Review the batch'), findsOneWidget);
    expect(find.textContaining('7 kWh'), findsWidgets);
    expect(tester.takeException(), isNull);
    final finalize = find.byKey(const Key('finalize-reading-batch'));
    await tester.scrollUntilVisible(
      finalize,
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(finalize);
    await tester.pumpAndSettle();

    expect(fixture.electricity.createBatchCalls, 1);
    expect(fixture.electricity.updateBatchCalls, 1);
    expect(fixture.electricity.finalizeBatchCalls, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openBilling(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Billing'),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('electricity-billing-card')), findsOneWidget);
  GoRouter.of(tester.element(find.byType(NavigationBar)))
      .go('/billing/electricity');
  await tester.pumpAndSettle();
}

class _ElectricityFixture {
  const _ElectricityFixture({
    required this.properties,
    required this.electricity,
  });

  factory _ElectricityFixture.create({bool includeRecord = false}) {
    final now = DateTime.utc(2026, 10, 14, 1);
    final endDate = BusinessDate.todayInManila();
    var startDate = BusinessDate(endDate.year, endDate.month, 1);
    if (!startDate.isBefore(endDate)) {
      startDate = endDate.addDays(-1);
    }
    final spanDays = startDate.daysUntil(endDate);
    final middleDate = spanDays > 1 ? startDate.addDays(spanDays ~/ 2) : null;

    final room = Room(
      roomId: 'room-a',
      roomName: 'Room A',
      description: 'Ground floor',
      status: RoomStatus.active,
      defaultMonthlyRentCentavos: 350000,
      activeOccupancyCount: 2,
      createdAt: now,
      updatedAt: now,
    );
    final boarders = [
      Boarder(
        boarderId: 'boarder-a',
        fullName: 'Ana Cruz',
        contact: '09170000001',
        notes: null,
        status: BoarderStatus.active,
        currentOccupancyId: 'occupancy-a',
        currentRoomId: room.roomId,
        currentMoveInDate: startDate,
        lastMoveOutDate: null,
        createdAt: now,
        updatedAt: now,
      ),
      Boarder(
        boarderId: 'boarder-b',
        fullName: 'Ben Lim',
        contact: null,
        notes: null,
        status: BoarderStatus.active,
        currentOccupancyId: 'occupancy-b',
        currentRoomId: room.roomId,
        currentMoveInDate: startDate,
        lastMoveOutDate: null,
        createdAt: now,
        updatedAt: now,
      ),
    ];
    final occupancies = [
      Occupancy(
        occupancyId: 'occupancy-a',
        boarderId: 'boarder-a',
        roomId: room.roomId,
        moveInDate: startDate,
        moveOutDate: null,
        createdAt: now,
        updatedAt: now,
      ),
      Occupancy(
        occupancyId: 'occupancy-b',
        boarderId: 'boarder-b',
        roomId: room.roomId,
        moveInDate: startDate,
        moveOutDate: null,
        createdAt: now,
        updatedAt: now,
      ),
    ];
    const meterId = 'meter-room-a-1';
    final meter = ElectricityMeter(
      meterId: meterId,
      roomId: room.roomId,
      sequence: 1,
      status: ElectricityMeterStatus.active,
      startedOn: startDate,
      endedOn: null,
      startKind: ElectricityMeterStartKind.initial,
      transitionReason: null,
      previousMeterId: null,
      replacementMeterId: null,
      lastReadingId: 'reading-end',
      lastReadingDate: endDate,
      lastReadingWh: 113000,
      createdAt: now,
      updatedAt: now,
    );
    final readings = <MeterReading>[
      MeterReading(
        readingId: 'reading-start',
        meterId: meterId,
        roomId: room.roomId,
        sequence: 1,
        readingDate: startDate,
        readingWh: 100000,
        kind: MeterReadingKind.opening,
        previousReadingId: null,
        previousReadingDate: null,
        previousReadingWh: null,
        consumptionWh: 0,
        note: 'Opening baseline',
        createdAt: now,
      ),
      if (middleDate != null)
        MeterReading(
          readingId: 'reading-middle',
          meterId: meterId,
          roomId: room.roomId,
          sequence: 1,
          readingDate: middleDate,
          readingWh: 106000,
          kind: MeterReadingKind.intermediate,
          previousReadingId: 'reading-start',
          previousReadingDate: startDate,
          previousReadingWh: 100000,
          consumptionWh: 6000,
          note: 'Intermediate split',
          createdAt: now,
        ),
      MeterReading(
        readingId: 'reading-end',
        meterId: meterId,
        roomId: room.roomId,
        sequence: 1,
        readingDate: endDate,
        readingWh: 113000,
        kind: MeterReadingKind.regular,
        previousReadingId: middleDate == null
            ? 'reading-start'
            : 'reading-middle',
        previousReadingDate: middleDate ?? startDate,
        previousReadingWh: middleDate == null ? 100000 : 106000,
        consumptionWh: middleDate == null ? 13000 : 7000,
        note: null,
        createdAt: now,
      ),
    ];

    final properties = FakePropertyRepository()
      ..rooms = [room]
      ..boarders = boarders;
    properties.occupancies['boarder-a'] = [occupancies[0]];
    properties.occupancies['boarder-b'] = [occupancies[1]];

    final electricity = FakeElectricityRepository()
      ..states = [
        RoomMeterState(
          roomId: room.roomId,
          currentMeterId: meterId,
          lastTransitionId: meterId,
          createdAt: now,
          updatedAt: now,
        ),
      ]
      ..meters = [meter]
      ..readings = readings;

    if (includeRecord) {
      final result = const ElectricityCalculator().calculate(
        ElectricityCalculationInput(
          startDate: startDate,
          endDateExclusive: endDate,
          rateMicropesosPerKwh: 12000000,
          rooms: [room],
          meters: [meter],
          readings: readings,
          occupancies: occupancies,
          boarders: boarders,
        ),
      );
      electricity.records = [
        ElectricityBillingRecord.fromResult(
          billingRecordId: 'electricity-period-1',
          result: result,
          recordedAt: now,
        ),
      ];
    }

    return _ElectricityFixture(
      properties: properties,
      electricity: electricity,
    );
  }

  final FakePropertyRepository properties;
  final FakeElectricityRepository electricity;
}
