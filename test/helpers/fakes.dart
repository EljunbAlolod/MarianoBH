import 'dart:async';

import 'package:boarding_house_manager/features/authentication/domain/app_user.dart';
import 'package:boarding_house_manager/features/authentication/domain/auth_repository.dart';
import 'package:boarding_house_manager/features/billing/domain/monthly_billing_models.dart';
import 'package:boarding_house_manager/features/billing/domain/monthly_billing_repository.dart';
import 'package:boarding_house_manager/features/billing/domain/room_billing_models.dart';
import 'package:boarding_house_manager/features/billing/domain/utility_billing_models.dart';
import 'package:boarding_house_manager/features/electricity/domain/electricity_models.dart';
import 'package:boarding_house_manager/features/electricity/domain/electricity_repository.dart';
import 'package:boarding_house_manager/features/electricity/domain/electricity_batch_models.dart';
import 'package:boarding_house_manager/features/onboarding/domain/owner_repository.dart';
import 'package:boarding_house_manager/features/onboarding/domain/owner_workspace.dart';
import 'package:boarding_house_manager/features/property_management/domain/boarder.dart';
import 'package:boarding_house_manager/features/property_management/domain/business_date.dart';
import 'package:boarding_house_manager/features/property_management/domain/occupancy.dart';
import 'package:boarding_house_manager/features/property_management/domain/property_repository.dart';
import 'package:boarding_house_manager/features/property_management/domain/room.dart';
import 'package:boarding_house_manager/features/rent/domain/rent_models.dart';
import 'package:boarding_house_manager/features/rent/domain/rent_repository.dart';
import 'package:boarding_house_manager/features/rent/domain/rent_cycle_models.dart';
import 'package:boarding_house_manager/features/water/domain/water_models.dart';
import 'package:boarding_house_manager/features/water/domain/water_batch_models.dart';
import 'package:boarding_house_manager/features/water/domain/water_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AppUser? initialUser}) : _currentUser = initialUser {
    _controller = StreamController<AppUser?>.broadcast(
      onListen: () => scheduleMicrotask(() => _controller.add(_currentUser)),
    );
  }

  late final StreamController<AppUser?> _controller;
  AppUser? _currentUser;

  String? lastEmail;
  String? lastPassword;
  String? lastDisplayName;
  int signInCalls = 0;
  int signInWithGoogleCalls = 0;
  int registerCalls = 0;
  int resetCalls = 0;
  int verificationCalls = 0;
  int reloadCalls = 0;
  int signOutCalls = 0;
  AuthException? nextError;
  AppUser? signInResult;
  AppUser? googleSignInResult;
  AppUser? registerResult;

  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;

  @override
  AppUser? get currentUser => _currentUser;

  void emit(AppUser? user) {
    _currentUser = user;
    _controller.add(user);
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    lastEmail = email;
    lastPassword = password;
    _throwNextError();
    if (signInResult != null) emit(signInResult);
  }

  @override
  Future<void> signInWithGoogle() async {
    signInWithGoogleCalls++;
    _throwNextError();
    if (googleSignInResult != null) emit(googleSignInResult);
  }

  @override
  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    registerCalls++;
    lastDisplayName = displayName;
    lastEmail = email;
    lastPassword = password;
    _throwNextError();
    if (registerResult != null) emit(registerResult);
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    resetCalls++;
    lastEmail = email;
    _throwNextError();
  }

  @override
  Future<void> sendEmailVerification() async {
    verificationCalls++;
    _throwNextError();
  }

  @override
  Future<AppUser?> reloadCurrentUser() async {
    reloadCalls++;
    _throwNextError();
    return _currentUser;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _throwNextError();
    emit(null);
  }

  void _throwNextError() {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  Future<void> dispose() => _controller.close();
}

class FakeOwnerRepository implements OwnerRepository {
  OwnerWorkspace? workspace;
  OwnerRepositoryException? fetchError;
  OwnerRepositoryException? createError;
  int fetchCalls = 0;
  int createCalls = 0;
  String? lastOwnerName;
  String? lastHouseName;

  @override
  Future<OwnerWorkspace?> fetchWorkspace(AppUser user) async {
    fetchCalls++;
    final error = fetchError;
    if (error != null) throw error;
    return workspace;
  }

  @override
  Future<OwnerWorkspace> createWorkspace({
    required AppUser user,
    required String ownerName,
    required String houseName,
  }) async {
    createCalls++;
    lastOwnerName = ownerName;
    lastHouseName = houseName;
    final error = createError;
    if (error != null) throw error;
    return workspace = OwnerWorkspace(
      ownerUid: user.id,
      ownerName: ownerName.trim(),
      ownerEmail: user.email,
      houseName: houseName.trim(),
    );
  }
}

class FakePropertyRepository implements PropertyRepository {
  List<Room> rooms = [];
  List<Boarder> boarders = [];
  final Map<String, List<Occupancy>> occupancies = {};
  PropertyRepositoryException? nextError;
  int createRoomCalls = 0;
  int createBoarderCalls = 0;
  int transferCalls = 0;
  int moveOutCalls = 0;
  int moveInCalls = 0;
  String? lastRoomId;
  String? lastBoarderId;
  BusinessDate? lastBusinessDate;

  void _throwNextError() {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  @override
  Stream<List<Room>> watchRooms(String ownerId) => Stream.value(rooms);

  @override
  Stream<List<Boarder>> watchBoarders(String ownerId) => Stream.value(boarders);

  @override
  Stream<List<Occupancy>> watchOccupancies(String ownerId, String boarderId) =>
      Stream.value(occupancies[boarderId] ?? const []);

  @override
  Stream<List<Occupancy>> watchAllOccupancies(String ownerId) => Stream.value(
    occupancies.values.expand((items) => items).toList(growable: false),
  );

  @override
  Future<String> createRoom({
    required String ownerId,
    required String roomName,
    String description = '',
    int? defaultMonthlyRentCentavos,
  }) async {
    createRoomCalls++;
    _throwNextError();
    return 'room-$createRoomCalls';
  }

  @override
  Future<void> updateRoom({
    required String ownerId,
    required String roomId,
    required String roomName,
    String description = '',
    int? defaultMonthlyRentCentavos,
  }) async {
    lastRoomId = roomId;
    _throwNextError();
  }

  @override
  Future<void> deactivateRoom({
    required String ownerId,
    required String roomId,
  }) async {
    lastRoomId = roomId;
    _throwNextError();
  }

  @override
  Future<void> reactivateRoom({
    required String ownerId,
    required String roomId,
  }) async {
    lastRoomId = roomId;
    _throwNextError();
  }

  @override
  Future<String> createBoarder({
    required String ownerId,
    required String fullName,
    String? contact,
    String? notes,
    required String roomId,
    required BusinessDate moveInDate,
  }) async {
    createBoarderCalls++;
    lastRoomId = roomId;
    lastBusinessDate = moveInDate;
    _throwNextError();
    return 'boarder-$createBoarderCalls';
  }

  @override
  Future<void> updateBoarder({
    required String ownerId,
    required String boarderId,
    required String fullName,
    String? contact,
    String? notes,
  }) async {
    lastBoarderId = boarderId;
    _throwNextError();
  }

  @override
  Future<void> deactivateBoarder({
    required String ownerId,
    required String boarderId,
  }) async {
    lastBoarderId = boarderId;
    _throwNextError();
  }

  @override
  Future<void> moveOut({
    required String ownerId,
    required String boarderId,
    required BusinessDate moveOutDate,
  }) async {
    moveOutCalls++;
    lastBoarderId = boarderId;
    lastBusinessDate = moveOutDate;
    _throwNextError();
  }

  @override
  Future<void> moveIn({
    required String ownerId,
    required String boarderId,
    required String roomId,
    required BusinessDate moveInDate,
  }) async {
    moveInCalls++;
    lastBoarderId = boarderId;
    lastRoomId = roomId;
    lastBusinessDate = moveInDate;
    _throwNextError();
  }

  @override
  Future<void> transfer({
    required String ownerId,
    required String boarderId,
    required String toRoomId,
    required BusinessDate transferDate,
  }) async {
    transferCalls++;
    lastBoarderId = boarderId;
    lastRoomId = toRoomId;
    lastBusinessDate = transferDate;
    _throwNextError();
  }
}

class FakeMonthlyBillingRepository implements MonthlyBillingRepository {
  List<UtilityBillingBatch> utilityBatches = [];
  List<UtilityRoomBillAccount> utilityRoomAccounts = [];
  List<UtilityRoomPaymentRecord> utilityRoomPayments = [];
  List<MonthlyBillingCycle> cycles = [];
  List<BillingCycleControl> controls = [];
  List<BoarderBillAccount> accounts = [];
  List<PaymentRecord> payments = [];
  List<RoomBillingCycle> roomCycles = [];
  List<BillingCycleControl> roomControls = [];
  List<RoomBillAccount> roomAccounts = [];
  List<RoomPaymentRecord> roomPayments = [];
  MonthlyBillingRepositoryException? nextError;
  int finalizeCalls = 0;
  int finalizeUtilityBatchCalls = 0;
  int voidCalls = 0;
  int paymentCalls = 0;
  String? lastPaymentBillingBatchId;
  String? lastPaymentRoomId;
  int? lastPaymentAmountCentavos;
  MonthlyBillingResult? lastResult;
  RoomBillingResult? lastRoomResult;
  UtilityBillingResult? lastUtilityResult;

  @override
  Stream<List<UtilityBillingBatch>> watchUtilityBillingBatches(
    String ownerId,
  ) => Stream.value(utilityBatches);

  @override
  Stream<List<UtilityRoomBillAccount>> watchUtilityRoomAccounts(
    String ownerId,
  ) => Stream.value(utilityRoomAccounts);

  @override
  Stream<List<UtilityRoomPaymentRecord>> watchUtilityRoomPayments(
    String ownerId,
  ) => Stream.value(utilityRoomPayments);

  void _throwNextError() {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  @override
  Stream<List<MonthlyBillingCycle>> watchCycles(String ownerId) =>
      Stream.value(cycles);

  @override
  Stream<List<BillingCycleControl>> watchControls(String ownerId) =>
      Stream.value(controls);

  @override
  Stream<List<BoarderBillAccount>> watchAccounts(String ownerId) =>
      Stream.value(accounts);

  @override
  Stream<List<PaymentRecord>> watchPayments(String ownerId) =>
      Stream.value(payments);

  @override
  Stream<List<RoomBillingCycle>> watchRoomCycles(String ownerId) =>
      Stream.value(roomCycles);

  @override
  Stream<List<BillingCycleControl>> watchRoomControls(String ownerId) =>
      Stream.value(roomControls);

  @override
  Stream<List<RoomBillAccount>> watchRoomAccounts(String ownerId) =>
      Stream.value(roomAccounts);

  @override
  Stream<List<RoomPaymentRecord>> watchRoomPayments(String ownerId) =>
      Stream.value(roomPayments);

  @override
  Future<String> finalizeCycle({
    required String ownerId,
    required MonthlyBillingResult result,
  }) async {
    finalizeCalls++;
    lastResult = result;
    _throwNextError();
    return '${result.startDate}_${result.endDateExclusive}_v1';
  }

  @override
  Future<String> finalizeRoomCycle({
    required String ownerId,
    required RoomBillingResult result,
  }) async {
    finalizeCalls++;
    lastRoomResult = result;
    _throwNextError();
    return '${result.startDate}_${result.endDateExclusive}_room_v1';
  }

  @override
  Future<String> finalizeUtilityBillingBatch({
    required String ownerId,
    required UtilityBillingResult result,
  }) async {
    finalizeUtilityBatchCalls++;
    lastUtilityResult = result;
    _throwNextError();
    final billingBatchId = 'utility-batch-$finalizeUtilityBatchCalls';
    final createdAt = result.issuedOn.value;
    utilityBatches = [
      UtilityBillingBatch(
        billingBatchId: billingBatchId,
        billingBatchReference: 'UB-TEST-$finalizeUtilityBatchCalls',
        status: UtilityBillingBatchStatus.finalized,
        issuedOn: result.issuedOn,
        electricityBatchId: result.electricityBatchId,
        electricityBatchReference: result.electricityBatchReference,
        electricityMeasurementStart: result.electricityMeasurementStart,
        electricityMeasurementEnd: result.electricityMeasurementEnd,
        electricityRateMicropesosPerKwh: result.electricityRateMicropesosPerKwh,
        sourceReadingIds: result.sourceReadingIds,
        waterBatchId: result.waterBatchId,
        waterBatchReference: result.waterBatchReference,
        waterPeriodStart: result.waterPeriodStart,
        waterPeriodEndExclusive: result.waterPeriodEndExclusive,
        waterReceiptDate: result.waterReceiptDate,
        waterMethod: result.waterMethod,
        waterSummerBasis: result.waterSummerBasis,
        waterReferenceElectricityBatchId:
            result.waterReferenceElectricityBatchId,
        waterReferenceElectricityBatchReference:
            result.waterReferenceElectricityBatchReference,
        associationMismatchConfirmed: result.associationMismatchConfirmed,
        electricityTotalCentavos: result.electricityTotalCentavos,
        waterTotalCentavos: result.waterTotalCentavos,
        adjustmentTotalCentavos: result.adjustmentTotalCentavos,
        totalBilledCentavos: result.totalBilledCentavos,
        totalUnallocatedCentavos: result.totalUnallocatedCentavos,
        statements: result.statements,
        warnings: result.warnings,
        createdAt: createdAt,
        voidReason: null,
        voidedAt: null,
      ),
    ];
    utilityRoomAccounts = result.statements
        .map(
          (statement) => UtilityRoomBillAccount(
            accountId: '${billingBatchId}_${statement.roomId}',
            billingBatchId: billingBatchId,
            roomId: statement.roomId,
            roomName: statement.roomName,
            totalChargesCentavos: statement.totalCentavos,
            totalPaidCentavos: 0,
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        )
        .toList(growable: false);
    return billingBatchId;
  }

  @override
  Future<void> voidCycle({
    required String ownerId,
    required String billingCycleId,
    required String reason,
  }) async {
    voidCalls++;
    _throwNextError();
  }

  @override
  Future<void> voidRoomCycle({
    required String ownerId,
    required String billingCycleId,
    required String reason,
  }) async {
    voidCalls++;
    _throwNextError();
  }

  @override
  Future<String> recordPayment({
    required String ownerId,
    required String billingCycleId,
    required String boarderId,
    required int amountCentavos,
    required BusinessDate paymentDate,
    required PaymentMethod method,
    String? notes,
  }) async {
    paymentCalls++;
    _throwNextError();
    return 'payment-$paymentCalls';
  }

  @override
  Future<String> recordRoomPayment({
    required String ownerId,
    required String billingCycleId,
    required String roomId,
    required int amountCentavos,
    required BusinessDate paymentDate,
    required PaymentMethod method,
    String? notes,
  }) async {
    paymentCalls++;
    _throwNextError();
    return 'room-payment-$paymentCalls';
  }

  @override
  Future<String> recordUtilityRoomPayment({
    required String ownerId,
    required String billingBatchId,
    required String roomId,
    required int amountCentavos,
    required BusinessDate paymentDate,
    required PaymentMethod method,
    String? notes,
  }) async {
    paymentCalls++;
    lastPaymentBillingBatchId = billingBatchId;
    lastPaymentRoomId = roomId;
    lastPaymentAmountCentavos = amountCentavos;
    _throwNextError();
    return 'utility-room-payment-$paymentCalls';
  }
}

class FakeElectricityRepository implements ElectricityRepository {
  List<RoomMeterState> states = [];
  List<ElectricityMeter> meters = [];
  List<MeterReading> readings = [];
  List<MeterReadingCorrection> corrections = [];
  List<ElectricityBillingRecord> records = [];
  List<ElectricityReadingBatch> batches = [];
  ElectricityRepositoryException? nextError;
  int initializeCalls = 0;
  int recordReadingCalls = 0;
  int transitionCalls = 0;
  int correctReadingCalls = 0;
  int recordSnapshotCalls = 0;
  int createBatchCalls = 0;
  int updateBatchCalls = 0;
  int finalizeBatchCalls = 0;
  int voidBatchCalls = 0;
  String? lastRoomId;
  int? lastReadingWh;
  ElectricityCalculationResult? lastResult;

  void _throwNextError() {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  @override
  Stream<List<RoomMeterState>> watchRoomMeterStates(String ownerId) =>
      Stream.value(states);

  @override
  Stream<List<ElectricityMeter>> watchMeters(String ownerId) =>
      Stream.value(meters);

  @override
  Stream<List<MeterReading>> watchReadings(String ownerId) =>
      Stream.value(readings);

  @override
  Stream<List<MeterReadingCorrection>> watchReadingCorrections(
    String ownerId,
  ) => Stream.value(corrections);

  @override
  Stream<List<ElectricityBillingRecord>> watchBillingRecords(String ownerId) =>
      Stream.value(records);

  @override
  Stream<List<ElectricityReadingBatch>> watchReadingBatches(String ownerId) =>
      Stream.value(batches);

  @override
  Future<void> initializeMeter({
    required String ownerId,
    required String roomId,
    required BusinessDate openingDate,
    required int openingReadingWh,
    String? note,
  }) async {
    initializeCalls++;
    lastRoomId = roomId;
    lastReadingWh = openingReadingWh;
    _throwNextError();
  }

  @override
  Future<void> recordReading({
    required String ownerId,
    required String roomId,
    required BusinessDate readingDate,
    required int readingWh,
    MeterReadingKind kind = MeterReadingKind.regular,
    String? note,
  }) async {
    recordReadingCalls++;
    lastRoomId = roomId;
    lastReadingWh = readingWh;
    _throwNextError();
  }

  @override
  Future<void> transitionMeter({
    required String ownerId,
    required String roomId,
    required BusinessDate transitionDate,
    required int closingReadingWh,
    required int newOpeningReadingWh,
    required ElectricityMeterStartKind startKind,
    required String reason,
  }) async {
    transitionCalls++;
    lastRoomId = roomId;
    lastReadingWh = newOpeningReadingWh;
    _throwNextError();
  }

  @override
  Future<void> correctLatestReading({
    required String ownerId,
    required String roomId,
    required String readingId,
    required BusinessDate expectedReadingDate,
    required int expectedReadingWh,
    required int expectedCorrectionCount,
    required BusinessDate correctedReadingDate,
    required int correctedReadingWh,
    required String reason,
  }) async {
    correctReadingCalls++;
    lastRoomId = roomId;
    lastReadingWh = correctedReadingWh;
    _throwNextError();
  }

  @override
  Future<void> insertHistoricalReading({
    required String ownerId,
    required String roomId,
    required String meterId,
    required String predecessorReadingId,
    required BusinessDate expectedPredecessorDate,
    required int expectedPredecessorWh,
    required String successorReadingId,
    required BusinessDate expectedSuccessorDate,
    required int expectedSuccessorWh,
    required BusinessDate readingDate,
    required int readingWh,
    required String reason,
  }) async {
    lastRoomId = roomId;
    lastReadingWh = readingWh;
    _throwNextError();
  }

  @override
  Future<String> recordBillingSnapshot({
    required String ownerId,
    required ElectricityCalculationResult result,
    bool roomBillingSource = false,
  }) async {
    recordSnapshotCalls++;
    lastResult = result;
    _throwNextError();
    return roomBillingSource
        ? '${result.startDate}_${result.endDateExclusive}_roomV2'
        : '${result.startDate}_${result.endDateExclusive}';
  }

  @override
  Future<String> createReadingBatchDraft({
    required String ownerId,
    required BusinessDate effectiveDate,
    required DateTime effectiveAt,
    required int rateMicropesosPerKwh,
    required List<ElectricityBatchRoomSource> rooms,
  }) async {
    createBatchCalls++;
    _throwNextError();
    return 'batch-$createBatchCalls';
  }

  @override
  Future<void> updateReadingBatchDraft({
    required String ownerId,
    required String batchId,
    required int expectedVersion,
    required BusinessDate effectiveDate,
    required DateTime effectiveAt,
    required int rateMicropesosPerKwh,
    required List<ElectricityBatchEntryDraft> entries,
  }) async {
    updateBatchCalls++;
    _throwNextError();
  }

  @override
  Future<void> finalizeReadingBatch({
    required String ownerId,
    required String batchId,
  }) async {
    finalizeBatchCalls++;
    _throwNextError();
  }

  @override
  Future<void> voidReadingBatch({
    required String ownerId,
    required String batchId,
    required String reason,
  }) async {
    voidBatchCalls++;
    _throwNextError();
  }
}

class FakeRentRepository implements RentRepository {
  RentSettings settings = RentSettings.defaults();
  List<RentBillingRecord> records = [];
  List<RentAgreement> agreements = [];
  List<RentCycle> cycles = [];
  List<RentCycleControl> controls = [];
  List<RentPayment> payments = [];
  List<RentExtraStayResolution> resolutions = [];
  RentRepositoryException? nextError;
  int saveSettingsCalls = 0;
  int recordSnapshotCalls = 0;
  int resolveExtraStayCalls = 0;
  RentSettings? lastSettings;
  RentCalculationResult? lastResult;
  ExtraStayDecision? lastExtraStayDecision;
  int? lastExtraStayAmountCentavos;
  String? lastExtraStayNote;
  BusinessDate? lastExtraStayMoveOutDate;

  void _throwNextError() {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  @override
  Stream<RentSettings> watchSettings(String ownerId) => Stream.value(settings);

  @override
  Stream<List<RentBillingRecord>> watchBillingRecords(String ownerId) =>
      Stream.value(records);

  @override
  Stream<List<RentAgreement>> watchAgreements(String ownerId) =>
      Stream.value(agreements);

  @override
  Stream<List<RentCycle>> watchCycles(String ownerId) => Stream.value(cycles);

  @override
  Stream<List<RentCycleControl>> watchCycleControls(String ownerId) =>
      Stream.value(controls);

  @override
  Stream<List<RentPayment>> watchPayments(String ownerId) =>
      Stream.value(payments);

  @override
  Stream<List<RentExtraStayResolution>> watchExtraStayResolutions(
    String ownerId,
  ) => Stream.value(resolutions);

  @override
  Future<void> saveSettings({
    required String ownerId,
    required RentSettings settings,
  }) async {
    saveSettingsCalls++;
    lastSettings = settings;
    _throwNextError();
  }

  @override
  Future<String> recordBillingSnapshot({
    required String ownerId,
    required RentCalculationResult result,
    bool roomBillingSource = false,
  }) async {
    recordSnapshotCalls++;
    lastResult = result;
    _throwNextError();
    return roomBillingSource
        ? '${result.startDate}_${result.endDateExclusive}_roomV2'
        : '${result.startDate}_${result.endDateExclusive}';
  }

  @override
  Future<String> createAgreement({
    required String ownerId,
    required String occupancyId,
    required int monthlyRentCentavos,
  }) async {
    _throwNextError();
    return occupancyId;
  }

  @override
  Future<int> createDueCycles({
    required String ownerId,
    required RentAgreement agreement,
    required BusinessDate throughDate,
  }) async {
    _throwNextError();
    return 0;
  }

  @override
  Future<String> recordPayment({
    required String ownerId,
    required String cycleId,
    required int expectedPaidCentavos,
    required int amountCentavos,
    required BusinessDate receivedOn,
    String? note,
  }) async {
    _throwNextError();
    return 'payment-1';
  }

  @override
  Future<String> resolveExtraStay({
    required String ownerId,
    required RentAgreement agreement,
    required BusinessDate moveOutDate,
    required ExtraStayDecision decision,
    required int amountCentavos,
    required String note,
  }) async {
    resolveExtraStayCalls++;
    lastExtraStayDecision = decision;
    lastExtraStayAmountCentavos = amountCentavos;
    lastExtraStayNote = note;
    lastExtraStayMoveOutDate = moveOutDate;
    _throwNextError();
    return agreement.occupancyId;
  }
}

class FakeWaterRepository implements WaterRepository {
  WaterSettings settings = WaterSettings.defaults();
  List<WaterBillingRecord> records = [];
  List<WaterBillingBatch> batches = [];
  WaterRepositoryException? nextError;
  int saveSettingsCalls = 0;
  int recordSnapshotCalls = 0;
  int createWaterBatchCalls = 0;
  int updateWaterBatchCalls = 0;
  int finalizeWaterBatchCalls = 0;
  int voidWaterBatchCalls = 0;
  WaterSettings? lastSettings;
  WaterCalculationResult? lastResult;

  void _throwNextError() {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  @override
  Stream<WaterSettings> watchSettings(String ownerId) => Stream.value(settings);

  @override
  Stream<List<WaterBillingRecord>> watchBillingRecords(String ownerId) =>
      Stream.value(records);

  @override
  Stream<List<WaterBillingBatch>> watchBillingBatches(String ownerId) =>
      Stream.value(batches);

  @override
  Future<void> saveSettings({
    required String ownerId,
    required WaterSettings settings,
  }) async {
    saveSettingsCalls++;
    lastSettings = settings;
    _throwNextError();
  }

  @override
  Future<String> recordBillingSnapshot({
    required String ownerId,
    required WaterCalculationResult result,
  }) async {
    recordSnapshotCalls++;
    lastResult = result;
    _throwNextError();
    return '${result.startDate}_${result.endDateExclusive}';
  }

  @override
  Future<String> createBillingBatchDraft({
    required String ownerId,
    required BusinessDate receiptDate,
    required WaterCalculationResult result,
    required String? electricityBatchId,
    required bool referencePeriodMismatchConfirmed,
    required String? referenceExplanation,
    required String? notes,
  }) async {
    createWaterBatchCalls++;
    lastResult = result;
    _throwNextError();
    return 'water-batch-$createWaterBatchCalls';
  }

  @override
  Future<void> updateBillingBatchDraft({
    required String ownerId,
    required String batchId,
    required int expectedVersion,
    required BusinessDate receiptDate,
    required WaterCalculationResult result,
    required String? electricityBatchId,
    required bool referencePeriodMismatchConfirmed,
    required String? referenceExplanation,
    required String? notes,
  }) async {
    updateWaterBatchCalls++;
    lastResult = result;
    _throwNextError();
  }

  @override
  Future<void> finalizeBillingBatch({
    required String ownerId,
    required String batchId,
    int? expectedVersion,
  }) async {
    finalizeWaterBatchCalls++;
    _throwNextError();
  }

  @override
  Future<void> voidBillingBatch({
    required String ownerId,
    required String batchId,
    required String reason,
  }) async {
    voidWaterBatchCalls++;
    _throwNextError();
  }
}

const unverifiedUser = AppUser(
  id: 'owner-1',
  email: 'owner@example.com',
  displayName: 'Maria Santos',
  isEmailVerified: false,
);

const verifiedUser = AppUser(
  id: 'owner-1',
  email: 'owner@example.com',
  displayName: 'Maria Santos',
  isEmailVerified: true,
);

const ownerWorkspace = OwnerWorkspace(
  ownerUid: 'owner-1',
  ownerName: 'Maria Santos',
  ownerEmail: 'owner@example.com',
  houseName: 'Mariano Boarding House',
);
