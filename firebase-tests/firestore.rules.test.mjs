import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {
  after,
  before,
  beforeEach,
  describe,
  it,
} from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const rules = fs.readFileSync(
  path.resolve(currentDirectory, '..', 'firestore.rules'),
  'utf8',
);

const projectId = 'demo-boarding-house-manager';
const aliceUid = 'alice-owner';
const aliceEmail = 'alice@example.com';
const bobUid = 'bob-owner';
const bobEmail = 'bob@example.com';

let testEnvironment;

function authenticatedDb(uid, email, emailVerified = true) {
  return testEnvironment.authenticatedContext(uid, {
    email,
    email_verified: emailVerified,
  }).firestore();
}

function profileData(email, overrides = {}) {
  return {
    email,
    displayName: 'Boarding House Owner',
    primaryHouseId: 'primary',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function houseData(uid, overrides = {}) {
  return {
    ownerUid: uid,
    name: 'Mariano Boarding House',
    currencyCode: 'PHP',
    businessTimeZone: 'Asia/Manila',
    schemaVersion: 1,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function profileRef(db, uid) {
  return doc(db, 'users', uid);
}

function primaryHouseRef(db, uid) {
  return doc(db, 'owners', uid, 'boardingHouses', 'primary');
}

function houseRef(db, uid, houseId) {
  return doc(db, 'owners', uid, 'boardingHouses', houseId);
}

function roomRef(db, uid, roomId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'rooms',
    roomId,
  );
}

function boarderRef(db, uid, boarderId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'boarders',
    boarderId,
  );
}

function occupancyRef(db, uid, occupancyId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'occupancies',
    occupancyId,
  );
}

function roomMeterStateRef(db, uid, roomId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'roomMeterStates',
    roomId,
  );
}

function electricityMeterRef(db, uid, meterId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'electricityMeters',
    meterId,
  );
}

function meterReadingRef(db, uid, readingId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'meterReadings',
    readingId,
  );
}

function meterReadingCorrectionRef(db, uid, correctionId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'meterReadingCorrections',
    correctionId,
  );
}

function meterReadingInsertionRef(db, uid, insertionId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'meterReadingInsertions',
    insertionId,
  );
}

function electricityBillingRecordRef(db, uid, recordId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'electricityBillingRecords',
    recordId,
  );
}

function electricityReadingBatchRef(db, uid, batchId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'electricityReadingBatches',
    batchId,
  );
}

function electricityBatchVoidRef(db, uid, voidId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'electricityBatchVoids',
    voidId,
  );
}

function electricityBatchReadingLinkRef(db, uid, linkId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'electricityBatchReadingLinks',
    linkId,
  );
}

function waterSettingsRef(db, uid) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'waterSettings',
    'config',
  );
}

function waterBillingRecordRef(db, uid, recordId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'waterBillingRecords',
    recordId,
  );
}

function waterBillingBatchRef(db, uid, batchId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'waterBillingBatches',
    batchId,
  );
}

function waterBillingBatchVoidRef(db, uid, voidId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'waterBillingBatchVoids',
    voidId,
  );
}

function utilityBillingBatchRef(db, uid, billingBatchId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'utilityBillingBatches',
    billingBatchId,
  );
}

function utilityRoomBillAccountRef(db, uid, accountId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'utilityRoomBillAccounts',
    accountId,
  );
}

function utilityRoomPaymentRef(db, uid, paymentId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'utilityRoomPayments',
    paymentId,
  );
}

function rentSettingsRef(db, uid) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'rentSettings',
    'config',
  );
}

function rentBillingRecordRef(db, uid, recordId) {
  return doc(
    db,
    'owners',
    uid,
    'boardingHouses',
    'primary',
    'rentBillingRecords',
    recordId,
  );
}

function rentAgreementRef(db, uid, agreementId) {
  return doc(db, 'owners', uid, 'boardingHouses', 'primary', 'rentAgreements', agreementId);
}

function rentCycleRef(db, uid, cycleId) {
  return doc(db, 'owners', uid, 'boardingHouses', 'primary', 'rentCycles', cycleId);
}

function rentCycleControlRef(db, uid, cycleId) {
  return doc(db, 'owners', uid, 'boardingHouses', 'primary', 'rentCycleControls', cycleId);
}

function rentPaymentRef(db, uid, paymentId) {
  return doc(db, 'owners', uid, 'boardingHouses', 'primary', 'rentPayments', paymentId);
}

function rentExtraStayResolutionRef(db, uid, resolutionId) {
  return doc(db, 'owners', uid, 'boardingHouses', 'primary', 'rentExtraStayResolutions', resolutionId);
}

function billingPeriodRef(db, uid, periodId) {
  return doc(db, 'owners', uid, 'boardingHouses', 'primary', 'billingPeriods', periodId);
}

function monthlyBillingCycleRef(db, uid, cycleId) {
  return doc(db, 'owners', uid, 'boardingHouses', 'primary', 'monthlyBillingCycles', cycleId);
}

function billingCycleControlRef(db, uid, cycleId) {
  return doc(db, 'owners', uid, 'boardingHouses', 'primary', 'billingCycleControls', cycleId);
}

function boarderBillAccountRef(db, uid, accountId) {
  return doc(db, 'owners', uid, 'boardingHouses', 'primary', 'boarderBillAccounts', accountId);
}

function paymentRef(db, uid, paymentId) {
  return doc(db, 'owners', uid, 'boardingHouses', 'primary', 'payments', paymentId);
}

function roomBillingPeriodRef(db, uid, periodId) {
  return doc(db, 'owners', uid, 'boardingHouses', 'primary', 'roomBillingPeriods', periodId);
}

function roomBillingCycleRef(db, uid, cycleId) {
  return doc(db, 'owners', uid, 'boardingHouses', 'primary', 'roomBillingCycles', cycleId);
}

function roomBillingControlRef(db, uid, cycleId) {
  return doc(db, 'owners', uid, 'boardingHouses', 'primary', 'roomBillingControls', cycleId);
}

function roomBillAccountRef(db, uid, accountId) {
  return doc(db, 'owners', uid, 'boardingHouses', 'primary', 'roomBillAccounts', accountId);
}

function roomPaymentRef(db, uid, paymentId) {
  return doc(db, 'owners', uid, 'boardingHouses', 'primary', 'roomPayments', paymentId);
}

function businessDate(isoDate) {
  return Timestamp.fromDate(new Date(`${isoDate}T00:00:00.000Z`));
}

function manilaDateFromNow(dayOffset = 0) {
  const nowInManila = new Date(Date.now() + 8 * 60 * 60 * 1000);
  const date = new Date(
    Date.UTC(
      nowInManila.getUTCFullYear(),
      nowInManila.getUTCMonth(),
      nowInManila.getUTCDate() + dayOffset,
    ),
  );
  return Timestamp.fromDate(date);
}

function roomData(roomId, overrides = {}) {
  return {
    roomId,
    roomName: `Room ${roomId}`,
    description: '',
    status: 'active',
    defaultMonthlyRentCentavos: 350000,
    activeOccupancyCount: 0,
    lastOccupancyMutationId: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function boarderData(boarderId, occupancyId, roomId, moveInDate, overrides = {}) {
  return {
    boarderId,
    fullName: `Boarder ${boarderId}`,
    contact: null,
    notes: null,
    status: 'active',
    currentOccupancyId: occupancyId,
    currentRoomId: roomId,
    currentMoveInDate: moveInDate,
    lastMoveOutDate: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function occupancyData(occupancyId, boarderId, roomId, moveInDate, overrides = {}) {
  return {
    occupancyId,
    boarderId,
    roomId,
    moveInDate,
    moveOutDate: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function roomMeterStateData(roomId, meterId, overrides = {}) {
  return {
    roomId,
    currentMeterId: meterId,
    lastTransitionId: meterId,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function electricityMeterData(
  meterId,
  roomId,
  openingReadingId,
  startedOn,
  openingReadingWh,
  overrides = {},
) {
  return {
    meterId,
    roomId,
    sequenceNumber: 1,
    status: 'active',
    startedOn,
    endedOn: null,
    startKind: 'initial',
    transitionReason: null,
    previousMeterId: null,
    replacementMeterId: null,
    lastReadingId: openingReadingId,
    lastReadingDate: startedOn,
    lastReadingWh: openingReadingWh,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function meterReadingData(
  readingId,
  meterId,
  roomId,
  sequenceNumber,
  readingDate,
  readingWh,
  overrides = {},
) {
  return {
    readingId,
    meterId,
    roomId,
    sequenceNumber,
    readingDate,
    readingWh,
    kind: 'opening',
    previousReadingId: null,
    previousReadingDate: null,
    previousReadingWh: null,
    consumptionWh: 0,
    note: null,
    billingRecordIds: [],
    correctionCount: 0,
    lastCorrectionId: null,
    lastCorrectedAt: null,
    lastCorrectedBy: null,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function electricityBillingRecordData(recordId, overrides = {}) {
  return {
    recordId,
    startDate: businessDate('2024-01-01'),
    endDateExclusive: businessDate('2024-02-01'),
    rateMicropesosPerKwh: 12000000,
    totalConsumptionWh: 90000,
    totalBaseChargeCentavos: 108000,
    totalAdjustmentCentavos: 0,
    totalChargeCentavos: 108000,
    totalAllocatedCentavos: 108000,
    totalUnallocatedCentavos: 0,
    roomCharges: [],
    sourceReadingIds: ['source-reading'],
    warnings: [],
    createdBy: aliceUid,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function electricityReadingBatchData(batchId, overrides = {}) {
  return {
    batchId,
    batchReference: 'EB-2024-02-01-TEST',
    status: 'draft',
    effectiveDate: businessDate('2024-02-01'),
    effectiveAt: Timestamp.fromDate(new Date('2024-02-01T10:00:00+08:00')),
    rateMicropesosPerKwh: 12000000,
    entries: [{ roomId: 'room-a', roomName: 'Room A' }],
    roomCount: 1,
    pendingCount: 1,
    recordedCount: 0,
    excludedCount: 0,
    totalConsumptionWh: 0,
    totalChargeCentavos: 0,
    version: 1,
    lastLinkId: null,
    createdBy: aliceUid,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    finalizedAt: null,
    usedAt: null,
    voidReason: null,
    voidedAt: null,
    ...overrides,
  };
}

function electricityBatchEntryData(overrides = {}) {
  return {
    roomId: 'room-a',
    roomName: 'Room A',
    meterId: 'meter-a',
    sequenceNumber: 1,
    previousReadingId: 'reading-open',
    previousReadingDate: businessDate('2024-01-01'),
    previousReadingWh: 100000,
    targetReadingId: 'reading-batch',
    status: 'pending',
    currentReadingWh: 110000,
    actualReadAt: Timestamp.fromDate(new Date('2024-02-01T10:00:00+08:00')),
    readingId: null,
    consumptionWh: 10000,
    chargeCentavos: 12000,
    exclusionReason: null,
    ...overrides,
  };
}

function electricityBatchReadingLinkData(batchId, overrides = {}) {
  return {
    linkId: 'reading-batch',
    batchId,
    batchReference: 'EB-2024-02-01-TEST',
    readingId: 'reading-batch',
    roomId: 'room-a',
    meterId: 'meter-a',
    readingDate: businessDate('2024-02-01'),
    readingWh: 110000,
    consumptionWh: 10000,
    chargeCentavos: 12000,
    createdBy: aliceUid,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function electricityBatchVoidData(batchId, overrides = {}) {
  return {
    voidId: batchId,
    batchId,
    batchReference: 'EB-2024-02-01-TEST',
    reason: 'Duplicate batch entered by mistake',
    voidedBy: aliceUid,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function waterSettingsData(overrides = {}) {
  return {
    settingsId: 'config',
    defaultMethod: 'personDays',
    summerBasis: 'roomElectricityCharge',
    summerMonths: [3, 4, 5],
    allowManualMethodOverride: true,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function waterBillingRecordData(recordId, overrides = {}) {
  return {
    recordId,
    startDate: businessDate('2024-01-01'),
    endDateExclusive: businessDate('2024-02-01'),
    waterBillCentavos: 120000,
    method: 'personDays',
    summerBasis: 'roomElectricityCharge',
    electricityRecordId: null,
    totalPersonDays: 45,
    totalElectricityBasis: 0,
    totalAllocatedCentavos: 120000,
    totalUnallocatedCentavos: 0,
    roomAllocations: [],
    boarderShares: [],
    warnings: [],
    createdBy: aliceUid,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function waterBillingBatchData(batchId, overrides = {}) {
  return {
    batchId,
    batchReference: 'WB-2024-02-TEST',
    status: 'draft',
    startDate: businessDate('2024-01-01'),
    endDateExclusive: businessDate('2024-02-01'),
    receiptDate: businessDate('2024-02-05'),
    waterBillCentavos: 120000,
    method: 'personDays',
    summerBasis: 'roomElectricityCharge',
    electricityBatchId: null,
    electricityBatchReference: null,
    electricityMeasurementStart: null,
    electricityMeasurementEnd: null,
    referencePeriodMismatchConfirmed: false,
    referenceExplanation: null,
    notes: null,
    totalPersonDays: 45,
    totalElectricityBasis: 0,
    totalAllocatedCentavos: 120000,
    totalUnallocatedCentavos: 0,
    roomAllocations: [],
    boarderShares: [],
    warnings: [],
    version: 1,
    createdBy: aliceUid,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    finalizedAt: null,
    usedAt: null,
    voidReason: null,
    voidedAt: null,
    ...overrides,
  };
}

function waterBillingBatchVoidData(batchId, overrides = {}) {
  return {
    voidId: batchId,
    batchId,
    batchReference: 'WB-2024-02-TEST',
    reason: 'Duplicate provider statement',
    voidedBy: aliceUid,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function utilityBillingBatchData(billingBatchId, overrides = {}) {
  return {
    billingBatchId,
    billingBatchReference: 'UB-2024-02-TEST',
    status: 'finalized',
    issuedOn: businessDate('2024-02-05'),
    electricityBatchId: 'electricity-source',
    electricityBatchReference: 'EB-2024-02-01-TEST',
    electricityMeasurementStart: businessDate('2024-01-01'),
    electricityMeasurementEnd: businessDate('2024-02-01'),
    electricityRateMicropesosPerKwh: 12000000,
    sourceReadingIds: ['reading-batch'],
    waterBatchId: 'water-source',
    waterBatchReference: 'WB-2024-02-TEST',
    waterPeriodStart: businessDate('2024-01-01'),
    waterPeriodEndExclusive: businessDate('2024-02-01'),
    waterReceiptDate: businessDate('2024-02-05'),
    waterMethod: 'personDays',
    waterSummerBasis: 'roomElectricityCharge',
    waterReferenceElectricityBatchId: null,
    waterReferenceElectricityBatchReference: null,
    associationMismatchConfirmed: false,
    electricityTotalCentavos: 12000,
    waterTotalCentavos: 120000,
    adjustmentTotalCentavos: 0,
    totalBilledCentavos: 132000,
    totalUnallocatedCentavos: 0,
    statements: [{
      roomId: 'room-a',
      roomName: 'Room A',
      electricityCentavos: 12000,
      waterCentavos: 120000,
      adjustmentCentavos: 0,
      totalCentavos: 132000,
    }],
    warnings: [],
    createdBy: aliceUid,
    createdAt: serverTimestamp(),
    voidReason: null,
    voidedAt: null,
    ...overrides,
  };
}

function utilityRoomBillAccountData(accountId, billingBatchId, overrides = {}) {
  return {
    accountId,
    billingBatchId,
    roomId: 'room-a',
    roomName: 'Room A',
    totalChargesCentavos: 132000,
    totalPaidCentavos: 0,
    lastPaymentId: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function utilityRoomPaymentData(paymentId, billingBatchId, overrides = {}) {
  return {
    paymentId,
    billingBatchId,
    accountId: `${billingBatchId}_room-a`,
    roomId: 'room-a',
    roomName: 'Room A',
    amountCentavos: 50000,
    paymentDate: businessDate('2024-02-10'),
    method: 'cash',
    notes: 'Partial utility payment',
    createdBy: aliceUid,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function rentSettingsData(overrides = {}) {
  return {
    settingsId: 'config',
    mode: 'perBoarder',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function rentBillingRecordData(recordId, overrides = {}) {
  return {
    recordId,
    startDate: businessDate('2024-01-01'),
    endDateExclusive: businessDate('2024-02-01'),
    mode: 'perBoarder',
    periodDays: 31,
    totalRentCentavos: 310000,
    totalAdjustmentCentavos: -10000,
    grandTotalCentavos: 300000,
    roomAllocations: [],
    boarderCharges: [],
    adjustments: [],
    warnings: [],
    createdBy: aliceUid,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function rentAgreementData(agreementId, overrides = {}) {
  return {
    agreementId,
    occupancyId: agreementId,
    boarderId: 'boarder-rent',
    boarderName: 'Boarder boarder-rent',
    roomId: 'room-rent',
    roomName: 'Room room-rent',
    startDate: businessDate('2024-06-10'),
    anchorDay: 10,
    monthlyRentCentavos: 200000,
    createdBy: aliceUid,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function rentCycleData(cycleId, overrides = {}) {
  return {
    cycleId,
    agreementId: 'occupancy-rent',
    occupancyId: 'occupancy-rent',
    boarderId: 'boarder-rent',
    boarderName: 'Boarder boarder-rent',
    roomId: 'room-rent',
    roomName: 'Room room-rent',
    kind: 'monthly',
    cycleNumber: 1,
    coverageStart: businessDate('2024-06-10'),
    coverageEndExclusive: businessDate('2024-07-10'),
    dueDate: businessDate('2024-07-10'),
    amountCentavos: 200000,
    createdBy: aliceUid,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function rentCycleControlData(cycleId, overrides = {}) {
  return {
    cycleId,
    totalPaidCentavos: 0,
    lastPaymentId: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function rentPaymentData(paymentId, cycleId, overrides = {}) {
  return {
    paymentId,
    cycleId,
    agreementId: 'occupancy-rent',
    amountCentavos: 100000,
    note: 'First partial payment',
    receivedOn: businessDate('2024-07-10'),
    createdBy: aliceUid,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function billingPeriodData(periodId, cycleId, overrides = {}) {
  return {
    periodId,
    startDate: businessDate('2024-01-01'),
    endDateExclusive: businessDate('2024-02-01'),
    activeCycleId: cycleId,
    latestCycleId: cycleId,
    latestVersion: 1,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function monthlyBillingCycleData(cycleId, periodId, overrides = {}) {
  return {
    billingCycleId: cycleId,
    periodId,
    version: 1,
    replacesCycleId: null,
    startDate: businessDate('2024-01-01'),
    endDateExclusive: businessDate('2024-02-01'),
    electricityRecordId: 'electricity-month',
    waterRecordId: 'water-month',
    rentRecordId: 'rent-month',
    electricityTotalCentavos: 108000,
    waterTotalCentavos: 120000,
    rentTotalCentavos: 310000,
    rentAdjustmentCentavos: -10000,
    totalBilledCentavos: 528000,
    totalUnallocatedCentavos: 0,
    statements: [],
    warnings: [],
    createdBy: aliceUid,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function billingCycleControlData(cycleId, overrides = {}) {
  return {
    billingCycleId: cycleId,
    state: 'active',
    totalBilledCentavos: 528000,
    totalPaidCentavos: 0,
    outstandingCentavos: 528000,
    voidReason: null,
    voidedAt: null,
    reissuedAsCycleId: null,
    lastPaymentId: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function boarderBillAccountData(accountId, cycleId, boarderId, overrides = {}) {
  return {
    accountId,
    billingCycleId: cycleId,
    boarderId,
    boarderName: 'Boarder A',
    totalChargesCentavos: 528000,
    previousBalanceCentavos: 0,
    totalPaidCentavos: 0,
    lastPaymentId: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function paymentData(paymentId, cycleId, accountId, overrides = {}) {
  return {
    paymentId,
    billingCycleId: cycleId,
    accountId,
    boarderId: 'boarder-a',
    boarderName: 'Boarder A',
    amountCentavos: 100000,
    paymentDate: businessDate('2024-02-01'),
    method: 'cash',
    notes: null,
    createdBy: aliceUid,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function roomBillingCycleData(cycleId, periodId, overrides = {}) {
  return {
    billingCycleId: cycleId,
    periodId,
    billingModel: 'roomV2',
    version: 1,
    replacesCycleId: null,
    startDate: businessDate('2024-01-01'),
    endDateExclusive: businessDate('2024-02-01'),
    electricityRecordId: 'electricity-room-month',
    waterRecordId: 'water-room-month',
    rentRecordId: 'not-applicable',
    electricityTotalCentavos: 108000,
    waterTotalCentavos: 120000,
    rentTotalCentavos: 0,
    adjustmentTotalCentavos: 0,
    totalBilledCentavos: 228000,
    totalUnallocatedCentavos: 0,
    statements: [{ roomId: 'room-a', currentChargesCentavos: 228000 }],
    warnings: [],
    createdBy: aliceUid,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function roomBillAccountData(accountId, cycleId, overrides = {}) {
  return {
    accountId,
    billingCycleId: cycleId,
    roomId: 'room-a',
    roomName: 'Room A',
    totalChargesCentavos: 228000,
    totalPaidCentavos: 0,
    lastPaymentId: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function roomPaymentData(paymentId, cycleId, accountId, overrides = {}) {
  return {
    paymentId,
    billingCycleId: cycleId,
    accountId,
    roomId: 'room-a',
    roomName: 'Room A',
    amountCentavos: 100000,
    paymentDate: businessDate('2024-02-01'),
    method: 'cash',
    notes: null,
    createdBy: aliceUid,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

async function createRoom(db, uid, roomId, overrides = {}) {
  return setDoc(roomRef(db, uid, roomId), roomData(roomId, overrides));
}

async function createMonthlySources(db, uid) {
  await setDoc(
    electricityBillingRecordRef(db, uid, 'electricity-month'),
    electricityBillingRecordData('electricity-month'),
  );
  await setDoc(
    waterBillingRecordRef(db, uid, 'water-month'),
    waterBillingRecordData('water-month'),
  );
  await setDoc(
    rentBillingRecordRef(db, uid, 'rent-month'),
    rentBillingRecordData('rent-month'),
  );
}

async function createMonthlyCycle(
  db,
  uid,
  {
    periodId = '2024-01-01_2024-02-01',
    cycleId = '2024-01-01_2024-02-01_v1',
  } = {},
) {
  const batch = writeBatch(db);
  batch.set(
    billingPeriodRef(db, uid, periodId),
    billingPeriodData(periodId, cycleId),
  );
  batch.set(
    monthlyBillingCycleRef(db, uid, cycleId),
    monthlyBillingCycleData(cycleId, periodId),
  );
  batch.set(
    billingCycleControlRef(db, uid, cycleId),
    billingCycleControlData(cycleId),
  );
  const accountId = `${cycleId}_boarder-a`;
  batch.set(
    boarderBillAccountRef(db, uid, accountId),
    boarderBillAccountData(accountId, cycleId, 'boarder-a'),
  );
  return batch.commit();
}

async function createRoomMonthlySources(db, uid) {
  await setDoc(
    electricityBillingRecordRef(db, uid, 'electricity-room-month'),
    electricityBillingRecordData('electricity-room-month'),
  );
  await setDoc(
    waterBillingRecordRef(db, uid, 'water-room-month'),
    waterBillingRecordData('water-room-month', {
      method: 'roomDays',
      totalPersonDays: 31,
      boarderShares: [],
    }),
  );
}

async function createRoomMonthlyCycle(db, uid) {
  const periodId = '2024-01-01_2024-02-01';
  const cycleId = `${periodId}_room_v1`;
  const accountId = `${cycleId}_room-a`;
  const batch = writeBatch(db);
  batch.set(
    roomBillingPeriodRef(db, uid, periodId),
    billingPeriodData(periodId, cycleId),
  );
  batch.set(
    roomBillingCycleRef(db, uid, cycleId),
    roomBillingCycleData(cycleId, periodId),
  );
  batch.set(
    roomBillingControlRef(db, uid, cycleId),
    billingCycleControlData(cycleId, {
      totalBilledCentavos: 228000,
      outstandingCentavos: 228000,
    }),
  );
  batch.set(
    roomBillAccountRef(db, uid, accountId),
    roomBillAccountData(accountId, cycleId),
  );
  await batch.commit();
  return { cycleId, accountId };
}

async function createAssignedBoarder(
  db,
  uid,
  {
    boarderId,
    occupancyId,
    roomId,
    moveInDate,
    previousRoomCount = 0,
  },
) {
  const batch = writeBatch(db);
  batch.set(
    boarderRef(db, uid, boarderId),
    boarderData(boarderId, occupancyId, roomId, moveInDate),
  );
  batch.set(
    occupancyRef(db, uid, occupancyId),
    occupancyData(occupancyId, boarderId, roomId, moveInDate),
  );
  batch.update(roomRef(db, uid, roomId), {
    activeOccupancyCount: previousRoomCount + 1,
    lastOccupancyMutationId: occupancyId,
    updatedAt: serverTimestamp(),
  });
  return batch.commit();
}

async function installInitialMeter(
  db,
  uid,
  {
    roomId,
    meterId,
    readingId,
    readingDate,
    readingWh,
    stateOverrides = {},
    meterOverrides = {},
    readingOverrides = {},
  },
) {
  const batch = writeBatch(db);
  batch.set(
    roomMeterStateRef(db, uid, roomId),
    roomMeterStateData(roomId, meterId, stateOverrides),
  );
  batch.set(
    electricityMeterRef(db, uid, meterId),
    electricityMeterData(
      meterId,
      roomId,
      readingId,
      readingDate,
      readingWh,
      meterOverrides,
    ),
  );
  batch.set(
    meterReadingRef(db, uid, readingId),
    meterReadingData(
      readingId,
      meterId,
      roomId,
      meterOverrides.sequenceNumber ?? 1,
      readingDate,
      readingWh,
      readingOverrides,
    ),
  );
  return batch.commit();
}

async function appendMeterReading(
  db,
  uid,
  {
    roomId,
    meterId,
    sequenceNumber = 1,
    previousReadingId,
    previousReadingDate,
    previousReadingWh,
    readingId,
    readingDate,
    readingWh,
    kind = 'regular',
    note = null,
    readingOverrides = {},
    meterUpdateOverrides = {},
  },
) {
  const batch = writeBatch(db);
  batch.set(
    meterReadingRef(db, uid, readingId),
    meterReadingData(
      readingId,
      meterId,
      roomId,
      sequenceNumber,
      readingDate,
      readingWh,
      {
        kind,
        previousReadingId,
        previousReadingDate,
        previousReadingWh,
        consumptionWh: readingWh - previousReadingWh,
        note,
        ...readingOverrides,
      },
    ),
  );
  batch.update(electricityMeterRef(db, uid, meterId), {
    lastReadingId: readingId,
    lastReadingDate: readingDate,
    lastReadingWh: readingWh,
    updatedAt: serverTimestamp(),
    ...meterUpdateOverrides,
  });
  return batch.commit();
}

async function insertHistoricalMeterReading(
  db,
  uid,
  {
    roomId,
    meterId,
    predecessorReadingId,
    predecessorDate,
    predecessorWh,
    successorReadingId,
    successorDate,
    successorWh,
    insertedReadingId,
    insertedDate,
    insertedWh,
    reason = 'Add missing period boundary',
    insertionOverrides = {},
  },
) {
  const batch = writeBatch(db);
  batch.set(
    meterReadingRef(db, uid, insertedReadingId),
    meterReadingData(
      insertedReadingId,
      meterId,
      roomId,
      1,
      insertedDate,
      insertedWh,
      {
        kind: 'intermediate',
        previousReadingId: predecessorReadingId,
        previousReadingDate: predecessorDate,
        previousReadingWh: predecessorWh,
        consumptionWh: insertedWh - predecessorWh,
        note: reason,
      },
    ),
  );
  batch.update(meterReadingRef(db, uid, successorReadingId), {
    previousReadingId: insertedReadingId,
    previousReadingDate: insertedDate,
    previousReadingWh: insertedWh,
    consumptionWh: successorWh - insertedWh,
  });
  batch.set(meterReadingInsertionRef(db, uid, insertedReadingId), {
    insertionId: insertedReadingId,
    ownerId: uid,
    roomId,
    meterId,
    insertedReadingId,
    predecessorReadingId,
    successorReadingId,
    readingDate: insertedDate,
    readingWh: insertedWh,
    reason,
    createdBy: uid,
    createdAt: serverTimestamp(),
    ...insertionOverrides,
  });
  return batch.commit();
}

async function correctMeterReading(
  db,
  uid,
  {
    roomId,
    meterId,
    readingId,
    sequenceNumber = 1,
    kind,
    beforeDate,
    beforeWh,
    beforeConsumptionWh,
    previousReadingDate = null,
    previousReadingWh = null,
    beforeMeterStartedOn,
    correctedDate,
    correctedWh,
    correctedConsumptionWh,
    correctionId = 'correction-1',
    correctionCount = 0,
    reason = 'Corrected a meter entry typo',
    readingOverrides = {},
    meterOverrides = {},
    correctionOverrides = {},
    includeReading = true,
    includeMeter = true,
    includeAudit = true,
  },
) {
  const batch = writeBatch(db);
  if (includeReading) {
    batch.update(meterReadingRef(db, uid, readingId), {
      readingDate: correctedDate,
      readingWh: correctedWh,
      consumptionWh: correctedConsumptionWh,
      correctionCount: correctionCount + 1,
      lastCorrectionId: correctionId,
      lastCorrectedAt: serverTimestamp(),
      lastCorrectedBy: uid,
      ...readingOverrides,
    });
  }
  if (includeMeter) {
    batch.update(electricityMeterRef(db, uid, meterId), {
      ...(kind === 'opening' ? { startedOn: correctedDate } : {}),
      lastReadingDate: correctedDate,
      lastReadingWh: correctedWh,
      updatedAt: serverTimestamp(),
      ...meterOverrides,
    });
  }
  if (includeAudit) {
    batch.set(meterReadingCorrectionRef(db, uid, correctionId), {
      correctionId,
      ownerId: uid,
      roomId,
      meterId,
      readingId,
      sequenceNumber,
      kind,
      before: {
        readingDate: beforeDate,
        readingWh: beforeWh,
        consumptionWh: beforeConsumptionWh,
        meterStartedOn: beforeMeterStartedOn,
        meterLastReadingDate: beforeDate,
        meterLastReadingWh: beforeWh,
      },
      after: {
        readingDate: correctedDate,
        readingWh: correctedWh,
        consumptionWh: correctedConsumptionWh,
        meterStartedOn:
          kind === 'opening' ? correctedDate : beforeMeterStartedOn,
        meterLastReadingDate: correctedDate,
        meterLastReadingWh: correctedWh,
      },
      reason,
      correctedBy: uid,
      createdAt: serverTimestamp(),
      ...correctionOverrides,
    });
  }
  return batch.commit();
}

async function createElectricityRecordAndLockReading(
  db,
  uid,
  { recordId, readingId },
) {
  const batch = writeBatch(db);
  batch.set(
    electricityBillingRecordRef(db, uid, recordId),
    electricityBillingRecordData(recordId, {
      sourceReadingIds: [readingId],
    }),
  );
  batch.update(meterReadingRef(db, uid, readingId), {
    billingRecordIds: [recordId],
  });
  return batch.commit();
}

async function transitionMeter(
  db,
  uid,
  {
    roomId,
    oldMeterId,
    oldSequenceNumber,
    oldReadingId,
    oldReadingDate,
    oldReadingWh,
    closingReadingId,
    transitionDate,
    closingReadingWh,
    newMeterId,
    openingReadingId,
    openingReadingWh,
    startKind,
    transitionReason,
    stateOverrides = {},
    oldMeterOverrides = {},
    newMeterOverrides = {},
    closingOverrides = {},
    openingOverrides = {},
  },
) {
  const nextSequence = oldSequenceNumber + 1;
  const batch = writeBatch(db);
  batch.set(
    meterReadingRef(db, uid, closingReadingId),
    meterReadingData(
      closingReadingId,
      oldMeterId,
      roomId,
      oldSequenceNumber,
      transitionDate,
      closingReadingWh,
      {
        kind: 'closing',
        previousReadingId: oldReadingId,
        previousReadingDate: oldReadingDate,
        previousReadingWh: oldReadingWh,
        consumptionWh: closingReadingWh - oldReadingWh,
        ...closingOverrides,
      },
    ),
  );
  batch.update(electricityMeterRef(db, uid, oldMeterId), {
    status: 'retired',
    endedOn: transitionDate,
    replacementMeterId: newMeterId,
    lastReadingId: closingReadingId,
    lastReadingDate: transitionDate,
    lastReadingWh: closingReadingWh,
    updatedAt: serverTimestamp(),
    ...oldMeterOverrides,
  });
  batch.set(
    electricityMeterRef(db, uid, newMeterId),
    electricityMeterData(
      newMeterId,
      roomId,
      openingReadingId,
      transitionDate,
      openingReadingWh,
      {
        sequenceNumber: nextSequence,
        startKind,
        transitionReason,
        previousMeterId: oldMeterId,
        ...newMeterOverrides,
      },
    ),
  );
  batch.set(
    meterReadingRef(db, uid, openingReadingId),
    meterReadingData(
      openingReadingId,
      newMeterId,
      roomId,
      nextSequence,
      transitionDate,
      openingReadingWh,
      openingOverrides,
    ),
  );
  batch.update(roomMeterStateRef(db, uid, roomId), {
    currentMeterId: newMeterId,
    lastTransitionId: newMeterId,
    updatedAt: serverTimestamp(),
    ...stateOverrides,
  });
  return batch.commit();
}

async function createOwnerPair(db, uid, email, options = {}) {
  const batch = writeBatch(db);
  batch.set(
    profileRef(db, uid),
    profileData(email, options.profileOverrides),
  );
  batch.set(
    primaryHouseRef(db, uid),
    houseData(uid, options.houseOverrides),
  );
  return batch.commit();
}

async function seedRentOccupancy(uid, { moveOutDate = null } = {}) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const moveInDate = businessDate('2024-06-10');
    const batch = writeBatch(db);
    batch.set(roomRef(db, uid, 'room-rent'), roomData('room-rent'));
    batch.set(
      boarderRef(db, uid, 'boarder-rent'),
      boarderData('boarder-rent', 'occupancy-rent', 'room-rent', moveInDate),
    );
    batch.set(
      occupancyRef(db, uid, 'occupancy-rent'),
      occupancyData(
        'occupancy-rent',
        'boarder-rent',
        'room-rent',
        moveInDate,
        { moveOutDate },
      ),
    );
    await batch.commit();
  });
}

async function createRentCycle(db, uid, cycleId = 'occupancy-rent_1') {
  const batch = writeBatch(db);
  batch.set(rentCycleRef(db, uid, cycleId), rentCycleData(cycleId));
  batch.set(
    rentCycleControlRef(db, uid, cycleId),
    rentCycleControlData(cycleId),
  );
  return batch.commit();
}

async function seedFinalizedUtilitySources(uid = aliceUid) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(
      electricityReadingBatchRef(db, uid, 'electricity-source'),
      electricityReadingBatchData('electricity-source', {
        batchReference: 'EB-2024-02-01-TEST',
        status: 'finalized',
        entries: [electricityBatchEntryData({
          status: 'recorded',
          readingId: 'reading-batch',
        })],
        pendingCount: 0,
        recordedCount: 1,
        totalConsumptionWh: 10000,
        totalChargeCentavos: 12000,
        version: 2,
        finalizedAt: Timestamp.fromDate(new Date('2024-02-01T02:00:00Z')),
        createdAt: Timestamp.fromDate(new Date('2024-01-01T02:00:00Z')),
        updatedAt: Timestamp.fromDate(new Date('2024-02-01T02:00:00Z')),
      }),
    );
    await setDoc(
      waterBillingBatchRef(db, uid, 'water-source'),
      waterBillingBatchData('water-source', {
        batchReference: 'WB-2024-02-TEST',
        status: 'finalized',
        version: 2,
        finalizedAt: Timestamp.fromDate(new Date('2024-02-05T02:00:00Z')),
        createdAt: Timestamp.fromDate(new Date('2024-02-05T02:00:00Z')),
        updatedAt: Timestamp.fromDate(new Date('2024-02-05T02:00:00Z')),
      }),
    );
  });
}

async function createUtilityBill(db, uid, billingBatchId = 'utility-bill-1') {
  const accountId = `${billingBatchId}_room-a`;
  const batch = writeBatch(db);
  batch.set(
    utilityBillingBatchRef(db, uid, billingBatchId),
    utilityBillingBatchData(billingBatchId),
  );
  batch.update(electricityReadingBatchRef(db, uid, 'electricity-source'), {
    status: 'usedInBilling',
    billingBatchId,
    version: 3,
    usedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  batch.update(waterBillingBatchRef(db, uid, 'water-source'), {
    status: 'usedInBilling',
    billingBatchId,
    version: 3,
    usedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  batch.set(
    utilityRoomBillAccountRef(db, uid, accountId),
    utilityRoomBillAccountData(accountId, billingBatchId),
  );
  return batch.commit();
}

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: { rules },
  });
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
});

after(async () => {
  await testEnvironment.cleanup();
});

describe('owner onboarding', () => {
  it('allows a verified owner to create the linked profile and house atomically', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);

    await assertSucceeds(createOwnerPair(db, aliceUid, aliceEmail));

    const [profileSnapshot, houseSnapshot] = await Promise.all([
      assertSucceeds(getDoc(profileRef(db, aliceUid))),
      assertSucceeds(getDoc(primaryHouseRef(db, aliceUid))),
    ]);

    assert.equal(profileSnapshot.data().primaryHouseId, 'primary');
    assert.equal(houseSnapshot.data().ownerUid, aliceUid);
  });

  it('denies creating a profile without its paired house', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);

    await assertFails(
      setDoc(profileRef(db, aliceUid), profileData(aliceEmail)),
    );
  });

  it('denies creating a house without its paired profile', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);

    await assertFails(
      setDoc(primaryHouseRef(db, aliceUid), houseData(aliceUid)),
    );
  });

  it('denies completing onboarding later when only the house already exists', async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await setDoc(primaryHouseRef(adminDb, aliceUid), houseData(aliceUid));
    });
    const db = authenticatedDb(aliceUid, aliceEmail);

    await assertFails(
      setDoc(profileRef(db, aliceUid), profileData(aliceEmail)),
    );
  });

  it('denies completing onboarding later when only the profile already exists', async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await setDoc(profileRef(adminDb, aliceUid), profileData(aliceEmail));
    });
    const db = authenticatedDb(aliceUid, aliceEmail);

    await assertFails(
      setDoc(primaryHouseRef(db, aliceUid), houseData(aliceUid)),
    );
  });

  it('rolls back both documents when either side of onboarding is invalid', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);

    await assertFails(
      createOwnerPair(db, aliceUid, aliceEmail, {
        houseOverrides: { currencyCode: 'USD' },
      }),
    );

    const [profileSnapshot, houseSnapshot] = await Promise.all([
      assertSucceeds(getDoc(profileRef(db, aliceUid))),
      assertSucceeds(getDoc(primaryHouseRef(db, aliceUid))),
    ]);
    assert.equal(profileSnapshot.exists(), false);
    assert.equal(houseSnapshot.exists(), false);
  });

  it('denies onboarding when the email has not been verified', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail, false);

    await assertFails(createOwnerPair(db, aliceUid, aliceEmail));
  });

  it('denies onboarding without authentication', async () => {
    const db = testEnvironment.unauthenticatedContext().firestore();

    await assertFails(createOwnerPair(db, aliceUid, aliceEmail));
  });

  it('denies an owner from creating records in another UID path', async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);

    await assertFails(createOwnerPair(aliceDb, bobUid, aliceEmail));
  });

  it('denies a non-primary house document', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);

    await assertSucceeds(createOwnerPair(db, aliceUid, aliceEmail));
    await assertFails(
      setDoc(houseRef(db, aliceUid, 'secondary'), houseData(aliceUid)),
    );
  });
});

describe('authentication and owner isolation', () => {
  beforeEach(async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(createOwnerPair(aliceDb, aliceUid, aliceEmail));
    await assertSucceeds(createOwnerPair(bobDb, bobUid, bobEmail));
  });

  it('allows another authenticated context with the same UID to read the same data', async () => {
    const replacementDeviceDb = authenticatedDb(aliceUid, aliceEmail);

    await assertSucceeds(getDoc(profileRef(replacementDeviceDb, aliceUid)));
    await assertSucceeds(
      getDoc(primaryHouseRef(replacementDeviceDb, aliceUid)),
    );
  });

  it('denies one owner from reading another owner profile or house', async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);

    await assertFails(getDoc(profileRef(aliceDb, bobUid)));
    await assertFails(getDoc(primaryHouseRef(aliceDb, bobUid)));
  });

  it('denies one owner from updating another owner profile or house', async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);

    await assertFails(
      updateDoc(profileRef(aliceDb, bobUid), {
        displayName: 'Taken over',
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(primaryHouseRef(aliceDb, bobUid), {
        name: 'Taken over',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('denies reads when the current token is no longer email-verified', async () => {
    const unverifiedDb = authenticatedDb(bobUid, bobEmail, false);

    await assertFails(getDoc(profileRef(unverifiedDb, aliceUid)));
    await assertFails(getDoc(primaryHouseRef(unverifiedDb, aliceUid)));
  });

  it('denies unauthenticated reads', async () => {
    const anonymousDb = testEnvironment.unauthenticatedContext().firestore();

    await assertFails(getDoc(profileRef(anonymousDb, aliceUid)));
    await assertFails(getDoc(primaryHouseRef(anonymousDb, aliceUid)));
  });

  it('denies collection listing even to the owner', async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);

    await assertFails(getDocs(collection(aliceDb, 'users')));
    await assertFails(
      getDocs(collection(aliceDb, 'owners', aliceUid, 'boardingHouses')),
    );
  });
});

describe('profile validation and immutability', () => {
  const invalidProfiles = [
    ['a mismatched email', { email: 'attacker@example.com' }],
    ['an empty display name', { displayName: '' }],
    ['a non-string display name', { displayName: 42 }],
    ['an oversized display name', { displayName: 'x'.repeat(81) }],
    ['a different primary house ID', { primaryHouseId: 'other' }],
    ['a non-string primary house ID', { primaryHouseId: 1 }],
    ['an extra privilege field', { role: 'admin' }],
    ['a forged creation timestamp', { createdAt: new Date(0) }],
    ['a forged update timestamp', { updatedAt: new Date(0) }],
  ];

  for (const [description, profileOverrides] of invalidProfiles) {
    it(`denies onboarding with ${description}`, async () => {
      const db = authenticatedDb(aliceUid, aliceEmail);

      await assertFails(
        createOwnerPair(db, aliceUid, aliceEmail, { profileOverrides }),
      );
    });
  }

  it('allows changing the display name with a server update timestamp', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(createOwnerPair(db, aliceUid, aliceEmail));

    await assertSucceeds(
      updateDoc(profileRef(db, aliceUid), {
        displayName: 'Alice Santos',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('allows synchronizing an email only when it matches the verified auth token', async () => {
    const originalDb = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(createOwnerPair(originalDb, aliceUid, aliceEmail));

    await assertFails(
      updateDoc(profileRef(originalDb, aliceUid), {
        email: 'new-alice@example.com',
        updatedAt: serverTimestamp(),
      }),
    );

    const refreshedAuthDb = authenticatedDb(
      aliceUid,
      'new-alice@example.com',
    );
    await assertSucceeds(
      updateDoc(profileRef(refreshedAuthDb, aliceUid), {
        email: 'new-alice@example.com',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  const immutableProfileFields = [
    ['primaryHouseId', 'other'],
    ['createdAt', new Date(0)],
  ];

  for (const [field, value] of immutableProfileFields) {
    it(`denies changing immutable profile field ${field}`, async () => {
      const db = authenticatedDb(aliceUid, aliceEmail);
      await assertSucceeds(createOwnerPair(db, aliceUid, aliceEmail));

      await assertFails(
        updateDoc(profileRef(db, aliceUid), {
          [field]: value,
          updatedAt: serverTimestamp(),
        }),
      );
    });
  }

  it('denies profile updates without a fresh server timestamp', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(createOwnerPair(db, aliceUid, aliceEmail));

    await assertFails(
      updateDoc(profileRef(db, aliceUid), { displayName: 'Alice Santos' }),
    );
  });
});

describe('house validation and immutability', () => {
  const invalidHouses = [
    ['a mismatched owner UID', { ownerUid: bobUid }],
    ['an empty name', { name: '' }],
    ['a non-string name', { name: 101 }],
    ['an oversized name', { name: 'x'.repeat(121) }],
    ['a different currency', { currencyCode: 'USD' }],
    ['a different business time zone', { businessTimeZone: 'UTC' }],
    ['a different schema version', { schemaVersion: 2 }],
    ['an extra membership field', { memberUids: [aliceUid] }],
    ['a forged creation timestamp', { createdAt: new Date(0) }],
    ['a forged update timestamp', { updatedAt: new Date(0) }],
  ];

  for (const [description, houseOverrides] of invalidHouses) {
    it(`denies onboarding with ${description}`, async () => {
      const db = authenticatedDb(aliceUid, aliceEmail);

      await assertFails(
        createOwnerPair(db, aliceUid, aliceEmail, { houseOverrides }),
      );
    });
  }

  it('allows changing the house name with a server update timestamp', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(createOwnerPair(db, aliceUid, aliceEmail));

    await assertSucceeds(
      updateDoc(primaryHouseRef(db, aliceUid), {
        name: 'Santos Boarding House',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  const immutableHouseFields = [
    ['ownerUid', bobUid],
    ['currencyCode', 'USD'],
    ['businessTimeZone', 'UTC'],
    ['schemaVersion', 2],
    ['createdAt', new Date(0)],
  ];

  for (const [field, value] of immutableHouseFields) {
    it(`denies changing immutable house field ${field}`, async () => {
      const db = authenticatedDb(aliceUid, aliceEmail);
      await assertSucceeds(createOwnerPair(db, aliceUid, aliceEmail));

      await assertFails(
        updateDoc(primaryHouseRef(db, aliceUid), {
          [field]: value,
          updatedAt: serverTimestamp(),
        }),
      );
    });
  }

  it('denies house updates without a fresh server timestamp', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(createOwnerPair(db, aliceUid, aliceEmail));

    await assertFails(
      updateDoc(primaryHouseRef(db, aliceUid), {
        name: 'Santos Boarding House',
      }),
    );
  });
});

describe('Phase 2 room ownership and validation', () => {
  beforeEach(async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(createOwnerPair(aliceDb, aliceUid, aliceEmail));
    await assertSucceeds(createOwnerPair(bobDb, bobUid, bobEmail));
  });

  it('allows the verified owner to create and list valid rooms', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(createRoom(db, aliceUid, 'room-a'));

    const rooms = await assertSucceeds(
      getDocs(
        collection(
          db,
          'owners',
          aliceUid,
          'boardingHouses',
          'primary',
          'rooms',
        ),
      ),
    );
    assert.equal(rooms.size, 1);
  });

  it('denies cross-owner room access', async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(createRoom(bobDb, bobUid, 'room-b'));

    await assertFails(getDoc(roomRef(aliceDb, bobUid, 'room-b')));
    await assertFails(
      setDoc(roomRef(aliceDb, bobUid, 'room-forged'), roomData('room-forged')),
    );
  });

  it('denies malformed rooms and forged bookkeeping', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);

    await assertFails(
      setDoc(
        roomRef(db, aliceUid, 'bad-rent'),
        roomData('bad-rent', { defaultMonthlyRentCentavos: 12.5 }),
      ),
    );
    await assertFails(
      setDoc(
        roomRef(db, aliceUid, 'bad-extra'),
        roomData('bad-extra', { administrator: true }),
      ),
    );
    await assertFails(
      setDoc(
        roomRef(db, aliceUid, 'bad-count'),
        roomData('bad-count', {
          activeOccupancyCount: 1,
          lastOccupancyMutationId: 'forged',
        }),
      ),
    );
  });

  it('allows metadata edits but denies a direct occupancy-count change', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(createRoom(db, aliceUid, 'room-a'));

    await assertSucceeds(
      updateDoc(roomRef(db, aliceUid, 'room-a'), {
        roomName: 'Room A - Ground Floor',
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(roomRef(db, aliceUid, 'room-a'), {
        activeOccupancyCount: 1,
        lastOccupancyMutationId: 'forged-occupancy',
        updatedAt: serverTimestamp(),
      }),
    );
  });
});

describe('Phase 2 occupancy lifecycle', () => {
  const moveIn = businessDate('2024-01-01');
  const transferDate = businessDate('2024-01-15');
  const moveOutDate = businessDate('2024-02-01');

  beforeEach(async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(createOwnerPair(db, aliceUid, aliceEmail));
    await assertSucceeds(createRoom(db, aliceUid, 'room-a'));
    await assertSucceeds(createRoom(db, aliceUid, 'room-b'));
  });

  it('creates multiple boarders in one room with separate open occupancies', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      createAssignedBoarder(db, aliceUid, {
        boarderId: 'boarder-1',
        occupancyId: 'occupancy-1',
        roomId: 'room-a',
        moveInDate: moveIn,
      }),
    );
    await assertSucceeds(
      createAssignedBoarder(db, aliceUid, {
        boarderId: 'boarder-2',
        occupancyId: 'occupancy-2',
        roomId: 'room-a',
        moveInDate: moveIn,
        previousRoomCount: 1,
      }),
    );

    const room = await getDoc(roomRef(db, aliceUid, 'room-a'));
    assert.equal(room.data().activeOccupancyCount, 2);
  });

  it('denies creating an assigned boarder without its occupancy and room update', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);

    await assertFails(
      setDoc(
        boarderRef(db, aliceUid, 'boarder-1'),
        boarderData('boarder-1', 'occupancy-1', 'room-a', moveIn),
      ),
    );
  });

  it('atomically transfers a boarder at mid-month and closes the old interval', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      createAssignedBoarder(db, aliceUid, {
        boarderId: 'boarder-1',
        occupancyId: 'occupancy-1',
        roomId: 'room-a',
        moveInDate: moveIn,
      }),
    );

    const batch = writeBatch(db);
    batch.update(occupancyRef(db, aliceUid, 'occupancy-1'), {
      moveOutDate: transferDate,
      updatedAt: serverTimestamp(),
    });
    batch.set(
      occupancyRef(db, aliceUid, 'occupancy-2'),
      occupancyData(
        'occupancy-2',
        'boarder-1',
        'room-b',
        transferDate,
      ),
    );
    batch.update(boarderRef(db, aliceUid, 'boarder-1'), {
      currentOccupancyId: 'occupancy-2',
      currentRoomId: 'room-b',
      currentMoveInDate: transferDate,
      lastMoveOutDate: transferDate,
      updatedAt: serverTimestamp(),
    });
    batch.update(roomRef(db, aliceUid, 'room-a'), {
      activeOccupancyCount: 0,
      lastOccupancyMutationId: 'occupancy-1',
      updatedAt: serverTimestamp(),
    });
    batch.update(roomRef(db, aliceUid, 'room-b'), {
      activeOccupancyCount: 1,
      lastOccupancyMutationId: 'occupancy-2',
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());

    const [oldOccupancy, newOccupancy] = await Promise.all([
      getDoc(occupancyRef(db, aliceUid, 'occupancy-1')),
      getDoc(occupancyRef(db, aliceUid, 'occupancy-2')),
    ]);
    assert.equal(oldOccupancy.data().moveOutDate.toMillis(), transferDate.toMillis());
    assert.equal(newOccupancy.data().moveInDate.toMillis(), transferDate.toMillis());
    assert.equal(newOccupancy.data().moveOutDate, null);
  });

  it('denies a second simultaneous assignment that leaves the first open', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      createAssignedBoarder(db, aliceUid, {
        boarderId: 'boarder-1',
        occupancyId: 'occupancy-1',
        roomId: 'room-a',
        moveInDate: moveIn,
      }),
    );

    const batch = writeBatch(db);
    batch.set(
      occupancyRef(db, aliceUid, 'occupancy-2'),
      occupancyData(
        'occupancy-2',
        'boarder-1',
        'room-b',
        transferDate,
      ),
    );
    batch.update(boarderRef(db, aliceUid, 'boarder-1'), {
      currentOccupancyId: 'occupancy-2',
      currentRoomId: 'room-b',
      currentMoveInDate: transferDate,
      lastMoveOutDate: transferDate,
      updatedAt: serverTimestamp(),
    });
    batch.update(roomRef(db, aliceUid, 'room-b'), {
      activeOccupancyCount: 1,
      lastOccupancyMutationId: 'occupancy-2',
      updatedAt: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  it('atomically moves a boarder out and preserves the closed history', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      createAssignedBoarder(db, aliceUid, {
        boarderId: 'boarder-1',
        occupancyId: 'occupancy-1',
        roomId: 'room-a',
        moveInDate: moveIn,
      }),
    );

    const batch = writeBatch(db);
    batch.update(occupancyRef(db, aliceUid, 'occupancy-1'), {
      moveOutDate,
      updatedAt: serverTimestamp(),
    });
    batch.update(boarderRef(db, aliceUid, 'boarder-1'), {
      status: 'movedOut',
      currentOccupancyId: null,
      currentRoomId: null,
      currentMoveInDate: null,
      lastMoveOutDate: moveOutDate,
      updatedAt: serverTimestamp(),
    });
    batch.update(roomRef(db, aliceUid, 'room-a'), {
      activeOccupancyCount: 0,
      lastOccupancyMutationId: 'occupancy-1',
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());

    await assertFails(
      updateDoc(occupancyRef(db, aliceUid, 'occupancy-1'), {
        moveOutDate: businessDate('2024-02-02'),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(deleteDoc(occupancyRef(db, aliceUid, 'occupancy-1')));
  });

  it('denies deactivating an occupied room and allows it after move-out', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      createAssignedBoarder(db, aliceUid, {
        boarderId: 'boarder-1',
        occupancyId: 'occupancy-1',
        roomId: 'room-a',
        moveInDate: moveIn,
      }),
    );
    await assertFails(
      updateDoc(roomRef(db, aliceUid, 'room-a'), {
        status: 'inactive',
        updatedAt: serverTimestamp(),
      }),
    );

    const batch = writeBatch(db);
    batch.update(occupancyRef(db, aliceUid, 'occupancy-1'), {
      moveOutDate,
      updatedAt: serverTimestamp(),
    });
    batch.update(boarderRef(db, aliceUid, 'boarder-1'), {
      status: 'movedOut',
      currentOccupancyId: null,
      currentRoomId: null,
      currentMoveInDate: null,
      lastMoveOutDate: moveOutDate,
      updatedAt: serverTimestamp(),
    });
    batch.update(roomRef(db, aliceUid, 'room-a'), {
      activeOccupancyCount: 0,
      lastOccupancyMutationId: 'occupancy-1',
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
    await assertSucceeds(
      updateDoc(roomRef(db, aliceUid, 'room-a'), {
        status: 'inactive',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('denies overlap when a moved-out boarder is assigned before their last move-out', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await setDoc(
        boarderRef(adminDb, aliceUid, 'boarder-1'),
        boarderData(
          'boarder-1',
          null,
          null,
          null,
          {
            status: 'movedOut',
            currentOccupancyId: null,
            currentRoomId: null,
            currentMoveInDate: null,
            lastMoveOutDate: moveOutDate,
          },
        ),
      );
    });

    const overlappingDate = businessDate('2024-01-20');
    const batch = writeBatch(db);
    batch.set(
      occupancyRef(db, aliceUid, 'occupancy-2'),
      occupancyData(
        'occupancy-2',
        'boarder-1',
        'room-b',
        overlappingDate,
      ),
    );
    batch.update(boarderRef(db, aliceUid, 'boarder-1'), {
      status: 'active',
      currentOccupancyId: 'occupancy-2',
      currentRoomId: 'room-b',
      currentMoveInDate: overlappingDate,
      updatedAt: serverTimestamp(),
    });
    batch.update(roomRef(db, aliceUid, 'room-b'), {
      activeOccupancyCount: 1,
      lastOccupancyMutationId: 'occupancy-2',
      updatedAt: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  it('denies deletes of room and boarder records', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(createRoom(db, aliceUid, 'room-c'));
    await assertFails(deleteDoc(roomRef(db, aliceUid, 'room-c')));

    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await setDoc(
        boarderRef(adminDb, aliceUid, 'inactive-boarder'),
        boarderData('inactive-boarder', null, null, null, {
          status: 'inactive',
          currentOccupancyId: null,
          currentRoomId: null,
          currentMoveInDate: null,
        }),
      );
    });
    await assertFails(
      deleteDoc(boarderRef(db, aliceUid, 'inactive-boarder')),
    );
  });
});

describe('Phase 3 electricity meter lifecycle', () => {
  const openingDate = businessDate('2024-01-01');
  const regularDate = businessDate('2024-01-15');
  const transitionDate = businessDate('2024-02-01');
  const laterDate = businessDate('2024-02-15');

  beforeEach(async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(createOwnerPair(aliceDb, aliceUid, aliceEmail));
    await assertSucceeds(createOwnerPair(bobDb, bobUid, bobEmail));
    await assertSucceeds(createRoom(aliceDb, aliceUid, 'room-a'));
    await assertSucceeds(createRoom(aliceDb, aliceUid, 'room-b'));
    await assertSucceeds(createRoom(aliceDb, aliceUid, 'room-c'));
    await assertSucceeds(createRoom(bobDb, bobUid, 'room-a'));
  });

  it('atomically installs a room meter and opening reading', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      installInitialMeter(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-a-open',
        readingDate: openingDate,
        readingWh: 1250000,
      }),
    );

    const [state, meter, reading] = await Promise.all([
      getDoc(roomMeterStateRef(db, aliceUid, 'room-a')),
      getDoc(electricityMeterRef(db, aliceUid, 'meter-a-1')),
      getDoc(meterReadingRef(db, aliceUid, 'reading-a-open')),
    ]);
    assert.equal(state.data().currentMeterId, 'meter-a-1');
    assert.equal(meter.data().lastReadingWh, 1250000);
    assert.equal(reading.data().kind, 'opening');
  });

  it('denies partial installation and malformed meter fields', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);

    await assertFails(
      setDoc(
        roomMeterStateRef(db, aliceUid, 'room-a'),
        roomMeterStateData('room-a', 'meter-a-1'),
      ),
    );
    await assertFails(
      setDoc(
        electricityMeterRef(db, aliceUid, 'meter-a-1'),
        electricityMeterData(
          'meter-a-1',
          'room-a',
          'reading-a-open',
          openingDate,
          1250000,
        ),
      ),
    );
    await assertFails(
      setDoc(
        meterReadingRef(db, aliceUid, 'reading-a-open'),
        meterReadingData(
          'reading-a-open',
          'meter-a-1',
          'room-a',
          1,
          openingDate,
          1250000,
        ),
      ),
    );
    await assertFails(
      installInitialMeter(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-a-open',
        readingDate: openingDate,
        readingWh: 1250000.5,
      }),
    );
    await assertFails(
      installInitialMeter(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-a-open',
        readingDate: openingDate,
        readingWh: 1250000,
        meterOverrides: { administrator: true },
      }),
    );
  });

  it('denies owner crossover for meter data and collection reads', async () => {
    const bobDb = authenticatedDb(bobUid, bobEmail);
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      installInitialMeter(bobDb, bobUid, {
        roomId: 'room-a',
        meterId: 'bob-meter-1',
        readingId: 'bob-opening',
        readingDate: openingDate,
        readingWh: 100000,
      }),
    );

    await assertFails(
      getDoc(electricityMeterRef(aliceDb, bobUid, 'bob-meter-1')),
    );
    await assertFails(
      getDocs(
        collection(
          aliceDb,
          'owners',
          bobUid,
          'boardingHouses',
          'primary',
          'meterReadings',
        ),
      ),
    );
    const unverifiedDb = authenticatedDb(aliceUid, aliceEmail, false);
    const anonymousDb = testEnvironment.unauthenticatedContext().firestore();
    await assertFails(
      getDoc(electricityMeterRef(unverifiedDb, bobUid, 'bob-meter-1')),
    );
    await assertFails(
      getDoc(electricityMeterRef(anonymousDb, bobUid, 'bob-meter-1')),
    );
    await assertFails(
      installInitialMeter(aliceDb, bobUid, {
        roomId: 'room-a',
        meterId: 'forged-meter',
        readingId: 'forged-opening',
        readingDate: openingDate,
        readingWh: 100000,
      }),
    );
  });

  it('atomically appends regular and intermediate readings', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      installInitialMeter(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-a-open',
        readingDate: openingDate,
        readingWh: 1250000,
      }),
    );
    await assertSucceeds(
      appendMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        previousReadingId: 'reading-a-open',
        previousReadingDate: openingDate,
        previousReadingWh: 1250000,
        readingId: 'reading-a-mid',
        readingDate: regularDate,
        readingWh: 1290000,
        kind: 'intermediate',
      }),
    );
    await assertSucceeds(
      appendMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        previousReadingId: 'reading-a-mid',
        previousReadingDate: regularDate,
        previousReadingWh: 1290000,
        readingId: 'reading-a-current',
        readingDate: transitionDate,
        readingWh: 1340000,
      }),
    );

    const meter = await getDoc(
      electricityMeterRef(db, aliceUid, 'meter-a-1'),
    );
    assert.equal(meter.data().lastReadingId, 'reading-a-current');
    assert.equal(meter.data().lastReadingWh, 1340000);
  });

  it('allows zero consumption but denies duplicate, backdated, and lower readings', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      installInitialMeter(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-a-open',
        readingDate: openingDate,
        readingWh: 1250000,
      }),
    );
    await assertSucceeds(
      appendMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        previousReadingId: 'reading-a-open',
        previousReadingDate: openingDate,
        previousReadingWh: 1250000,
        readingId: 'zero-reading',
        readingDate: regularDate,
        readingWh: 1250000,
      }),
    );

    for (const attempt of [
      {
        readingId: 'duplicate-date',
        readingDate: regularDate,
        readingWh: 1260000,
      },
      {
        readingId: 'backdated',
        readingDate: businessDate('2024-01-10'),
        readingWh: 1260000,
      },
      {
        readingId: 'lower-reading',
        readingDate: transitionDate,
        readingWh: 1240000,
      },
    ]) {
      await assertFails(
        appendMeterReading(db, aliceUid, {
          roomId: 'room-a',
          meterId: 'meter-a-1',
          previousReadingId: 'zero-reading',
          previousReadingDate: regularDate,
          previousReadingWh: 1250000,
          ...attempt,
        }),
      );
    }
  });

  it('denies a reading without its head update and a forged head update', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      installInitialMeter(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-a-open',
        readingDate: openingDate,
        readingWh: 1250000,
      }),
    );

    await assertFails(
      setDoc(
        meterReadingRef(db, aliceUid, 'orphan-reading'),
        meterReadingData(
          'orphan-reading',
          'meter-a-1',
          'room-a',
          1,
          regularDate,
          1290000,
          {
            kind: 'regular',
            previousReadingId: 'reading-a-open',
            previousReadingDate: openingDate,
            previousReadingWh: 1250000,
            consumptionWh: 40000,
          },
        ),
      ),
    );
    await assertFails(
      updateDoc(electricityMeterRef(db, aliceUid, 'meter-a-1'), {
        lastReadingId: 'missing-reading',
        lastReadingDate: regularDate,
        lastReadingWh: 1290000,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('keeps readings and meter identity history immutable', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      installInitialMeter(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-a-open',
        readingDate: openingDate,
        readingWh: 1250000,
      }),
    );

    await assertFails(
      updateDoc(meterReadingRef(db, aliceUid, 'reading-a-open'), {
        readingWh: 1,
      }),
    );
    await assertFails(
      deleteDoc(meterReadingRef(db, aliceUid, 'reading-a-open')),
    );
    await assertFails(
      updateDoc(electricityMeterRef(db, aliceUid, 'meter-a-1'), {
        sequenceNumber: 99,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      deleteDoc(electricityMeterRef(db, aliceUid, 'meter-a-1')),
    );
    await assertFails(
      deleteDoc(roomMeterStateRef(db, aliceUid, 'room-a')),
    );
  });

  it('atomically starts reset, replacement, and correction sequences', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const cases = [
      ['room-a', 'reset'],
      ['room-b', 'replacement'],
      ['room-c', 'correction'],
    ];

    for (const [roomId, startKind] of cases) {
      const oldMeterId = `${roomId}-meter-1`;
      const openingReadingId = `${roomId}-opening-1`;
      const newMeterId = `${roomId}-meter-2`;
      await assertSucceeds(
        installInitialMeter(db, aliceUid, {
          roomId,
          meterId: oldMeterId,
          readingId: openingReadingId,
          readingDate: openingDate,
          readingWh: 1250000,
        }),
      );
      await assertSucceeds(
        transitionMeter(db, aliceUid, {
          roomId,
          oldMeterId,
          oldSequenceNumber: 1,
          oldReadingId: openingReadingId,
          oldReadingDate: openingDate,
          oldReadingWh: 1250000,
          closingReadingId: `${roomId}-closing-1`,
          transitionDate,
          closingReadingWh: 1340000,
          newMeterId,
          openingReadingId: `${roomId}-opening-2`,
          openingReadingWh: 25000,
          startKind,
          transitionReason: `${startKind} documented by owner`,
        }),
      );

      const [state, oldMeter, nextMeter] = await Promise.all([
        getDoc(roomMeterStateRef(db, aliceUid, roomId)),
        getDoc(electricityMeterRef(db, aliceUid, oldMeterId)),
        getDoc(electricityMeterRef(db, aliceUid, newMeterId)),
      ]);
      assert.equal(state.data().currentMeterId, newMeterId);
      assert.equal(oldMeter.data().status, 'retired');
      assert.equal(nextMeter.data().startKind, startKind);
      assert.equal(nextMeter.data().lastReadingWh, 25000);
    }
  });

  it('denies incomplete or undocumented meter transitions', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      installInitialMeter(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-a-open',
        readingDate: openingDate,
        readingWh: 1250000,
      }),
    );

    await assertFails(
      transitionMeter(db, aliceUid, {
        roomId: 'room-a',
        oldMeterId: 'meter-a-1',
        oldSequenceNumber: 1,
        oldReadingId: 'reading-a-open',
        oldReadingDate: openingDate,
        oldReadingWh: 1250000,
        closingReadingId: 'reading-a-close',
        transitionDate,
        closingReadingWh: 1340000,
        newMeterId: 'meter-a-2',
        openingReadingId: 'reading-a-open-2',
        openingReadingWh: 25000,
        startKind: 'reset',
        transitionReason: '',
      }),
    );
    await assertFails(
      transitionMeter(db, aliceUid, {
        roomId: 'room-a',
        oldMeterId: 'meter-a-1',
        oldSequenceNumber: 1,
        oldReadingId: 'reading-a-open',
        oldReadingDate: openingDate,
        oldReadingWh: 1250000,
        closingReadingId: 'reading-a-close',
        transitionDate,
        closingReadingWh: 1340000,
        newMeterId: 'meter-a-2',
        openingReadingId: 'reading-a-open-2',
        openingReadingWh: 25000,
        startKind: 'reset',
        transitionReason: 'Meter reset',
        newMeterOverrides: { sequenceNumber: 4 },
      }),
    );
  });

  it('denies appending readings to a retired meter', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      installInitialMeter(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-a-open',
        readingDate: openingDate,
        readingWh: 1250000,
      }),
    );
    await assertSucceeds(
      transitionMeter(db, aliceUid, {
        roomId: 'room-a',
        oldMeterId: 'meter-a-1',
        oldSequenceNumber: 1,
        oldReadingId: 'reading-a-open',
        oldReadingDate: openingDate,
        oldReadingWh: 1250000,
        closingReadingId: 'reading-a-close',
        transitionDate,
        closingReadingWh: 1340000,
        newMeterId: 'meter-a-2',
        openingReadingId: 'reading-a-open-2',
        openingReadingWh: 25000,
        startKind: 'replacement',
        transitionReason: 'Installed replacement meter',
      }),
    );

    await assertFails(
      appendMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        previousReadingId: 'reading-a-close',
        previousReadingDate: transitionDate,
        previousReadingWh: 1340000,
        readingId: 'retired-reading',
        readingDate: laterDate,
        readingWh: 1350000,
      }),
    );
  });

  it('rejects future and non-date-only meter readings', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const today = manilaDateFromNow();
    const tomorrow = manilaDateFromNow(1);
    const nonMidnight = Timestamp.fromMillis(today.toMillis() + 60 * 60 * 1000);

    await assertFails(
      installInitialMeter(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'future-meter',
        readingId: 'future-opening',
        readingDate: tomorrow,
        readingWh: 1000,
      }),
    );
    await assertFails(
      installInitialMeter(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'time-meter',
        readingId: 'time-opening',
        readingDate: nonMidnight,
        readingWh: 1000,
      }),
    );
  });
});

describe('Pre-Phase 8 meter reading corrections', () => {
  const openingDate = businessDate('2024-01-01');
  const regularDate = businessDate('2024-01-15');
  const correctedDate = businessDate('2024-01-16');

  beforeEach(async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(createOwnerPair(aliceDb, aliceUid, aliceEmail));
    await assertSucceeds(createOwnerPair(bobDb, bobUid, bobEmail));
    await assertSucceeds(createRoom(aliceDb, aliceUid, 'room-a'));
    await assertSucceeds(createRoom(bobDb, bobUid, 'room-a'));
  });

  it('corrects the latest unbilled regular reading with meter and audit atomically', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      installInitialMeter(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-open',
        readingDate: openingDate,
        readingWh: 100000,
      }),
    );
    await assertSucceeds(
      appendMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        previousReadingId: 'reading-open',
        previousReadingDate: openingDate,
        previousReadingWh: 100000,
        readingId: 'reading-current',
        readingDate: regularDate,
        readingWh: 125000,
      }),
    );

    await assertSucceeds(
      correctMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-current',
        kind: 'regular',
        beforeDate: regularDate,
        beforeWh: 125000,
        beforeConsumptionWh: 25000,
        previousReadingDate: openingDate,
        previousReadingWh: 100000,
        beforeMeterStartedOn: openingDate,
        correctedDate,
        correctedWh: 128000,
        correctedConsumptionWh: 28000,
      }),
    );

    const [reading, meter, audit] = await Promise.all([
      getDoc(meterReadingRef(db, aliceUid, 'reading-current')),
      getDoc(electricityMeterRef(db, aliceUid, 'meter-a-1')),
      getDoc(meterReadingCorrectionRef(db, aliceUid, 'correction-1')),
    ]);
    assert.equal(reading.data().readingWh, 128000);
    assert.equal(reading.data().correctionCount, 1);
    assert.equal(meter.data().lastReadingWh, 128000);
    assert.equal(audit.data().before.readingWh, 125000);
    assert.equal(audit.data().after.readingWh, 128000);

    await assertFails(
      updateDoc(meterReadingCorrectionRef(db, aliceUid, 'correction-1'), {
        reason: 'Changed audit',
      }),
    );
    await assertFails(
      deleteDoc(meterReadingCorrectionRef(db, aliceUid, 'correction-1')),
    );
  });

  it('corrects an initial baseline and keeps meter startedOn aligned', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      installInitialMeter(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-open',
        readingDate: openingDate,
        readingWh: 100000,
      }),
    );

    await assertSucceeds(
      correctMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-open',
        kind: 'opening',
        beforeDate: openingDate,
        beforeWh: 100000,
        beforeConsumptionWh: 0,
        beforeMeterStartedOn: openingDate,
        correctedDate: businessDate('2024-01-02'),
        correctedWh: 101000,
        correctedConsumptionWh: 0,
      }),
    );

    const meter = await getDoc(
      electricityMeterRef(db, aliceUid, 'meter-a-1'),
    );
    assert.equal(
      meter.data().startedOn.toMillis(),
      businessDate('2024-01-02').toMillis(),
    );
    assert.equal(meter.data().lastReadingWh, 101000);
  });

  it('rejects older, billed, invalid, incomplete, and forged corrections', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      installInitialMeter(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-open',
        readingDate: openingDate,
        readingWh: 100000,
      }),
    );
    await assertSucceeds(
      appendMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        previousReadingId: 'reading-open',
        previousReadingDate: openingDate,
        previousReadingWh: 100000,
        readingId: 'reading-current',
        readingDate: regularDate,
        readingWh: 125000,
      }),
    );

    await assertFails(
      correctMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-open',
        kind: 'opening',
        beforeDate: openingDate,
        beforeWh: 100000,
        beforeConsumptionWh: 0,
        beforeMeterStartedOn: openingDate,
        correctedDate: businessDate('2024-01-02'),
        correctedWh: 101000,
        correctedConsumptionWh: 0,
      }),
    );
    await assertFails(
      correctMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-current',
        kind: 'regular',
        beforeDate: regularDate,
        beforeWh: 125000,
        beforeConsumptionWh: 25000,
        beforeMeterStartedOn: openingDate,
        correctedDate: openingDate,
        correctedWh: 99000,
        correctedConsumptionWh: 0,
      }),
    );
    await assertFails(
      correctMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-current',
        kind: 'regular',
        beforeDate: regularDate,
        beforeWh: 125000,
        beforeConsumptionWh: 25000,
        beforeMeterStartedOn: openingDate,
        correctedDate,
        correctedWh: 128000,
        correctedConsumptionWh: 28000,
        includeAudit: false,
      }),
    );
    await assertFails(
      correctMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-current',
        kind: 'regular',
        beforeDate: regularDate,
        beforeWh: 125000,
        beforeConsumptionWh: 25000,
        beforeMeterStartedOn: openingDate,
        correctedDate,
        correctedWh: 128000,
        correctedConsumptionWh: 28000,
        correctionOverrides: { correctedBy: bobUid },
      }),
    );

    await assertSucceeds(
      createElectricityRecordAndLockReading(db, aliceUid, {
        recordId: 'locked-bill',
        readingId: 'reading-current',
      }),
    );
    await assertFails(
      correctMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a-1',
        readingId: 'reading-current',
        kind: 'regular',
        beforeDate: regularDate,
        beforeWh: 125000,
        beforeConsumptionWh: 25000,
        beforeMeterStartedOn: openingDate,
        correctedDate,
        correctedWh: 128000,
        correctedConsumptionWh: 28000,
      }),
    );
  });

  it('rejects cross-owner correction attempts', async () => {
    const bobDb = authenticatedDb(bobUid, bobEmail);
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      installInitialMeter(bobDb, bobUid, {
        roomId: 'room-a',
        meterId: 'bob-meter',
        readingId: 'bob-reading',
        readingDate: openingDate,
        readingWh: 100000,
      }),
    );
    await assertFails(
      correctMeterReading(aliceDb, bobUid, {
        roomId: 'room-a',
        meterId: 'bob-meter',
        readingId: 'bob-reading',
        kind: 'opening',
        beforeDate: openingDate,
        beforeWh: 100000,
        beforeConsumptionWh: 0,
        beforeMeterStartedOn: openingDate,
        correctedDate: businessDate('2024-01-02'),
        correctedWh: 101000,
        correctedConsumptionWh: 0,
      }),
    );
  });
});

describe('missing historical meter readings', () => {
  const openingDate = businessDate('2024-01-01');
  const closingDate = businessDate('2024-01-31');

  beforeEach(async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(createOwnerPair(db, aliceUid, aliceEmail));
    await assertSucceeds(createRoom(db, aliceUid, 'room-a'));
    await assertSucceeds(
      installInitialMeter(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a',
        readingId: 'opening',
        readingDate: openingDate,
        readingWh: 100000,
      }),
    );
    await assertSucceeds(
      appendMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a',
        previousReadingId: 'opening',
        previousReadingDate: openingDate,
        previousReadingWh: 100000,
        readingId: 'month-end',
        readingDate: closingDate,
        readingWh: 130000,
      }),
    );
  });

  it('inserts an unbilled boundary, relinks its successor, and keeps audit immutable', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      insertHistoricalMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a',
        predecessorReadingId: 'opening',
        predecessorDate: openingDate,
        predecessorWh: 100000,
        successorReadingId: 'month-end',
        successorDate: closingDate,
        successorWh: 130000,
        insertedReadingId: 'mid-month',
        insertedDate: businessDate('2024-01-15'),
        insertedWh: 115000,
      }),
    );
    const successor = await getDoc(
      meterReadingRef(db, aliceUid, 'month-end'),
    );
    assert.equal(successor.data().previousReadingId, 'mid-month');
    assert.equal(successor.data().consumptionWh, 15000);
    await assertFails(
      updateDoc(meterReadingInsertionRef(db, aliceUid, 'mid-month'), {
        reason: 'Changed audit',
      }),
    );
    await assertFails(
      deleteDoc(meterReadingInsertionRef(db, aliceUid, 'mid-month')),
    );
  });

  it('rejects out-of-range values and forged audit ownership', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertFails(
      insertHistoricalMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a',
        predecessorReadingId: 'opening',
        predecessorDate: openingDate,
        predecessorWh: 100000,
        successorReadingId: 'month-end',
        successorDate: closingDate,
        successorWh: 130000,
        insertedReadingId: 'bad-value',
        insertedDate: businessDate('2024-01-15'),
        insertedWh: 140000,
      }),
    );
    await assertFails(
      insertHistoricalMeterReading(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a',
        predecessorReadingId: 'opening',
        predecessorDate: openingDate,
        predecessorWh: 100000,
        successorReadingId: 'month-end',
        successorDate: closingDate,
        successorWh: 130000,
        insertedReadingId: 'forged-owner',
        insertedDate: businessDate('2024-01-15'),
        insertedWh: 115000,
        insertionOverrides: { createdBy: bobUid },
      }),
    );
  });
});

describe('Phase 3 immutable electricity billing records', () => {
  beforeEach(async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(createOwnerPair(aliceDb, aliceUid, aliceEmail));
    await assertSucceeds(createOwnerPair(bobDb, bobUid, bobEmail));
  });

  it('creates a reconciled owner-scoped record once', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const recordId = 'electricity-2024-01';
    await assertSucceeds(
      setDoc(
        electricityBillingRecordRef(db, aliceUid, recordId),
        electricityBillingRecordData(recordId, {
          totalAdjustmentCentavos: -8000,
          totalChargeCentavos: 100000,
          totalAllocatedCentavos: 95000,
          totalUnallocatedCentavos: 5000,
          roomCharges: [{ roomId: 'room-a', totalChargeCentavos: 100000 }],
          warnings: ['One allocation is estimated.'],
        }),
      ),
    );

    await assertSucceeds(
      getDoc(electricityBillingRecordRef(db, aliceUid, recordId)),
    );
    await assertFails(
      setDoc(
        electricityBillingRecordRef(db, aliceUid, recordId),
        electricityBillingRecordData(recordId),
      ),
    );
  });

  it('denies malformed, unreconciled, or forged billing records', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const cases = [
      ['wrong-id', { recordId: 'another-id' }],
      ['float-rate', { rateMicropesosPerKwh: 12000000.5 }],
      ['bad-charge-total', { totalChargeCentavos: 100 }],
      ['bad-allocation-total', { totalAllocatedCentavos: 100 }],
      ['negative-final', {
        totalBaseChargeCentavos: 100,
        totalAdjustmentCentavos: -200,
        totalChargeCentavos: -100,
        totalAllocatedCentavos: -100,
      }],
      ['forged-owner', { createdBy: bobUid }],
      ['too-many-warnings', { warnings: Array(101).fill('warning') }],
      ['too-many-rooms', { roomCharges: Array(501).fill({}) }],
      ['extra-field', { administrator: true }],
    ];

    for (const [recordId, overrides] of cases) {
      await assertFails(
        setDoc(
          electricityBillingRecordRef(db, aliceUid, recordId),
          electricityBillingRecordData(recordId, overrides),
        ),
      );
    }
  });

  it('denies cross-owner access and all record mutation or deletion', async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    const recordId = 'electricity-2024-01';
    await assertSucceeds(
      setDoc(
        electricityBillingRecordRef(aliceDb, aliceUid, recordId),
        electricityBillingRecordData(recordId),
      ),
    );

    await assertFails(
      getDoc(electricityBillingRecordRef(bobDb, aliceUid, recordId)),
    );
    await assertFails(
      updateDoc(
        electricityBillingRecordRef(aliceDb, aliceUid, recordId),
        { totalChargeCentavos: 1 },
      ),
    );
    await assertFails(
      deleteDoc(electricityBillingRecordRef(aliceDb, aliceUid, recordId)),
    );
  });
});

describe('Phase 4 water settings', () => {
  beforeEach(async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(createOwnerPair(aliceDb, aliceUid, aliceEmail));
    await assertSucceeds(createOwnerPair(bobDb, bobUid, bobEmail));
  });

  it('allows the owner to create and update valid settings', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      setDoc(waterSettingsRef(db, aliceUid), waterSettingsData()),
    );
    await assertSucceeds(
      updateDoc(waterSettingsRef(db, aliceUid), {
        defaultMethod: 'electricityPercentage',
        summerBasis: 'roomConsumption',
        summerMonths: [2, 3, 4, 5],
        allowManualMethodOverride: false,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('denies malformed settings, cross-owner access, and deletion', async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertFails(
      setDoc(
        waterSettingsRef(aliceDb, aliceUid),
        waterSettingsData({ summerMonths: [0, 13] }),
      ),
    );
    await assertSucceeds(
      setDoc(waterSettingsRef(aliceDb, aliceUid), waterSettingsData()),
    );
    await assertFails(getDoc(waterSettingsRef(bobDb, aliceUid)));
    await assertFails(
      updateDoc(waterSettingsRef(bobDb, aliceUid), {
        defaultMethod: 'electricityPercentage',
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(deleteDoc(waterSettingsRef(aliceDb, aliceUid)));
  });
});

describe('Phase 4 immutable water billing records', () => {
  beforeEach(async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(createOwnerPair(aliceDb, aliceUid, aliceEmail));
    await assertSucceeds(createOwnerPair(bobDb, bobUid, bobEmail));
  });

  it('creates a reconciled person-day record once', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const recordId = '2024-01-01_2024-02-01';
    await assertSucceeds(
      setDoc(
        waterBillingRecordRef(db, aliceUid, recordId),
        waterBillingRecordData(recordId),
      ),
    );
    await assertSucceeds(getDoc(waterBillingRecordRef(db, aliceUid, recordId)));
    await assertFails(
      setDoc(
        waterBillingRecordRef(db, aliceUid, recordId),
        waterBillingRecordData(recordId),
      ),
    );
  });

  it('creates an immutable occupied-room-day record without boarder shares', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const recordId = '2024-01-01_2024-02-01_roomDays';
    await assertSucceeds(
      setDoc(
        waterBillingRecordRef(db, aliceUid, recordId),
        waterBillingRecordData(recordId, {
          method: 'roomDays',
          totalPersonDays: 31,
          roomAllocations: [
            {
              roomId: 'room-a',
              roomName: 'Room A',
              electricityBasisValue: 0,
              occupancyDays: 31,
              roomChargeCentavos: 120000,
              allocatedCentavos: 120000,
              unallocatedCentavos: 0,
              boarderShares: [],
            },
          ],
          boarderShares: [],
        }),
      ),
    );
    await assertFails(
      updateDoc(waterBillingRecordRef(db, aliceUid, recordId), {
        waterBillCentavos: 1,
      }),
    );
    await assertFails(
      setDoc(
        waterBillingRecordRef(db, aliceUid, 'bad-room-days'),
        waterBillingRecordData('bad-room-days', {
          method: 'roomDays',
          boarderShares: [{ boarderId: 'forged' }],
        }),
      ),
    );
  });

  it('requires a matching electricity record and exact summer basis', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const electricityRecordId = 'electricity-2024-01';
    await assertSucceeds(
      setDoc(
        electricityBillingRecordRef(db, aliceUid, electricityRecordId),
        electricityBillingRecordData(electricityRecordId),
      ),
    );

    const chargeRecordId = 'summer-charge';
    await assertSucceeds(
      setDoc(
        waterBillingRecordRef(db, aliceUid, chargeRecordId),
        waterBillingRecordData(chargeRecordId, {
          method: 'electricityPercentage',
          electricityRecordId,
          totalElectricityBasis: 108000,
        }),
      ),
    );
    const consumptionRecordId = 'summer-consumption';
    await assertSucceeds(
      setDoc(
        waterBillingRecordRef(db, aliceUid, consumptionRecordId),
        waterBillingRecordData(consumptionRecordId, {
          method: 'electricityPercentage',
          summerBasis: 'roomConsumption',
          electricityRecordId,
          totalElectricityBasis: 90000,
        }),
      ),
    );
    await assertFails(
      setDoc(
        waterBillingRecordRef(db, aliceUid, 'wrong-summer-basis'),
        waterBillingRecordData('wrong-summer-basis', {
          method: 'electricityPercentage',
          electricityRecordId,
          totalElectricityBasis: 107999,
        }),
      ),
    );
    await assertFails(
      setDoc(
        waterBillingRecordRef(db, aliceUid, 'missing-electricity'),
        waterBillingRecordData('missing-electricity', {
          method: 'electricityPercentage',
          electricityRecordId: 'does-not-exist',
          totalElectricityBasis: 1,
        }),
      ),
    );
  });

  it('denies invalid totals, forged owners, cross-owner access, and mutation', async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    const recordId = 'water-2024-01';
    await assertFails(
      setDoc(
        waterBillingRecordRef(aliceDb, aliceUid, 'bad-total'),
        waterBillingRecordData('bad-total', { totalAllocatedCentavos: 1 }),
      ),
    );
    await assertFails(
      setDoc(
        waterBillingRecordRef(aliceDb, aliceUid, 'forged-owner'),
        waterBillingRecordData('forged-owner', { createdBy: bobUid }),
      ),
    );
    await assertSucceeds(
      setDoc(
        waterBillingRecordRef(aliceDb, aliceUid, recordId),
        waterBillingRecordData(recordId),
      ),
    );
    await assertFails(getDoc(waterBillingRecordRef(bobDb, aliceUid, recordId)));
    await assertFails(
      updateDoc(waterBillingRecordRef(aliceDb, aliceUid, recordId), {
        waterBillCentavos: 1,
      }),
    );
    await assertFails(
      deleteDoc(waterBillingRecordRef(aliceDb, aliceUid, recordId)),
    );
  });
});

describe('Phase C independent water billing batches', () => {
  beforeEach(async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(createOwnerPair(aliceDb, aliceUid, aliceEmail));
    await assertSucceeds(createOwnerPair(bobDb, bobUid, bobEmail));
  });

  it('creates, finalizes, and atomically voids an immutable batch', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const batchId = 'water-batch-person-days';
    const reference = waterBillingBatchRef(db, aliceUid, batchId);
    await assertSucceeds(
      setDoc(reference, waterBillingBatchData(batchId)),
    );
    await assertSucceeds(
      updateDoc(reference, {
        status: 'finalized',
        version: 2,
        finalizedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(reference, {
        waterBillCentavos: 1,
        updatedAt: serverTimestamp(),
      }),
    );

    const voidWrite = writeBatch(db);
    voidWrite.update(reference, {
      status: 'voided',
      version: 3,
      voidReason: 'Duplicate provider statement',
      voidedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    voidWrite.set(
      waterBillingBatchVoidRef(db, aliceUid, batchId),
      waterBillingBatchVoidData(batchId),
    );
    await assertSucceeds(voidWrite.commit());
    await assertFails(deleteDoc(reference));
  });

  it('preserves normal selected-boarder decisions through draft edits and finalization', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const id = 'selected-water';
    const reference = waterBillingBatchRef(db, aliceUid, id);
    const decision = {
      boarderId: 'a', boarderName: 'Ana', fullPeriod: true,
      inclusion: 'included', exclusionReason: '', billingRoomId: 'room-a', roomReason: '',
      occupancies: [{ occupancyId: 'oa', roomId: 'room-a', roomName: '201',
        moveIn: '2024-01-01', moveOut: null,
        overlapStart: '2024-01-01', overlapEnd: '2024-02-01' }],
    };
    const normal = {
      method: 'selectedBoarders', allocationSchemaVersion: 1,
      roundingPolicy: 'boarderIdAscending', includedBoarderCount: 1,
      decisions: [decision], totalPersonDays: 31,
      boarderShares: [{ boarderId: 'a', boarderName: 'Ana', occupancyIds: ['oa'],
        roomIds: ['room-a'], occupancyDays: 31, amountCentavos: 120000 }],
      roomAllocations: [{ roomId: 'room-a', roomName: '201', electricityBasisValue: 0,
        occupancyDays: 31, roomChargeCentavos: 120000, allocatedCentavos: 120000,
        unallocatedCentavos: 0, boarderShares: [{ boarderId: 'a', boarderName: 'Ana',
          occupancyIds: ['oa'], occupancyDays: 31, amountCentavos: 120000 }] }],
    };
    await assertSucceeds(setDoc(reference, waterBillingBatchData(id, normal)));
    await assertFails(updateDoc(reference, { includedBoarderCount: 0, version: 2, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(reference, { includedBoarderCount: 2, version: 2, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(reference, { allocationSchemaVersion: 99, version: 2, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(reference, { receiptDate: businessDate('2024-02-10'), version: 2, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(reference, { status: 'finalized', version: 3,
      decisions: [{ ...decision, boarderName: 'Changed during finalization' }],
      finalizedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(reference, { status: 'finalized', version: 3,
      finalizedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    const saved = (await getDoc(reference)).data();
    assert.deepEqual(saved.decisions, [decision]);
    await assertFails(updateDoc(reference, { decisions: [], version: 4, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(reference, { roomAllocations: [], version: 4, updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(reference));
    await assertFails(getDoc(waterBillingBatchRef(authenticatedDb(bobUid, bobEmail), aliceUid, id)));
  });

  it('requires explicit mismatch confirmation for an electricity reference', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const electricityBatchId = 'electricity-june';
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        electricityReadingBatchRef(context.firestore(), aliceUid, electricityBatchId),
        electricityReadingBatchData(electricityBatchId, {
          batchReference: 'EB-2024-06-TEST',
          status: 'finalized',
          effectiveDate: businessDate('2024-06-10'),
          entries: [electricityBatchEntryData({ status: 'recorded' })],
          pendingCount: 0,
          recordedCount: 1,
          totalConsumptionWh: 10000,
          totalChargeCentavos: 12000,
          version: 2,
          finalizedAt: Timestamp.fromDate(new Date('2024-06-10T02:00:00Z')),
          createdAt: Timestamp.fromDate(new Date('2024-06-01T02:00:00Z')),
          updatedAt: Timestamp.fromDate(new Date('2024-06-10T02:00:00Z')),
        }),
      );
    });
    const summer = {
      method: 'electricityPercentage',
      electricityBatchId,
      electricityBatchReference: 'EB-2024-06-TEST',
      electricityMeasurementStart: businessDate('2024-05-10'),
      electricityMeasurementEnd: businessDate('2024-06-10'),
      totalElectricityBasis: 12000,
    };
    await assertFails(
      setDoc(
        waterBillingBatchRef(db, aliceUid, 'water-may-unconfirmed'),
        waterBillingBatchData('water-may-unconfirmed', summer),
      ),
    );
    await assertSucceeds(
      setDoc(
        waterBillingBatchRef(db, aliceUid, 'water-may-confirmed'),
        waterBillingBatchData('water-may-confirmed', {
          ...summer,
          referencePeriodMismatchConfirmed: true,
          referenceExplanation: 'May water statement uses the June meter cycle.',
        }),
      ),
    );
  });

  it('denies cross-owner access and forged ownership', async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    const batchId = 'water-private';
    await assertFails(
      setDoc(
        waterBillingBatchRef(aliceDb, aliceUid, 'forged-water'),
        waterBillingBatchData('forged-water', { createdBy: bobUid }),
      ),
    );
    await assertSucceeds(
      setDoc(
        waterBillingBatchRef(aliceDb, aliceUid, batchId),
        waterBillingBatchData(batchId),
      ),
    );
    await assertFails(getDoc(waterBillingBatchRef(bobDb, aliceUid, batchId)));
  });
});

describe('Phase D combined room utility billing', () => {
  beforeEach(async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(createOwnerPair(aliceDb, aliceUid, aliceEmail));
    await assertSucceeds(createOwnerPair(bobDb, bobUid, bobEmail));
    await seedFinalizedUtilitySources();
  });

  for (const waterMethod of ['personDays', 'selectedBoarders']) {
  it(`finalizes a ${waterMethod} bill and consumes both utility sources atomically`, async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    if (waterMethod === 'selectedBoarders') {
      await testEnvironment.withSecurityRulesDisabled(async (context) => {
        await updateDoc(waterBillingBatchRef(context.firestore(), aliceUid, 'water-source'), {
          method: waterMethod, allocationSchemaVersion: 1,
          roundingPolicy: 'boarderIdAscending', includedBoarderCount: 1,
          decisions: [{ boarderId: 'a', boarderName: 'Ana', fullPeriod: true,
            inclusion: 'included', exclusionReason: '', billingRoomId: 'room-a', roomReason: '',
            occupancies: [{ occupancyId: 'oa', roomId: 'room-a', roomName: '201',
              moveIn: '2024-01-01', moveOut: null,
              overlapStart: '2024-01-01', overlapEnd: '2024-02-01' }] }],
          boarderShares: [{ boarderId: 'a', boarderName: 'Ana', occupancyIds: ['oa'],
            roomIds: ['room-a'], occupancyDays: 31, amountCentavos: 120000 }],
        });
      });
    }
    const billingBatchId = 'utility-bill-1';
    const accountId = `${billingBatchId}_room-a`;
    const batch = writeBatch(db);
    batch.set(
      utilityBillingBatchRef(db, aliceUid, billingBatchId),
      utilityBillingBatchData(billingBatchId, { waterMethod }),
    );
    batch.update(
      electricityReadingBatchRef(db, aliceUid, 'electricity-source'),
      {
        status: 'usedInBilling',
        billingBatchId,
        version: 3,
        usedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      },
    );
    batch.update(waterBillingBatchRef(db, aliceUid, 'water-source'), {
      status: 'usedInBilling',
      billingBatchId,
      version: 3,
      usedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    batch.set(
      utilityRoomBillAccountRef(db, aliceUid, accountId),
      utilityRoomBillAccountData(accountId, billingBatchId),
    );
    await assertSucceeds(batch.commit());

    const saved = await assertSucceeds(
      getDoc(utilityBillingBatchRef(db, aliceUid, billingBatchId)),
    );
    assert.equal(saved.data().totalBilledCentavos, 132000);
    assert.equal(saved.data().waterMethod, waterMethod);
    await assertFails(
      updateDoc(utilityBillingBatchRef(db, aliceUid, billingBatchId), {
        totalBilledCentavos: 1,
      }),
    );
  });
  }

  it('rejects non-atomic finalization and duplicate source consumption', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertFails(
      setDoc(
        utilityBillingBatchRef(db, aliceUid, 'not-atomic'),
        utilityBillingBatchData('not-atomic'),
      ),
    );

    const billingBatchId = 'utility-bill-used';
    const first = writeBatch(db);
    first.set(
      utilityBillingBatchRef(db, aliceUid, billingBatchId),
      utilityBillingBatchData(billingBatchId),
    );
    first.update(
      electricityReadingBatchRef(db, aliceUid, 'electricity-source'),
      {
        status: 'usedInBilling',
        billingBatchId,
        version: 3,
        usedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      },
    );
    first.update(waterBillingBatchRef(db, aliceUid, 'water-source'), {
      status: 'usedInBilling',
      billingBatchId,
      version: 3,
      usedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    first.set(
      utilityRoomBillAccountRef(db, aliceUid, `${billingBatchId}_room-a`),
      utilityRoomBillAccountData(`${billingBatchId}_room-a`, billingBatchId),
    );
    await assertSucceeds(first.commit());
    await assertFails(
      setDoc(
        utilityBillingBatchRef(db, aliceUid, 'duplicate-bill'),
        utilityBillingBatchData('duplicate-bill'),
      ),
    );
  });

  it('denies forged totals and cross-owner reads', async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertFails(
      setDoc(
        utilityBillingBatchRef(aliceDb, aliceUid, 'forged-total'),
        utilityBillingBatchData('forged-total', {
          totalBilledCentavos: 1,
        }),
      ),
    );
    await assertFails(
      getDoc(utilityBillingBatchRef(bobDb, aliceUid, 'forged-total')),
    );
  });
});

describe('Phase E utility room payments', () => {
  beforeEach(async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(createOwnerPair(aliceDb, aliceUid, aliceEmail));
    await assertSucceeds(createOwnerPair(bobDb, bobUid, bobEmail));
    await seedFinalizedUtilitySources();
    await assertSucceeds(createUtilityBill(aliceDb, aliceUid));
  });

  it('records a partial payment with its account update atomically', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const billingBatchId = 'utility-bill-1';
    const accountId = `${billingBatchId}_room-a`;
    const paymentId = 'utility-payment-1';
    const batch = writeBatch(db);
    batch.set(
      utilityRoomPaymentRef(db, aliceUid, paymentId),
      utilityRoomPaymentData(paymentId, billingBatchId),
    );
    batch.update(utilityRoomBillAccountRef(db, aliceUid, accountId), {
      totalPaidCentavos: 50000,
      lastPaymentId: paymentId,
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());

    const account = await assertSucceeds(
      getDoc(utilityRoomBillAccountRef(db, aliceUid, accountId)),
    );
    assert.equal(account.data().totalPaidCentavos, 50000);
    await assertFails(
      updateDoc(utilityRoomPaymentRef(db, aliceUid, paymentId), {
        amountCentavos: 1,
      }),
    );
  });

  it('rejects standalone writes and payments above the room balance', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const billingBatchId = 'utility-bill-1';
    const accountId = `${billingBatchId}_room-a`;
    await assertFails(
      setDoc(
        utilityRoomPaymentRef(db, aliceUid, 'standalone-payment'),
        utilityRoomPaymentData('standalone-payment', billingBatchId),
      ),
    );
    await assertFails(
      updateDoc(utilityRoomBillAccountRef(db, aliceUid, accountId), {
        totalPaidCentavos: 50000,
        lastPaymentId: 'missing-payment',
        updatedAt: serverTimestamp(),
      }),
    );

    const paymentId = 'overpayment';
    const overpay = writeBatch(db);
    overpay.set(
      utilityRoomPaymentRef(db, aliceUid, paymentId),
      utilityRoomPaymentData(paymentId, billingBatchId, {
        amountCentavos: 132001,
      }),
    );
    overpay.update(utilityRoomBillAccountRef(db, aliceUid, accountId), {
      totalPaidCentavos: 132001,
      lastPaymentId: paymentId,
      updatedAt: serverTimestamp(),
    });
    await assertFails(overpay.commit());
  });

  it('prevents another owner from reading utility payment records', async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    const billingBatchId = 'utility-bill-1';
    const accountId = `${billingBatchId}_room-a`;
    const paymentId = 'private-payment';
    const batch = writeBatch(aliceDb);
    batch.set(
      utilityRoomPaymentRef(aliceDb, aliceUid, paymentId),
      utilityRoomPaymentData(paymentId, billingBatchId),
    );
    batch.update(utilityRoomBillAccountRef(aliceDb, aliceUid, accountId), {
      totalPaidCentavos: 50000,
      lastPaymentId: paymentId,
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
    await assertFails(
      getDoc(utilityRoomPaymentRef(bobDb, aliceUid, paymentId)),
    );
  });
});

describe('Phase F finalized utility regression', () => {
  beforeEach(async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(createOwnerPair(aliceDb, aliceUid, aliceEmail));
    await assertSucceeds(createOwnerPair(bobDb, bobUid, bobEmail));
    await seedFinalizedUtilitySources();
    await assertSucceeds(createUtilityBill(aliceDb, aliceUid));
  });

  it('keeps the final bill, room account, and consumed sources immutable', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const billingBatchId = 'utility-bill-1';
    const accountId = `${billingBatchId}_room-a`;

    await assertFails(
      updateDoc(utilityBillingBatchRef(db, aliceUid, billingBatchId), {
        totalBilledCentavos: 1,
      }),
    );
    await assertFails(
      deleteDoc(utilityBillingBatchRef(db, aliceUid, billingBatchId)),
    );
    await assertFails(
      updateDoc(utilityRoomBillAccountRef(db, aliceUid, accountId), {
        totalChargesCentavos: 1,
      }),
    );
    await assertFails(
      deleteDoc(utilityRoomBillAccountRef(db, aliceUid, accountId)),
    );
    await assertFails(
      updateDoc(
        electricityReadingBatchRef(db, aliceUid, 'electricity-source'),
        { totalChargeCentavos: 1 },
      ),
    );
    await assertFails(
      updateDoc(waterBillingBatchRef(db, aliceUid, 'water-source'), {
        waterBillCentavos: 1,
      }),
    );
  });

  it('keeps the complete finalized graph private to its owner', async () => {
    const bobDb = authenticatedDb(bobUid, bobEmail);
    const billingBatchId = 'utility-bill-1';
    await assertFails(
      getDoc(utilityBillingBatchRef(bobDb, aliceUid, billingBatchId)),
    );
    await assertFails(
      getDoc(
        utilityRoomBillAccountRef(
          bobDb,
          aliceUid,
          `${billingBatchId}_room-a`,
        ),
      ),
    );
    await assertFails(
      getDoc(
        electricityReadingBatchRef(
          bobDb,
          aliceUid,
          'electricity-source',
        ),
      ),
    );
    await assertFails(
      getDoc(waterBillingBatchRef(bobDb, aliceUid, 'water-source')),
    );
  });
});

describe('Phase 5 rent settings', () => {
  beforeEach(async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(createOwnerPair(aliceDb, aliceUid, aliceEmail));
    await assertSucceeds(createOwnerPair(bobDb, bobUid, bobEmail));
  });

  it('allows the owner to create and update a valid rent policy', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      setDoc(rentSettingsRef(db, aliceUid), rentSettingsData()),
    );
    await assertSucceeds(
      updateDoc(rentSettingsRef(db, aliceUid), {
        mode: 'perRoom',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('denies malformed settings, cross-owner access, and deletion', async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertFails(
      setDoc(
        rentSettingsRef(aliceDb, aliceUid),
        rentSettingsData({ mode: 'perBed' }),
      ),
    );
    await assertSucceeds(
      setDoc(rentSettingsRef(aliceDb, aliceUid), rentSettingsData()),
    );
    await assertFails(getDoc(rentSettingsRef(bobDb, aliceUid)));
    await assertFails(
      updateDoc(rentSettingsRef(bobDb, aliceUid), {
        mode: 'disabled',
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(deleteDoc(rentSettingsRef(aliceDb, aliceUid)));
  });
});

describe('Phase 5 immutable rent billing records', () => {
  beforeEach(async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(createOwnerPair(aliceDb, aliceUid, aliceEmail));
    await assertSucceeds(createOwnerPair(bobDb, bobUid, bobEmail));
  });

  it('creates a reconciled record once', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const recordId = '2024-01-01_2024-02-01';
    await assertSucceeds(
      setDoc(
        rentBillingRecordRef(db, aliceUid, recordId),
        rentBillingRecordData(recordId),
      ),
    );
    await assertSucceeds(getDoc(rentBillingRecordRef(db, aliceUid, recordId)));
    await assertFails(
      setDoc(
        rentBillingRecordRef(db, aliceUid, recordId),
        rentBillingRecordData(recordId),
      ),
    );
  });

  it('enforces disabled-rent and total reconciliation constraints', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      setDoc(
        rentBillingRecordRef(db, aliceUid, 'disabled-valid'),
        rentBillingRecordData('disabled-valid', {
          mode: 'disabled',
          totalRentCentavos: 0,
          totalAdjustmentCentavos: 5000,
          grandTotalCentavos: 5000,
        }),
      ),
    );
    await assertFails(
      setDoc(
        rentBillingRecordRef(db, aliceUid, 'disabled-with-rent'),
        rentBillingRecordData('disabled-with-rent', {
          mode: 'disabled',
        }),
      ),
    );
    await assertFails(
      setDoc(
        rentBillingRecordRef(db, aliceUid, 'bad-total'),
        rentBillingRecordData('bad-total', { grandTotalCentavos: 300001 }),
      ),
    );
  });

  it('denies forged owners, cross-owner access, mutation, and deletion', async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    const recordId = 'rent-2024-01';
    await assertFails(
      setDoc(
        rentBillingRecordRef(aliceDb, aliceUid, 'forged-owner'),
        rentBillingRecordData('forged-owner', { createdBy: bobUid }),
      ),
    );
    await assertSucceeds(
      setDoc(
        rentBillingRecordRef(aliceDb, aliceUid, recordId),
        rentBillingRecordData(recordId),
      ),
    );
    await assertFails(getDoc(rentBillingRecordRef(bobDb, aliceUid, recordId)));
    await assertFails(
      updateDoc(rentBillingRecordRef(aliceDb, aliceUid, recordId), {
        grandTotalCentavos: 1,
      }),
    );
    await assertFails(
      deleteDoc(rentBillingRecordRef(aliceDb, aliceUid, recordId)),
    );
  });
});

describe('Phase A fixed rent cycles', () => {
  beforeEach(async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(createOwnerPair(aliceDb, aliceUid, aliceEmail));
    await assertSucceeds(createOwnerPair(bobDb, bobUid, bobEmail));
    await seedRentOccupancy(aliceUid);
  });

  it('creates an immutable agreement from the matching occupancy', async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(
      setDoc(
        rentAgreementRef(aliceDb, aliceUid, 'occupancy-rent'),
        rentAgreementData('occupancy-rent'),
      ),
    );
    await assertFails(
      updateDoc(rentAgreementRef(aliceDb, aliceUid, 'occupancy-rent'), {
        monthlyRentCentavos: 1,
      }),
    );
    await assertFails(
      getDoc(rentAgreementRef(bobDb, aliceUid, 'occupancy-rent')),
    );
  });

  it('requires cycle and zeroed control to be created atomically', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      setDoc(
        rentAgreementRef(db, aliceUid, 'occupancy-rent'),
        rentAgreementData('occupancy-rent'),
      ),
    );
    await assertFails(
      setDoc(
        rentCycleRef(db, aliceUid, 'standalone-cycle'),
        rentCycleData('standalone-cycle'),
      ),
    );
    await assertSucceeds(createRentCycle(db, aliceUid));
    await assertFails(
      updateDoc(rentCycleRef(db, aliceUid, 'occupancy-rent_1'), {
        amountCentavos: 1,
      }),
    );
  });

  it('records partial payment only with the matching control update', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const cycleId = 'occupancy-rent_1';
    const paymentId = 'rent-payment-1';
    await assertSucceeds(
      setDoc(
        rentAgreementRef(db, aliceUid, 'occupancy-rent'),
        rentAgreementData('occupancy-rent'),
      ),
    );
    await assertSucceeds(createRentCycle(db, aliceUid, cycleId));
    await assertFails(
      setDoc(
        rentPaymentRef(db, aliceUid, paymentId),
        rentPaymentData(paymentId, cycleId),
      ),
    );
    const batch = writeBatch(db);
    batch.set(
      rentPaymentRef(db, aliceUid, paymentId),
      rentPaymentData(paymentId, cycleId),
    );
    batch.update(rentCycleControlRef(db, aliceUid, cycleId), {
      totalPaidCentavos: 100000,
      lastPaymentId: paymentId,
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
    await assertFails(
      updateDoc(rentPaymentRef(db, aliceUid, paymentId), {
        amountCentavos: 1,
      }),
    );
  });

  it('records a waiver once and never creates an automatic charge', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await seedRentOccupancy(aliceUid, {
      moveOutDate: businessDate('2024-07-15'),
    });
    await assertSucceeds(
      setDoc(
        rentAgreementRef(db, aliceUid, 'occupancy-rent'),
        rentAgreementData('occupancy-rent'),
      ),
    );
    const resolution = {
      resolutionId: 'occupancy-rent',
      agreementId: 'occupancy-rent',
      occupancyId: 'occupancy-rent',
      boarderId: 'boarder-rent',
      roomId: 'room-rent',
      extraStayStart: businessDate('2024-07-10'),
      moveOutDate: businessDate('2024-07-15'),
      decision: 'waived',
      amountCentavos: 0,
      note: 'Allowed five extra days without charge.',
      chargeCycleId: null,
      createdBy: aliceUid,
      createdAt: serverTimestamp(),
    };
    await assertSucceeds(
      setDoc(
        rentExtraStayResolutionRef(db, aliceUid, 'occupancy-rent'),
        resolution,
      ),
    );
    await assertFails(
      deleteDoc(
        rentExtraStayResolutionRef(db, aliceUid, 'occupancy-rent'),
      ),
    );
  });

  it('creates one immutable manual extra-stay charge with its decision', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const agreementId = 'occupancy-rent';
    const chargeCycleId = `${agreementId}_extra`;
    await seedRentOccupancy(aliceUid, {
      moveOutDate: businessDate('2024-07-15'),
    });
    await assertSucceeds(
      setDoc(
        rentAgreementRef(db, aliceUid, agreementId),
        rentAgreementData(agreementId),
      ),
    );
    const resolution = {
      resolutionId: agreementId,
      agreementId,
      occupancyId: agreementId,
      boarderId: 'boarder-rent',
      roomId: 'room-rent',
      extraStayStart: businessDate('2024-07-10'),
      moveOutDate: businessDate('2024-07-15'),
      decision: 'manualCharge',
      amountCentavos: 50000,
      note: 'Agreed charge for five extra days.',
      chargeCycleId,
      createdBy: aliceUid,
      createdAt: serverTimestamp(),
    };

    await assertFails(
      setDoc(
        rentExtraStayResolutionRef(db, aliceUid, agreementId),
        resolution,
      ),
    );

    const batch = writeBatch(db);
    batch.set(
      rentCycleRef(db, aliceUid, chargeCycleId),
      rentCycleData(chargeCycleId, {
        kind: 'extraStay',
        cycleNumber: 2,
        coverageStart: businessDate('2024-07-10'),
        coverageEndExclusive: businessDate('2024-07-15'),
        dueDate: businessDate('2024-07-15'),
        amountCentavos: 50000,
      }),
    );
    batch.set(
      rentCycleControlRef(db, aliceUid, chargeCycleId),
      rentCycleControlData(chargeCycleId),
    );
    batch.set(
      rentExtraStayResolutionRef(db, aliceUid, agreementId),
      resolution,
    );
    await assertSucceeds(batch.commit());

    await assertFails(
      updateDoc(rentCycleRef(db, aliceUid, chargeCycleId), {
        amountCentavos: 1,
      }),
    );
    await assertFails(
      updateDoc(
        rentExtraStayResolutionRef(db, aliceUid, agreementId),
        { note: 'Changed later.' },
      ),
    );
    await assertFails(
      setDoc(
        rentExtraStayResolutionRef(db, aliceUid, agreementId),
        resolution,
      ),
    );
  });
});

describe('Phase 6 immutable monthly billing cycles', () => {
  beforeEach(async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    await assertSucceeds(createOwnerPair(aliceDb, aliceUid, aliceEmail));
    await assertSucceeds(createOwnerPair(bobDb, bobUid, bobEmail));
    await createMonthlySources(aliceDb, aliceUid);
  });

  it('atomically finalizes one cycle with its control and boarder account', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const cycleId = '2024-01-01_2024-02-01_v1';
    await assertSucceeds(createMonthlyCycle(db, aliceUid));
    await assertSucceeds(getDoc(monthlyBillingCycleRef(db, aliceUid, cycleId)));
    await assertSucceeds(getDoc(billingCycleControlRef(db, aliceUid, cycleId)));
    await assertFails(
      updateDoc(monthlyBillingCycleRef(db, aliceUid, cycleId), {
        totalBilledCentavos: 1,
      }),
    );
    await assertFails(deleteDoc(monthlyBillingCycleRef(db, aliceUid, cycleId)));
  });

  it('rejects mismatched source totals and standalone period writes', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const periodId = 'bad-period';
    const cycleId = 'bad-period_v1';
    const batch = writeBatch(db);
    batch.set(
      billingPeriodRef(db, aliceUid, periodId),
      billingPeriodData(periodId, cycleId),
    );
    batch.set(
      monthlyBillingCycleRef(db, aliceUid, cycleId),
      monthlyBillingCycleData(cycleId, periodId, {
        electricityTotalCentavos: 1,
        totalBilledCentavos: 420001,
      }),
    );
    batch.set(
      billingCycleControlRef(db, aliceUid, cycleId),
      billingCycleControlData(cycleId, {
        totalBilledCentavos: 420001,
        outstandingCentavos: 420001,
      }),
    );
    await assertFails(batch.commit());
    await assertFails(
      setDoc(
        billingPeriodRef(db, aliceUid, 'standalone'),
        billingPeriodData('standalone', 'missing_v1'),
      ),
    );
  });

  it('denies cross-owner reads and all cycle deletion', async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    const cycleId = '2024-01-01_2024-02-01_v1';
    await assertSucceeds(createMonthlyCycle(aliceDb, aliceUid));
    await assertFails(
      getDoc(monthlyBillingCycleRef(bobDb, aliceUid, cycleId)),
    );
    await assertFails(
      deleteDoc(billingCycleControlRef(aliceDb, aliceUid, cycleId)),
    );
    await assertFails(
      deleteDoc(
        boarderBillAccountRef(
          aliceDb,
          aliceUid,
          `${cycleId}_boarder-a`,
        ),
      ),
    );
  });

  it('voids an unpaid cycle and reissues a versioned replacement', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const periodId = '2024-01-01_2024-02-01';
    const oldCycleId = `${periodId}_v1`;
    const newCycleId = `${periodId}_v2`;
    await assertSucceeds(createMonthlyCycle(db, aliceUid));

    const voidBatch = writeBatch(db);
    voidBatch.update(billingCycleControlRef(db, aliceUid, oldCycleId), {
      state: 'voided',
      voidReason: 'Correct source record',
      voidedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    voidBatch.update(billingPeriodRef(db, aliceUid, periodId), {
      activeCycleId: null,
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(voidBatch.commit());

    const reissue = writeBatch(db);
    reissue.set(
      monthlyBillingCycleRef(db, aliceUid, newCycleId),
      monthlyBillingCycleData(newCycleId, periodId, {
        version: 2,
        replacesCycleId: oldCycleId,
      }),
    );
    reissue.set(
      billingCycleControlRef(db, aliceUid, newCycleId),
      billingCycleControlData(newCycleId),
    );
    const newAccountId = `${newCycleId}_boarder-a`;
    reissue.set(
      boarderBillAccountRef(db, aliceUid, newAccountId),
      boarderBillAccountData(newAccountId, newCycleId, 'boarder-a'),
    );
    reissue.update(billingCycleControlRef(db, aliceUid, oldCycleId), {
      reissuedAsCycleId: newCycleId,
      updatedAt: serverTimestamp(),
    });
    reissue.update(billingPeriodRef(db, aliceUid, periodId), {
      activeCycleId: newCycleId,
      latestCycleId: newCycleId,
      latestVersion: 2,
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(reissue.commit());
  });
});

describe('Phase 6 append-only payment ledger', () => {
  beforeEach(async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(createOwnerPair(db, aliceUid, aliceEmail));
    await createMonthlySources(db, aliceUid);
    await assertSucceeds(createMonthlyCycle(db, aliceUid));
  });

  it('records a partial payment with matching account and cycle totals', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const cycleId = '2024-01-01_2024-02-01_v1';
    const accountId = `${cycleId}_boarder-a`;
    const paymentId = 'payment-1';
    const batch = writeBatch(db);
    batch.set(
      paymentRef(db, aliceUid, paymentId),
      paymentData(paymentId, cycleId, accountId),
    );
    batch.update(boarderBillAccountRef(db, aliceUid, accountId), {
      totalPaidCentavos: 100000,
      lastPaymentId: paymentId,
      updatedAt: serverTimestamp(),
    });
    batch.update(billingCycleControlRef(db, aliceUid, cycleId), {
      totalPaidCentavos: 100000,
      outstandingCentavos: 428000,
      lastPaymentId: paymentId,
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
    await assertSucceeds(getDoc(paymentRef(db, aliceUid, paymentId)));
  });

  it('rejects direct balance edits, overpayment, and payment mutation', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const cycleId = '2024-01-01_2024-02-01_v1';
    const accountId = `${cycleId}_boarder-a`;
    await assertFails(
      updateDoc(boarderBillAccountRef(db, aliceUid, accountId), {
        totalPaidCentavos: 1,
        lastPaymentId: 'missing',
        updatedAt: serverTimestamp(),
      }),
    );

    const paymentId = 'overpayment';
    const batch = writeBatch(db);
    batch.set(
      paymentRef(db, aliceUid, paymentId),
      paymentData(paymentId, cycleId, accountId, {
        amountCentavos: 528001,
      }),
    );
    batch.update(boarderBillAccountRef(db, aliceUid, accountId), {
      totalPaidCentavos: 528001,
      lastPaymentId: paymentId,
      updatedAt: serverTimestamp(),
    });
    batch.update(billingCycleControlRef(db, aliceUid, cycleId), {
      totalPaidCentavos: 528001,
      outstandingCentavos: -1,
      lastPaymentId: paymentId,
      updatedAt: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });
});

describe('room billing and room payment ledger', () => {
  beforeEach(async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(createOwnerPair(db, aliceUid, aliceEmail));
    await createRoomMonthlySources(db, aliceUid);
  });

  it('atomically creates an immutable room cycle and records a partial payment', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const { cycleId, accountId } = await createRoomMonthlyCycle(db, aliceUid);
    await assertSucceeds(getDoc(roomBillingCycleRef(db, aliceUid, cycleId)));
    await assertFails(
      updateDoc(roomBillingCycleRef(db, aliceUid, cycleId), {
        totalBilledCentavos: 1,
      }),
    );

    const paymentId = 'room-payment-1';
    const paymentBatch = writeBatch(db);
    paymentBatch.set(
      roomPaymentRef(db, aliceUid, paymentId),
      roomPaymentData(paymentId, cycleId, accountId),
    );
    paymentBatch.update(roomBillAccountRef(db, aliceUid, accountId), {
      totalPaidCentavos: 100000,
      lastPaymentId: paymentId,
      updatedAt: serverTimestamp(),
    });
    paymentBatch.update(roomBillingControlRef(db, aliceUid, cycleId), {
      totalPaidCentavos: 100000,
      outstandingCentavos: 128000,
      lastPaymentId: paymentId,
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(paymentBatch.commit());
    await assertFails(
      updateDoc(roomPaymentRef(db, aliceUid, paymentId), {
        amountCentavos: 1,
      }),
    );
  });

  it('rejects forged source totals, rent, and standalone room balances', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const periodId = 'forged-room-period';
    const cycleId = `${periodId}_room_v1`;
    const batch = writeBatch(db);
    batch.set(
      roomBillingPeriodRef(db, aliceUid, periodId),
      billingPeriodData(periodId, cycleId),
    );
    batch.set(
      roomBillingCycleRef(db, aliceUid, cycleId),
      roomBillingCycleData(cycleId, periodId, {
        electricityTotalCentavos: 1,
        totalBilledCentavos: 120001,
      }),
    );
    batch.set(
      roomBillingControlRef(db, aliceUid, cycleId),
      billingCycleControlData(cycleId, {
        totalBilledCentavos: 120001,
        outstandingCentavos: 120001,
      }),
    );
    await assertFails(batch.commit());

    const rentPeriodId = 'rent-room-period';
    const rentCycleId = `${rentPeriodId}_room_v1`;
    const rentBatch = writeBatch(db);
    rentBatch.set(
      roomBillingPeriodRef(db, aliceUid, rentPeriodId),
      billingPeriodData(rentPeriodId, rentCycleId),
    );
    rentBatch.set(
      roomBillingCycleRef(db, aliceUid, rentCycleId),
      roomBillingCycleData(rentCycleId, rentPeriodId, {
        rentRecordId: 'rent-room-month',
        rentTotalCentavos: 310000,
        totalBilledCentavos: 538000,
        statements: [{ roomId: 'room-a', currentChargesCentavos: 538000 }],
      }),
    );
    rentBatch.set(
      roomBillingControlRef(db, aliceUid, rentCycleId),
      billingCycleControlData(rentCycleId, {
        totalBilledCentavos: 538000,
        outstandingCentavos: 538000,
      }),
    );
    await assertFails(rentBatch.commit());

    await assertFails(
      setDoc(
        roomBillAccountRef(db, aliceUid, 'standalone_room-a'),
        roomBillAccountData('standalone_room-a', 'standalone'),
      ),
    );
  });
});

describe('Phase B electricity reading batches', () => {
  beforeEach(async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(createOwnerPair(db, aliceUid, aliceEmail));
  });

  it('allows the owner to create a valid draft and hides it from another owner', async () => {
    const aliceDb = authenticatedDb(aliceUid, aliceEmail);
    const bobDb = authenticatedDb(bobUid, bobEmail);
    const batchId = 'batch-draft-1';
    await assertSucceeds(
      setDoc(
        electricityReadingBatchRef(aliceDb, aliceUid, batchId),
        electricityReadingBatchData(batchId),
      ),
    );
    await assertSucceeds(
      getDoc(electricityReadingBatchRef(aliceDb, aliceUid, batchId)),
    );
    await assertFails(
      getDoc(electricityReadingBatchRef(bobDb, aliceUid, batchId)),
    );
  });

  it('accepts a batch reading only with its meter, link, and batch update', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const batchId = 'batch-atomic-1';
    const openingDate = businessDate('2024-01-01');
    const readingDate = businessDate('2024-02-01');
    await assertSucceeds(createRoom(db, aliceUid, 'room-a'));
    await assertSucceeds(
      installInitialMeter(db, aliceUid, {
        roomId: 'room-a',
        meterId: 'meter-a',
        readingId: 'reading-open',
        readingDate: openingDate,
        readingWh: 100000,
      }),
    );
    await assertSucceeds(
      setDoc(
        electricityReadingBatchRef(db, aliceUid, batchId),
        electricityReadingBatchData(batchId, {
          entries: [electricityBatchEntryData()],
        }),
      ),
    );

    const atomic = writeBatch(db);
    atomic.set(
      meterReadingRef(db, aliceUid, 'reading-batch'),
      meterReadingData(
        'reading-batch',
        'meter-a',
        'room-a',
        1,
        readingDate,
        110000,
        {
          kind: 'regular',
          previousReadingId: 'reading-open',
          previousReadingDate: openingDate,
          previousReadingWh: 100000,
          consumptionWh: 10000,
          note: 'Electricity batch EB-2024-02-01-TEST',
        },
      ),
    );
    atomic.update(electricityMeterRef(db, aliceUid, 'meter-a'), {
      lastReadingId: 'reading-batch',
      lastReadingDate: readingDate,
      lastReadingWh: 110000,
      updatedAt: serverTimestamp(),
    });
    atomic.set(
      electricityBatchReadingLinkRef(db, aliceUid, 'reading-batch'),
      electricityBatchReadingLinkData(batchId),
    );
    atomic.update(electricityReadingBatchRef(db, aliceUid, batchId), {
      entries: [
        electricityBatchEntryData({
          status: 'recorded',
          readingId: 'reading-batch',
        }),
      ],
      pendingCount: 0,
      recordedCount: 1,
      totalConsumptionWh: 10000,
      totalChargeCentavos: 12000,
      version: 2,
      lastLinkId: 'reading-batch',
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(atomic.commit());

    await assertFails(
      updateDoc(
        electricityBatchReadingLinkRef(db, aliceUid, 'reading-batch'),
        { chargeCentavos: 1 },
      ),
    );
  });

  it('rejects incomplete finalization and immutable identity changes', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const batchId = 'batch-draft-2';
    const reference = electricityReadingBatchRef(db, aliceUid, batchId);
    await assertSucceeds(
      setDoc(reference, electricityReadingBatchData(batchId)),
    );
    await assertFails(
      updateDoc(reference, {
        status: 'finalized',
        version: 2,
        finalizedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(reference, {
        batchReference: 'FORGED-REFERENCE',
        version: 2,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(deleteDoc(reference));
  });

  it('requires an immutable audit record to void a finalized batch', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const batchId = 'batch-finalized-1';
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await setDoc(
        electricityReadingBatchRef(adminDb, aliceUid, batchId),
        electricityReadingBatchData(batchId, {
          status: 'finalized',
          pendingCount: 0,
          recordedCount: 1,
          version: 1,
          finalizedAt: Timestamp.fromDate(
            new Date('2024-02-01T10:01:00+08:00'),
          ),
          createdAt: Timestamp.fromDate(
            new Date('2024-02-01T10:00:00+08:00'),
          ),
          updatedAt: Timestamp.fromDate(
            new Date('2024-02-01T10:01:00+08:00'),
          ),
        }),
      );
    });

    await assertFails(
      updateDoc(electricityReadingBatchRef(db, aliceUid, batchId), {
        status: 'voided',
        version: 2,
        voidReason: 'Duplicate batch entered by mistake',
        voidedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );

    const batch = writeBatch(db);
    batch.update(electricityReadingBatchRef(db, aliceUid, batchId), {
      status: 'voided',
      version: 2,
      voidReason: 'Duplicate batch entered by mistake',
      voidedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    batch.set(
      electricityBatchVoidRef(db, aliceUid, batchId),
      electricityBatchVoidData(batchId),
    );
    await assertSucceeds(batch.commit());
    await assertFails(
      updateDoc(electricityBatchVoidRef(db, aliceUid, batchId), {
        reason: 'Changed later',
      }),
    );
    await assertFails(
      deleteDoc(electricityBatchVoidRef(db, aliceUid, batchId)),
    );
  });
});

describe('Manila business-date rule regression', () => {
  beforeEach(async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(createOwnerPair(db, aliceUid, aliceEmail));
    await assertSucceeds(createRoom(db, aliceUid, 'room-a'));
    await assertSucceeds(createRoom(db, aliceUid, 'room-b'));
  });

  it('accepts Manila today and rejects tomorrow for occupancy dates', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(
      createAssignedBoarder(db, aliceUid, {
        boarderId: 'today-boarder',
        occupancyId: 'today-occupancy',
        roomId: 'room-a',
        moveInDate: manilaDateFromNow(),
      }),
    );
    await assertFails(
      createAssignedBoarder(db, aliceUid, {
        boarderId: 'tomorrow-boarder',
        occupancyId: 'tomorrow-occupancy',
        roomId: 'room-b',
        moveInDate: manilaDateFromNow(1),
      }),
    );
  });
});

describe('destructive and undeclared operations', () => {
  beforeEach(async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    await assertSucceeds(createOwnerPair(db, aliceUid, aliceEmail));
  });

  it('denies deleting the profile or primary house', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);

    await assertFails(deleteDoc(profileRef(db, aliceUid)));
    await assertFails(deleteDoc(primaryHouseRef(db, aliceUid)));
  });

  it('denies writes to undeclared future subcollections', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const futureRecordRef = doc(
      db,
      'owners',
      aliceUid,
      'boardingHouses',
      'primary',
      'futureRecords',
      'future-record-1',
    );

    await assertFails(
      setDoc(futureRecordRef, {
        amountCentavos: 10000,
        createdAt: serverTimestamp(),
      }),
    );
    await assertFails(getDoc(futureRecordRef));
  });

  it('denies arbitrary top-level documents', async () => {
    const db = authenticatedDb(aliceUid, aliceEmail);
    const auditRef = doc(db, 'auditLogs', 'forged-entry');

    await assertFails(setDoc(auditRef, { ownerUid: aliceUid }));
    await assertFails(getDoc(auditRef));
  });
});
