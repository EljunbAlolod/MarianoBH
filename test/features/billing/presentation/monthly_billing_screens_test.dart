import 'dart:async';
import 'dart:typed_data';

import 'package:boarding_house_manager/features/billing/domain/monthly_billing_models.dart';
import 'package:boarding_house_manager/features/billing/domain/room_billing_models.dart';
import 'package:boarding_house_manager/features/billing/domain/utility_billing_models.dart';
import 'package:boarding_house_manager/features/electricity/domain/electricity_batch_models.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/reports/application/utility_billing_pdf_generator.dart';
import 'package:boarding_house_manager/features/water/domain/water_batch_models.dart';
import 'package:boarding_house_manager/features/water/domain/water_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes.dart';
import '../../../helpers/pump_app.dart';

void main() {
  testWidgets('room billing dashboard and partial payment work on a phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final billing = _roomBillingFixture();
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);
    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      monthlyBillingRepository: billing,
    );

    _go(tester, '/billing/monthly');
    await tester.pumpAndSettle();
    expect(find.text('Room billing dashboard'), findsOneWidget);
    expect(find.text('Legacy room bill history'), findsOneWidget);
    expect(find.text('Partially paid'), findsWidgets);
    expect(tester.takeException(), isNull);

    _go(tester, '/billing/monthly/room/room-cycle-1');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Rent'), findsNothing);
    await tester.tap(find.byKey(const Key('record-room-payment-room-a')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const Key('room-payment-amount-field')),
      '500',
    );
    await tester.tap(find.text('Record payment').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(billing.paymentCalls, 1);
  });

  testWidgets('monthly overview reflows on a narrow large-text phone', (
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
    final billing = _billingFixture();
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);

    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      monthlyBillingRepository: billing,
    );
    _go(tester, '/billing/monthly/legacy');
    await tester.pumpAndSettle();

    expect(find.text('Legacy boarder bills'), findsWidgets);
    expect(find.textContaining('Read-only archive through'), findsOneWidget);
    expect(find.text('Partially paid'), findsWidgets);
    expect(find.text('Billing history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('combined utility batches finalize on a narrow dark-mode phone', (
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
    final billing = FakeMonthlyBillingRepository();
    final electricity = FakeElectricityRepository()
      ..batches = [_electricityBatch()];
    final water = FakeWaterRepository()..batches = [_waterBatch()];
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);
    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      monthlyBillingRepository: billing,
      electricityRepository: electricity,
      waterRepository: water,
    );

    _go(tester, '/billing/monthly/new');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final electricityCard = find.byKey(
      const Key('select-electricity-electricity-july'),
    );
    tester
        .widget<InkWell>(
          find.descendant(of: electricityCard, matching: find.byType(InkWell)),
        )
        .onTap!();
    await tester.pumpAndSettle();
    final waterCard = find.byKey(const Key('select-water-water-may'));
    tester
        .widget<InkWell>(
          find.descendant(of: waterCard, matching: find.byType(InkWell)),
        )
        .onTap!();
    await tester.pumpAndSettle();
    final reviewButton = find.byKey(const Key('review-utility-bills-button'));
    await tester.ensureVisible(reviewButton);
    tester.widget<FilledButton>(reviewButton).onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('Rent: not included'), findsOneWidget);
    final finalizeButton = find.byKey(
      const Key('finalize-utility-bills-button'),
    );
    await tester.ensureVisible(finalizeButton);
    tester.widget<FilledButton>(finalizeButton).onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finalize bills'));
    await tester.pumpAndSettle();

    expect(billing.finalizeUtilityBatchCalls, 1);
    expect(billing.lastUtilityResult?.totalBilledCentavos, 420000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('combined utility selection remains usable in phone landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(812, 375);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final billing = FakeMonthlyBillingRepository();
    final electricity = FakeElectricityRepository()
      ..batches = [_electricityBatch()];
    final water = FakeWaterRepository()..batches = [_waterBatch()];
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);
    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      monthlyBillingRepository: billing,
      electricityRepository: electricity,
      waterRepository: water,
    );

    _go(tester, '/billing/monthly/new');
    await tester.pumpAndSettle();

    expect(find.text('Select utility batches'), findsOneWidget);
    expect(
      find.byKey(const Key('select-electricity-electricity-july')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('created utility bills reflow with payment status on a phone', (
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
    final billing = _utilityBillingFixture();
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);
    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      monthlyBillingRepository: billing,
    );

    _go(tester, '/billing/created');
    await tester.pumpAndSettle();

    expect(find.text('Created utility bills'), findsOneWidget);
    expect(find.text('UB-2026-07-001'), findsOneWidget);
    expect(find.text('Partially paid'), findsWidgets);
    expect(
      find.byKey(const Key('created-bill-pdf-utility-bill-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('records a partial payment on a created room utility bill', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final billing = _utilityBillingFixture();
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);
    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      monthlyBillingRepository: billing,
    );

    _go(tester, '/billing/utility/utility-bill-1');
    await tester.pumpAndSettle();
    final paymentButton = find.byKey(
      const Key('record-utility-payment-room-a'),
    );
    tester.widget<FilledButton>(paymentButton).onPressed!();
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('utility-payment-amount-field')),
      '500',
    );
    await tester.tap(find.text('Record payment').last);
    await tester.pumpAndSettle();

    expect(billing.paymentCalls, 1);
    expect(billing.lastPaymentBillingBatchId, 'utility-bill-1');
    expect(billing.lastPaymentRoomId, 'room-a');
    expect(billing.lastPaymentAmountCentavos, 50000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('utility PDF controls stay accessible while preview loads', (
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
    final billing = _utilityBillingFixture();
    final generator = _PendingUtilityPdfGenerator();
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(() {
      generator.complete();
      return auth.dispose();
    });
    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      monthlyBillingRepository: billing,
      utilityBillingPdfGenerator: generator,
    );

    _go(tester, '/billing/utility/utility-bill-1/pdf');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('utility-pdf-type-field')), findsOneWidget);
    expect(find.byKey(const Key('share-utility-pdf-button')), findsOneWidget);
    expect(find.byKey(const Key('save-utility-pdf-button')), findsOneWidget);
    expect(find.text('Preparing PDF preview...'), findsOneWidget);
    expect(generator.buildCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('monthly finalization explains missing exact-date sources', (
    tester,
  ) async {
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);
    await pumpTestApp(tester, authRepository: auth, ownerRepository: owners);

    _go(tester, '/billing/monthly/legacy/new');
    await tester.pumpAndSettle();

    expect(find.text('Select billing period'), findsOneWidget);
    expect(find.text('Exact-date record required'), findsNWidgets(3));
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('review-monthly-bill-button')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('legacy boarder bill detail is read-only', (tester) async {
    final billing = _billingFixture();
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);
    await pumpTestApp(
      tester,
      authRepository: auth,
      ownerRepository: owners,
      monthlyBillingRepository: billing,
    );

    _go(tester, '/billing/monthly/cycle-1');
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Legacy boarder bills are read-only'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('record-payment-boarder-a')), findsNothing);
    expect(billing.paymentCalls, 0);
  });
}

FakeMonthlyBillingRepository _roomBillingFixture() {
  final start = BusinessDate(2026, 10, 1);
  final end = BusinessDate(2026, 11, 1);
  final statement = RoomMonthlyStatement(
    roomId: 'room-a',
    roomName: 'Room 201',
    occupiedRanges: [
      OccupiedDateRange(startDate: start, endDateExclusive: end),
    ],
    occupiedDays: 31,
    rentCentavos: 0,
    adjustmentCentavos: 0,
    electricityCentavos: 60000,
    waterCentavos: 40000,
    currentChargesCentavos: 100000,
  );
  final cycle = RoomBillingCycle(
    billingCycleId: 'room-cycle-1',
    periodId: '2026-10-01_2026-11-01',
    version: 1,
    replacesCycleId: null,
    startDate: start,
    endDateExclusive: end,
    electricityRecordId: 'electricity-room',
    waterRecordId: 'water-room',
    rentRecordId: roomBillingNoRentRecordId,
    electricityTotalCentavos: 60000,
    waterTotalCentavos: 40000,
    rentTotalCentavos: 0,
    adjustmentTotalCentavos: 0,
    totalBilledCentavos: 100000,
    totalUnallocatedCentavos: 0,
    statements: [statement],
    warnings: const [],
    finalizedAt: DateTime.utc(2026, 11, 1),
  );
  return FakeMonthlyBillingRepository()
    ..roomCycles = [cycle]
    ..roomControls = [
      BillingCycleControl(
        billingCycleId: cycle.billingCycleId,
        state: BillingCycleState.active,
        totalBilledCentavos: 100000,
        totalPaidCentavos: 50000,
        outstandingCentavos: 50000,
        voidReason: null,
        voidedAt: null,
        reissuedAsCycleId: null,
        updatedAt: DateTime.utc(2026, 11, 2),
      ),
    ]
    ..roomAccounts = [
      RoomBillAccount(
        accountId: 'room-cycle-1_room-a',
        billingCycleId: cycle.billingCycleId,
        roomId: 'room-a',
        roomName: 'Room 201',
        totalChargesCentavos: 100000,
        totalPaidCentavos: 50000,
        updatedAt: DateTime.utc(2026, 11, 2),
      ),
    ];
}

FakeMonthlyBillingRepository _utilityBillingFixture() {
  final createdAt = DateTime.utc(2026, 7, 5);
  final batch = UtilityBillingBatch(
    billingBatchId: 'utility-bill-1',
    billingBatchReference: 'UB-2026-07-001',
    status: UtilityBillingBatchStatus.finalized,
    issuedOn: BusinessDate(2026, 7, 5),
    electricityBatchId: 'electricity-july',
    electricityBatchReference: 'EB-2026-07-001',
    electricityMeasurementStart: BusinessDate(2026, 6, 10),
    electricityMeasurementEnd: BusinessDate(2026, 7, 1),
    electricityRateMicropesosPerKwh: 10000000,
    sourceReadingIds: const ['reading-1'],
    waterBatchId: 'water-may',
    waterBatchReference: 'WB-2026-05-001',
    waterPeriodStart: BusinessDate(2026, 5, 1),
    waterPeriodEndExclusive: BusinessDate(2026, 6, 1),
    waterReceiptDate: BusinessDate(2026, 6, 5),
    waterMethod: WaterBillingMethod.personDays,
    waterSummerBasis: SummerElectricityBasis.roomElectricityCharge,
    waterReferenceElectricityBatchId: null,
    waterReferenceElectricityBatchReference: null,
    associationMismatchConfirmed: false,
    electricityTotalCentavos: 120000,
    waterTotalCentavos: 300000,
    adjustmentTotalCentavos: 0,
    totalBilledCentavos: 420000,
    totalUnallocatedCentavos: 0,
    statements: const [
      RoomUtilityBillStatement(
        roomId: 'room-a',
        roomName: 'Room 201',
        electricityCentavos: 120000,
        waterCentavos: 300000,
        adjustmentCentavos: 0,
        totalCentavos: 420000,
      ),
    ],
    warnings: const [],
    createdAt: createdAt,
    voidReason: null,
    voidedAt: null,
  );
  return FakeMonthlyBillingRepository()
    ..utilityBatches = [batch]
    ..utilityRoomAccounts = [
      UtilityRoomBillAccount(
        accountId: 'utility-bill-1_room-a',
        billingBatchId: 'utility-bill-1',
        roomId: 'room-a',
        roomName: 'Room 201',
        totalChargesCentavos: 420000,
        totalPaidCentavos: 100000,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    ]
    ..utilityRoomPayments = [
      UtilityRoomPaymentRecord(
        paymentId: 'payment-1',
        billingBatchId: 'utility-bill-1',
        accountId: 'utility-bill-1_room-a',
        roomId: 'room-a',
        roomName: 'Room 201',
        amountCentavos: 100000,
        paymentDate: BusinessDate(2026, 7, 5),
        method: PaymentMethod.gcash,
        notes: 'Deposit',
        recordedAt: createdAt,
      ),
    ];
}

class _PendingUtilityPdfGenerator extends UtilityBillingPdfGenerator {
  final _completer = Completer<Uint8List>();
  int buildCalls = 0;

  @override
  Future<Uint8List> build({
    required String houseName,
    required UtilityBillingBatch batch,
    required List<UtilityRoomBillAccount> accounts,
    required List<UtilityRoomPaymentRecord> payments,
    required UtilityBillingPdfDocumentType type,
    String? roomId,
  }) {
    buildCalls++;
    return _completer.future;
  }

  void complete() {
    if (!_completer.isCompleted) _completer.complete(Uint8List(0));
  }
}

void _go(WidgetTester tester, String location) {
  GoRouter.of(tester.element(find.byType(NavigationBar))).go(location);
}

FakeMonthlyBillingRepository _billingFixture() {
  final start = BusinessDate(2026, 10, 1);
  final end = BusinessDate(2026, 11, 1);
  final cycle = MonthlyBillingCycle(
    billingCycleId: 'cycle-1',
    periodId: '2026-10-01_2026-11-01',
    version: 1,
    replacesCycleId: null,
    startDate: start,
    endDateExclusive: end,
    electricityRecordId: 'electricity-1',
    waterRecordId: 'water-1',
    rentRecordId: 'rent-1',
    electricityTotalCentavos: 60000,
    waterTotalCentavos: 40000,
    rentTotalCentavos: 160000,
    rentAdjustmentCentavos: 1500,
    totalBilledCentavos: 261500,
    totalUnallocatedCentavos: 0,
    statements: [
      BoarderMonthlyStatement(
        boarderId: 'boarder-a',
        boarderName: 'Ana Cruz',
        roomIds: const ['room-a'],
        rentCentavos: 160000,
        rentAdjustmentCentavos: 1500,
        electricityCentavos: 60000,
        waterCentavos: 40000,
        currentChargesCentavos: 261500,
        previousBalanceCentavos: 2500,
      ),
    ],
    warnings: const [],
    finalizedAt: DateTime.utc(2026, 11, 1),
  );
  final control = BillingCycleControl(
    billingCycleId: cycle.billingCycleId,
    state: BillingCycleState.active,
    totalBilledCentavos: cycle.totalBilledCentavos,
    totalPaidCentavos: 100000,
    outstandingCentavos: 161500,
    voidReason: null,
    voidedAt: null,
    reissuedAsCycleId: null,
    updatedAt: DateTime.utc(2026, 11, 2),
  );
  final account = BoarderBillAccount(
    accountId: 'cycle-1_boarder-a',
    billingCycleId: cycle.billingCycleId,
    boarderId: 'boarder-a',
    boarderName: 'Ana Cruz',
    totalChargesCentavos: cycle.totalBilledCentavos,
    previousBalanceCentavos: 2500,
    totalPaidCentavos: 100000,
    updatedAt: DateTime.utc(2026, 11, 2),
  );
  return FakeMonthlyBillingRepository()
    ..cycles = [cycle]
    ..controls = [control]
    ..accounts = [account]
    ..payments = [
      PaymentRecord(
        paymentId: 'payment-1',
        billingCycleId: cycle.billingCycleId,
        boarderId: account.boarderId,
        boarderName: account.boarderName,
        amountCentavos: 100000,
        paymentDate: BusinessDate(2026, 11, 2),
        method: PaymentMethod.gcash,
        notes: 'Reference 123',
        recordedAt: DateTime.utc(2026, 11, 2),
      ),
    ];
}

ElectricityReadingBatch _electricityBatch() {
  final now = DateTime.utc(2026, 7, 1);
  return ElectricityReadingBatch(
    batchId: 'electricity-july',
    batchReference: 'EB-2026-07-001',
    status: ElectricityReadingBatchStatus.finalized,
    effectiveDate: BusinessDate(2026, 7, 1),
    effectiveAt: now,
    rateMicropesosPerKwh: 10000000,
    entries: [
      ElectricityReadingBatchEntry(
        roomId: 'room-a',
        roomName: 'Room 201',
        meterId: 'meter-a',
        sequence: 1,
        previousReadingId: 'reading-0',
        previousReadingDate: BusinessDate(2026, 6, 10),
        previousReadingWh: 100000,
        targetReadingId: 'reading-1',
        status: ElectricityBatchEntryStatus.recorded,
        currentReadingWh: 112000,
        actualReadAt: now,
        readingId: 'reading-1',
        consumptionWh: 12000,
        chargeCentavos: 120000,
        exclusionReason: null,
      ),
    ],
    roomCount: 1,
    pendingCount: 0,
    recordedCount: 1,
    excludedCount: 0,
    totalConsumptionWh: 12000,
    totalChargeCentavos: 120000,
    version: 2,
    lastLinkId: 'reading-1',
    createdAt: now,
    updatedAt: now,
    finalizedAt: now,
    usedAt: null,
    voidReason: null,
    voidedAt: null,
  );
}

WaterBillingBatch _waterBatch() {
  final now = DateTime.utc(2026, 6, 5);
  return WaterBillingBatch(
    batchId: 'water-may',
    batchReference: 'WB-2026-05-001',
    status: WaterBillingBatchStatus.finalized,
    startDate: BusinessDate(2026, 5, 1),
    endDateExclusive: BusinessDate(2026, 6, 1),
    receiptDate: BusinessDate(2026, 6, 5),
    waterBillCentavos: 300000,
    method: WaterBillingMethod.personDays,
    summerBasis: SummerElectricityBasis.roomElectricityCharge,
    electricityBatchId: null,
    electricityBatchReference: null,
    electricityMeasurementStart: null,
    electricityMeasurementEnd: null,
    referencePeriodMismatchConfirmed: false,
    referenceExplanation: null,
    notes: null,
    totalPersonDays: 31,
    totalElectricityBasis: 0,
    totalAllocatedCentavos: 300000,
    totalUnallocatedCentavos: 0,
    roomAllocations: [
      WaterRoomAllocation(
        roomId: 'room-a',
        roomName: 'Room 201',
        electricityBasisValue: 0,
        occupancyDays: 31,
        roomChargeCentavos: 300000,
        allocatedCentavos: 300000,
        unallocatedCentavos: 0,
        boarderShares: const [],
      ),
    ],
    boarderShares: const [],
    warnings: const [],
    version: 2,
    createdAt: now,
    updatedAt: now,
    finalizedAt: now,
    usedAt: null,
    voidReason: null,
    voidedAt: null,
  );
}
