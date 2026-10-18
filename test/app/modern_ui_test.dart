import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

import 'package:boarding_house_manager/features/billing/domain/utility_billing_models.dart';
import 'package:boarding_house_manager/shared/widgets/app_components.dart';

void main() {
  testWidgets('wide navigation rail switches tabs', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    addTearDown(auth.dispose);
    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: FakeOwnerRepository()..workspace = ownerWorkspace,
    );
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Rooms'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Home reports current combined utility balances', (tester) async {
    final billing = FakeMonthlyBillingRepository()
      ..utilityRoomAccounts = [
        UtilityRoomBillAccount(
          accountId: 'bill-room',
          billingBatchId: 'bill',
          roomId: 'room',
          roomName: '201',
          totalChargesCentavos: 9000,
          totalPaidCentavos: 3000,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ];
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    addTearDown(auth.dispose);
    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: FakeOwnerRepository()..workspace = ownerWorkspace,
      monthlyBillingRepository: billing,
    );
    final amounts = tester
        .widgetList<FinancialAmount>(find.byType(FinancialAmount))
        .map((v) => v.centavos);
    expect(amounts, containsAll([6000, 3000]));
    expect(find.text('No finalized billing period yet'), findsNothing);
  });
  for (final width in [360.0, 375.0, 412.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        testWidgets(
          'modern navigation reflows at $width / $scale / $brightness',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 900);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            tester.platformDispatcher.platformBrightnessTestValue = brightness;
            addTearDown(() {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
              tester.platformDispatcher.clearTextScaleFactorTestValue();
              tester.platformDispatcher.clearPlatformBrightnessTestValue();
            });
            final auth = FakeAuthRepository(initialUser: verifiedUser);
            addTearDown(auth.dispose);
            await pumpTestApp(
              tester,
              authRepository: auth,
              ownerRepository: FakeOwnerRepository()
                ..workspace = ownerWorkspace,
            );
            expect(tester.takeException(), isNull);
            final router = GoRouter.of(
              tester.element(find.byType(NavigationBar)),
            );
            for (final route in ['/billing', '/rooms', '/boarders']) {
              router.go(route);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: route);
            }
            await tester.enterText(
              find.byKey(const Key('boarder-search')),
              'Maria',
            );
            await tester.pumpAndSettle();
            final nav = tester.widget<NavigationBar>(
              find.byType(NavigationBar),
            );
            nav.onDestinationSelected!(0);
            await tester.pumpAndSettle();
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .onDestinationSelected!(2);
            await tester.pumpAndSettle();
            expect(
              find.text('Maria'),
              findsOneWidget,
              reason: 'Search state survives tab changes',
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  const previewFont = String.fromEnvironment('UI_PREVIEW_FONT');
  testWidgets('capture modern Home and Billing previews', (tester) async {
    for (final family in ['Roboto', 'Ahem']) {
      final loader = FontLoader(family);
      loader.addFont(
        Future.value(ByteData.sublistView(File(previewFont).readAsBytesSync())),
      );
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    addTearDown(auth.dispose);
    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: FakeOwnerRepository()..workspace = ownerWorkspace,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../docs/ui-previews/home.png'),
    );
    GoRouter.of(tester.element(find.byType(NavigationBar))).go('/billing');
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../docs/ui-previews/billing.png'),
    );
    for (final page in ['rooms', 'boarders']) {
      GoRouter.of(tester.element(find.byType(NavigationBar))).go('/$page');
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../docs/ui-previews/$page.png'),
      );
    }
    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go('/billing/monthly/new');
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../docs/ui-previews/create-bill.png'),
    );
    auth.emit(null);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../docs/ui-previews/login.png'),
    );
  }, skip: previewFont.isEmpty);
}
