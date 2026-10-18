import 'package:boarding_house_manager/features/property_management/domain/boarder.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/property_management/domain/room.dart';
import 'package:boarding_house_manager/features/property_management/presentation/widgets/property_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes.dart';
import '../../../helpers/pump_app.dart';

void main() {
  testWidgets('room details opens and Back preserves the room list', (
    tester,
  ) async {
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    addTearDown(auth.dispose);
    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: FakeOwnerRepository()..workspace = ownerWorkspace,
      propertyRepository: _populatedProperties(),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Rooms'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Room A'));
    await tester.tap(find.text('Room A'));
    await tester.pumpAndSettle();
    expect(find.text('Room details'), findsOneWidget);
    expect(find.text('Monthly rent'), findsOneWidget);
    expect(find.text('Ana Cruz'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-search')), findsOneWidget);
  });
  test('peso input converts to integer centavos without floating point', () {
    expect(parsePesoToCentavos('3,500.05'), 350005);
    expect(parsePesoToCentavos('3500'), 350000);
    expect(parsePesoToCentavos(''), isNull);
    expect(() => parsePesoToCentavos('10.999'), throwsFormatException);
  });

  testWidgets('room list shows multiple current boarders on a narrow phone', (
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

    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    final properties = _populatedProperties();
    addTearDown(auth.dispose);

    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      propertyRepository: properties,
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'The dashboard should reflow before opening Rooms.',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Rooms'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'The Rooms screen and bottom navigation should reflow.',
    );

    expect(find.text('Room A'), findsOneWidget);
    expect(find.text('2 boarders'), findsOneWidget);
    expect(find.text('Ana Cruz, Ben Lim'), findsOneWidget);
  });

  testWidgets('boarder list remains usable in landscape and dark mode', (
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

    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    final properties = _populatedProperties();
    addTearDown(auth.dispose);

    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      propertyRepository: properties,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Boarders'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ana Cruz'), findsOneWidget);
    expect(find.text('Ben Lim'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(NavigationBar))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });
}

FakePropertyRepository _populatedProperties() {
  final now = DateTime.utc(2026, 10, 13);
  final moveIn = BusinessDate(2026, 10, 1);
  return FakePropertyRepository()
    ..rooms = [
      Room(
        roomId: 'room-a',
        roomName: 'Room A',
        description: 'Ground floor',
        status: RoomStatus.active,
        defaultMonthlyRentCentavos: 350000,
        activeOccupancyCount: 2,
        createdAt: now,
        updatedAt: now,
      ),
    ]
    ..boarders = [
      Boarder(
        boarderId: 'boarder-a',
        fullName: 'Ana Cruz',
        contact: '09170000001',
        notes: null,
        status: BoarderStatus.active,
        currentOccupancyId: 'occupancy-a',
        currentRoomId: 'room-a',
        currentMoveInDate: moveIn,
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
        currentRoomId: 'room-a',
        currentMoveInDate: moveIn,
        lastMoveOutDate: null,
        createdAt: now,
        updatedAt: now,
      ),
    ];
}
