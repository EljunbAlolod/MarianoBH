import 'dart:async';
import 'dart:typed_data';

import 'package:boarding_house_manager/features/reports/application/billing_pdf_generator.dart';
import 'package:boarding_house_manager/features/reports/domain/billing_report_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes.dart';
import '../../../helpers/pump_app.dart';
import '../report_fixture.dart';

void main() {
  testWidgets('report controls reflow on a narrow large-text phone', (
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
    final report = reportFixture();
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    final billing = FakeMonthlyBillingRepository()
      ..cycles = [report.cycle]
      ..controls = [report.control]
      ..accounts = report.boarders.map((item) => item.account).toList()
      ..payments = report.payments;
    final electricity = FakeElectricityRepository()
      ..records = [report.electricity];
    final water = FakeWaterRepository()..records = [report.water];
    final rent = FakeRentRepository()..records = [report.rent];
    final generator = _PendingPdfGenerator();
    addTearDown(() {
      generator.complete();
      return auth.dispose();
    });

    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      monthlyBillingRepository: billing,
      electricityRepository: electricity,
      waterRepository: water,
      rentRepository: rent,
      billingPdfGenerator: generator,
    );
    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go('/billing/monthly/cycle-1/reports');
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Create a billing PDF'), findsOneWidget);
    expect(find.byKey(const Key('report-type-field')), findsOneWidget);
    expect(find.byKey(const Key('save-pdf-button')), findsOneWidget);
    expect(find.byKey(const Key('share-pdf-button')), findsOneWidget);
    expect(find.text('Preparing PDF preview...'), findsOneWidget);
    expect(generator.buildCalls, 1);
    expect(tester.takeException(), isNull);
  });
}

class _PendingPdfGenerator extends BillingPdfGenerator {
  final _completer = Completer<Uint8List>();
  int buildCalls = 0;

  @override
  Future<Uint8List> build({
    required BillingReportSnapshot report,
    required BillingReportDocumentType type,
    String? boarderId,
  }) {
    buildCalls++;
    return _completer.future;
  }

  void complete() {
    if (!_completer.isCompleted) _completer.complete(Uint8List(0));
  }
}
