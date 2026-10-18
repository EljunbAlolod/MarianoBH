import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const args = new Map(
  process.argv.slice(2).map((argument) => {
    const [key, ...value] = argument.split('=');
    return [key, value.join('=')];
  }),
);
const apply = args.has('--apply');
const projectId = args.get('--project') || process.env.GCLOUD_PROJECT;
const onlyOwner = args.get('--owner') || null;

if (!projectId) {
  throw new Error(
    'Provide --project=<firebase-project-id>. The script defaults to a dry run.',
  );
}

initializeApp({
  projectId,
  ...(process.env.FIRESTORE_EMULATOR_HOST
    ? {}
    : { credential: applicationDefault() }),
});
const db = getFirestore();

function fail(message) {
  throw new Error(message);
}

function sameTimestamp(left, right) {
  return left instanceof Timestamp &&
    right instanceof Timestamp &&
    left.isEqual(right);
}

function sameStringSet(left, right) {
  return Array.isArray(left) &&
    left.length === right.size &&
    left.every((value) => typeof value === 'string' && right.has(value));
}

function addExpectedSource(expected, candidate, label) {
  const existing = expected.get(candidate.readingId);
  if (existing) {
    const consistent = existing.roomId === candidate.roomId &&
      existing.meterId === candidate.meterId &&
      existing.readingWh === candidate.readingWh &&
      sameTimestamp(existing.readingDate, candidate.readingDate);
    if (!consistent) fail(`${label} repeats a reading with conflicting values.`);
    return;
  }
  expected.set(candidate.readingId, candidate);
}

function expectedSources(record, label) {
  if (!Array.isArray(record.roomCharges)) {
    fail(`${label} has no valid roomCharges array.`);
  }
  const expected = new Map();
  for (const room of record.roomCharges) {
    if (!room || typeof room.roomId !== 'string' || !Array.isArray(room.segments)) {
      fail(`${label} contains a malformed room snapshot.`);
    }
    for (const segment of room.segments) {
      const required = [
        'meterId',
        'previousReadingId',
        'currentReadingId',
        'startDate',
        'endDateExclusive',
        'previousReadingWh',
        'currentReadingWh',
      ];
      if (!segment || required.some((field) => segment[field] == null)) {
        fail(`${label} contains an incomplete meter segment.`);
      }
      addExpectedSource(expected, {
        readingId: segment.previousReadingId,
        roomId: room.roomId,
        meterId: segment.meterId,
        readingDate: segment.startDate,
        readingWh: segment.previousReadingWh,
      }, label);
      addExpectedSource(expected, {
        readingId: segment.currentReadingId,
        roomId: room.roomId,
        meterId: segment.meterId,
        readingDate: segment.endDateExclusive,
        readingWh: segment.currentReadingWh,
      }, label);
    }
  }
  if (expected.size === 0) fail(`${label} has no source meter readings.`);
  if (expected.size > 2000) fail(`${label} exceeds the 2,000-reading limit.`);
  return expected;
}

function correctionMetadataPatch(reading, label) {
  const fields = [
    'correctionCount',
    'lastCorrectionId',
    'lastCorrectedAt',
    'lastCorrectedBy',
  ];
  const present = fields.filter((field) => Object.hasOwn(reading, field));
  if (present.length === 0) {
    return {
      correctionCount: 0,
      lastCorrectionId: null,
      lastCorrectedAt: null,
      lastCorrectedBy: null,
    };
  }
  if (present.length !== fields.length) {
    fail(`${label} has partial correction metadata; repair it manually.`);
  }
  const count = reading.correctionCount;
  const validEmpty = count === 0 &&
    reading.lastCorrectionId == null &&
    reading.lastCorrectedAt == null &&
    reading.lastCorrectedBy == null;
  const validCorrected = Number.isInteger(count) &&
    count > 0 &&
    typeof reading.lastCorrectionId === 'string' &&
    reading.lastCorrectedAt instanceof Timestamp &&
    typeof reading.lastCorrectedBy === 'string';
  if (!validEmpty && !validCorrected) {
    fail(`${label} has inconsistent correction metadata.`);
  }
  return {};
}

async function planOwner(ownerId) {
  const house = db.collection('owners').doc(ownerId)
    .collection('boardingHouses').doc('primary');
  const [billSnapshot, readingSnapshot] = await Promise.all([
    house.collection('electricityBillingRecords').get(),
    house.collection('meterReadings').get(),
  ]);
  const readings = new Map(readingSnapshot.docs.map((doc) => [doc.id, doc]));
  const derivedLocks = new Map(
    readingSnapshot.docs.map((doc) => [doc.id, new Set()]),
  );
  const writes = [];

  for (const billDoc of billSnapshot.docs) {
    const bill = billDoc.data();
    const label = `${ownerId}/electricityBillingRecords/${billDoc.id}`;
    const expected = expectedSources(bill, label);
    for (const source of expected.values()) {
      const readingDoc = readings.get(source.readingId);
      if (!readingDoc) fail(`${label} references missing reading ${source.readingId}.`);
      const reading = readingDoc.data();
      const matches = reading.readingId === source.readingId &&
        reading.roomId === source.roomId &&
        reading.meterId === source.meterId &&
        reading.readingWh === source.readingWh &&
        sameTimestamp(reading.readingDate, source.readingDate);
      if (!matches) {
        fail(`${label} does not match source reading ${source.readingId}.`);
      }
      derivedLocks.get(source.readingId).add(billDoc.id);
    }
    if (!sameStringSet(bill.sourceReadingIds, new Set(expected.keys()))) {
      if (Object.hasOwn(bill, 'sourceReadingIds')) {
        fail(`${label} has sourceReadingIds that disagree with its snapshot.`);
      }
      writes.push({ ref: billDoc.ref, data: { sourceReadingIds: [...expected.keys()].sort() } });
    }
  }

  for (const readingDoc of readingSnapshot.docs) {
    const reading = readingDoc.data();
    const label = `${ownerId}/meterReadings/${readingDoc.id}`;
    const locks = derivedLocks.get(readingDoc.id);
    if (locks.size > 100) fail(`${label} exceeds the 100-bill lock limit.`);
    if (Object.hasOwn(reading, 'billingRecordIds') &&
        !sameStringSet(reading.billingRecordIds, locks)) {
      fail(`${label} has billing locks that disagree with billing snapshots.`);
    }
    const data = correctionMetadataPatch(reading, label);
    if (!Object.hasOwn(reading, 'billingRecordIds')) {
      data.billingRecordIds = [...locks].sort();
    }
    if (Object.keys(data).length > 0) writes.push({ ref: readingDoc.ref, data });
  }

  return {
    ownerId,
    bills: billSnapshot.size,
    readings: readingSnapshot.size,
    writes,
  };
}

const ownerIds = onlyOwner
  ? [onlyOwner]
  : (await db.collection('owners').get()).docs.map((doc) => doc.id);
const plans = [];
for (const ownerId of ownerIds) plans.push(await planOwner(ownerId));
const writes = plans.flatMap((plan) => plan.writes);

for (const plan of plans) {
  console.log(
    `${plan.ownerId}: ${plan.bills} bill(s), ${plan.readings} reading(s), ${plan.writes.length} planned write(s)`,
  );
}
console.log(`${apply ? 'APPLY' : 'DRY RUN'}: ${writes.length} total write(s).`);

if (apply) {
  for (let index = 0; index < writes.length; index += 400) {
    const batch = db.batch();
    for (const write of writes.slice(index, index + 400)) {
      batch.set(write.ref, write.data, { merge: true });
    }
    await batch.commit();
  }
  console.log('Backfill complete. Run a dry run again; it must report 0 writes.');
} else {
  console.log('No data changed. Re-run with --apply only during a maintenance window.');
}
