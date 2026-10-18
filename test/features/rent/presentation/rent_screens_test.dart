import 'package:boarding_house_manager/features/property_management/domain/boarder.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/property_management/domain/occupancy.dart';
import 'package:boarding_house_manager/features/property_management/domain/room.dart';
import 'package:boarding_house_manager/features/rent/domain/rent_calculator.dart';
import 'package:boarding_house_manager/features/rent/domain/rent_cycle_models.dart';
import 'package:boarding_house_manager/features/rent/domain/rent_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes.dart';
import '../../../helpers/pump_app.dart';

void main() {
  testWidgets('billing hub and rent overview reflow on a narrow phone', (
    tester,
  ) async {
    _useNarrowLargeText(tester);
    final fixture = _RentFixture.create(includeRecord: true);
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);

    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      propertyRepository: fixture.properties,
      rentRepository: fixture.rent,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Billing'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rent-billing-card')), findsOneWidget);

    GoRouter.of(tester.element(find.byType(NavigationBar))).go('/billing/rent');
    await tester.pumpAndSettle();
    expect(find.text('Fixed monthly rent'), findsOneWidget);
    expect(find.text('Legacy rent archive'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy rent creation route returns to fixed rent dashboard', (
    tester,
  ) async {
    _useNarrowLargeText(tester);
    final fixture = _RentFixture.create();
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);
    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      propertyRepository: fixture.properties,
      rentRepository: fixture.rent,
    );

    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go('/billing/rent/new');
    await tester.pumpAndSettle();
    expect(find.text('Fixed monthly rent'), findsOneWidget);
    expect(find.byKey(const Key('review-rent-button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'active agreement shows accruing coverage and anniversary due date',
    (tester) async {
      _useNarrowLargeText(tester);
      final fixture = _RentFixture.create(includeAgreement: true);
      final auth = FakeAuthRepository(initialUser: verifiedUser);
      final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
      addTearDown(auth.dispose);
      await pumpTestApp(
        tester,
        authRepository: auth,
        ownerRepository: owners,
        propertyRepository: fixture.properties,
        rentRepository: fixture.rent,
      );

      GoRouter.of(tester.element(find.byType(NavigationBar)))
          .go('/billing/rent');
      await tester.pumpAndSettle();

      expect(find.text('Current coverage'), findsOneWidget);
      expect(find.text('Accruing'), findsOneWidget);
      expect(find.textContaining('Due '), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'landlady can record a manual extra-stay charge on a large-text phone',
    (tester) async {
      _useNarrowLargeText(tester);
      final fixture = _RentFixture.create(movedOutWithExtraStay: true);
      final auth = FakeAuthRepository(initialUser: verifiedUser);
      final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
      addTearDown(auth.dispose);
      await pumpTestApp(
        tester,
        authRepository: auth,
        ownerRepository: owners,
        propertyRepository: fixture.properties,
        rentRepository: fixture.rent,
      );

      GoRouter.of(tester.element(find.byType(NavigationBar)))
          .go('/billing/rent');
      await tester.pumpAndSettle();

      expect(find.text('Move-out decisions'), findsOneWidget);
      final resolveButton = find.widgetWithText(
        FilledButton,
        'Resolve extra stay',
      );
      tester.widget<FilledButton>(resolveButton).onPressed!();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), '1,234.50');
      await tester.enterText(fields.at(1), 'Five extra days by agreement.');
      await tester.ensureVisible(find.text('Record decision'));
      await tester.tap(find.text('Record decision'));
      await tester.pumpAndSettle();

      expect(fixture.rent.resolveExtraStayCalls, 1);
      expect(
        fixture.rent.lastExtraStayDecision,
        ExtraStayDecision.manualCharge,
      );
      expect(fixture.rent.lastExtraStayAmountCentavos, 123450);
      expect(fixture.rent.lastExtraStayMoveOutDate, BusinessDate(2026, 7, 15));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved rent history opens as a read-only snapshot', (
    tester,
  ) async {
    final fixture = _RentFixture.create(includeRecord: true);
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);
    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      propertyRepository: fixture.properties,
      rentRepository: fixture.rent,
    );
    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go('/billing/rent/rent-period-1');
    await tester.pumpAndSettle();

    expect(find.text('Read-only historical record'), findsOneWidget);
    expect(find.text('Boarder charges'), findsOneWidget);
    expect(find.text('Room breakdown'), findsOneWidget);
    expect(find.text('Ana Cruz'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

void _useNarrowLargeText(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(375, 812);
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

class _RentFixture {
  const _RentFixture({required this.properties, required this.rent});

  factory _RentFixture.create({
    bool includeRecord = false,
    bool includeAgreement = false,
    bool missingRent = false,
    bool movedOutWithExtraStay = false,
  }) {
    final now = DateTime.utc(2026, 10, 14);
    final end = BusinessDate.todayInManila();
    var start = movedOutWithExtraStay
        ? BusinessDate(2026, 6, 10)
        : BusinessDate(end.year, end.month, 1);
    if (!start.isBefore(end)) start = end.addDays(-1);
    final room = Room(
      roomId: 'room-a',
      roomName: 'Room A',
      description: '',
      status: RoomStatus.active,
      defaultMonthlyRentCentavos: missingRent ? null : 310000,
      activeOccupancyCount: movedOutWithExtraStay ? 0 : 1,
      createdAt: now,
      updatedAt: now,
    );
    final boarder = Boarder(
      boarderId: 'boarder-a',
      fullName: 'Ana Cruz',
      contact: null,
      notes: null,
      status: movedOutWithExtraStay
          ? BoarderStatus.inactive
          : BoarderStatus.active,
      currentOccupancyId: movedOutWithExtraStay ? null : 'occupancy-a',
      currentRoomId: movedOutWithExtraStay ? null : room.roomId,
      currentMoveInDate: movedOutWithExtraStay ? null : start,
      lastMoveOutDate: movedOutWithExtraStay ? BusinessDate(2026, 7, 15) : null,
      createdAt: now,
      updatedAt: now,
    );
    final occupancy = Occupancy(
      occupancyId: 'occupancy-a',
      boarderId: boarder.boarderId,
      roomId: room.roomId,
      moveInDate: start,
      moveOutDate: movedOutWithExtraStay ? BusinessDate(2026, 7, 15) : null,
      createdAt: now,
      updatedAt: now,
    );
    final properties = FakePropertyRepository()
      ..rooms = [room]
      ..boarders = [boarder];
    properties.occupancies[boarder.boarderId] = [occupancy];
    final rent = FakeRentRepository();
    if (includeAgreement || movedOutWithExtraStay) {
      rent.agreements = [
        RentAgreement(
          agreementId: occupancy.occupancyId,
          occupancyId: occupancy.occupancyId,
          boarderId: boarder.boarderId,
          boarderName: boarder.fullName,
          roomId: room.roomId,
          roomName: room.roomName,
          startDate: occupancy.moveInDate,
          anchorDay: occupancy.moveInDate.day,
          monthlyRentCentavos: room.defaultMonthlyRentCentavos!,
          createdAt: now,
        ),
      ];
    }
    if (includeRecord) {
      final result = const RentCalculator().calculate(
        RentCalculationInput(
          startDate: start,
          endDateExclusive: end,
          mode: RentBillingMode.perBoarder,
          rooms: [room],
          boarders: [boarder],
          occupancies: [occupancy],
        ),
      );
      rent.records = [
        RentBillingRecord.fromResult(
          rentRecordId: 'rent-period-1',
          result: result,
          recordedAt: now,
        ),
      ];
    }
    return _RentFixture(properties: properties, rent: rent);
  }

  final FakePropertyRepository properties;
  final FakeRentRepository rent;
}
