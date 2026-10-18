# Firebase setup for Phases 1 through 8

This checkout is connected to the `marianobh-fcc1b` Firebase project. Use a
separate production Firebase project before release.

For Android signing, backup/recovery, App Check staging, and the final
physical-phone checklist, also follow [the Phase 8 release runbook](PHASE_8_RELEASE.md).

## 1. Confirm the Android application ID

The current application ID is:

```text
com.marianobh.boarding_house
```

It is defined in `android/app/build.gradle.kts`. Change it before Firebase
registration if a different permanent ID is required. Changing it later means
registering a new Android app in Firebase.

## 2. Create and secure the Firebase project

In the Firebase console:

1. Create or select a development project.
2. Add an Android application using the application ID above.
3. In **Authentication > Sign-in method**, enable **Email/Password**.
4. In **Authentication > Settings**, enable email-enumeration protection.
5. Create a Cloud Firestore database. Choose a region close to the property;
   `asia-southeast1` is a practical regional default if no policy requires a
   different location. A Firestore location cannot be changed later.
6. Do not paste any service-account key into this app.

The app requires users to verify their email before Firestore permits reads or
writes. Customize the sender name and email templates in Authentication before
production use.

## 3. Connect FlutterFire

Install and authenticate the CLIs:

```powershell
npm install --global firebase-tools
firebase login
dart pub global activate flutterfire_cli
```

From the repository root, run:

```powershell
flutterfire configure --project=marianobh-fcc1b --platforms=android --android-package-name=com.marianobh.boarding_house
```

Allow the command to update `lib/firebase_options.dart`. The generated file
contains the public client configuration for the selected project. FlutterFire
also creates `android/app/google-services.json` and updates the Android Gradle
plugins.

The Firebase API key in generated mobile configuration identifies the project;
it is not an administrative secret. Still apply Firebase's recommended API-key
restrictions. Never include a service-account JSON file or private key.

## 4. Deploy the owner-scoped rules

For a new empty Firestore database, associate this folder with the development
project and deploy. For any database that already contains electricity billing
records, complete the meter-reading lock backfill documented below first; the
correction-enabled rules deliberately treat legacy readings as locked.

After that prerequisite is satisfied, deploy:

```powershell
firebase use --add <firebase-project-id>
firebase deploy --only firestore:rules,firestore:indexes
```

The rules permit only a verified owner to access these deterministic paths:

```text
/users/{theirUid}
/owners/{theirUid}/boardingHouses/primary
/owners/{theirUid}/boardingHouses/primary/rooms/{roomId}
/owners/{theirUid}/boardingHouses/primary/boarders/{boarderId}
/owners/{theirUid}/boardingHouses/primary/occupancies/{occupancyId}
/owners/{theirUid}/boardingHouses/primary/roomMeterStates/{roomId}
/owners/{theirUid}/boardingHouses/primary/electricityMeters/{meterId}
/owners/{theirUid}/boardingHouses/primary/meterReadings/{readingId}
/owners/{theirUid}/boardingHouses/primary/meterReadingCorrections/{correctionId}
/owners/{theirUid}/boardingHouses/primary/electricityBillingRecords/{recordId}
/owners/{theirUid}/boardingHouses/primary/waterSettings/config
/owners/{theirUid}/boardingHouses/primary/waterBillingRecords/{recordId}
/owners/{theirUid}/boardingHouses/primary/rentSettings/config
/owners/{theirUid}/boardingHouses/primary/rentBillingRecords/{recordId}
/owners/{theirUid}/boardingHouses/primary/billingPeriods/{periodId}
/owners/{theirUid}/boardingHouses/primary/monthlyBillingCycles/{cycleId}
/owners/{theirUid}/boardingHouses/primary/billingCycleControls/{cycleId}
/owners/{theirUid}/boardingHouses/primary/boarderBillAccounts/{accountId}
/owners/{theirUid}/boardingHouses/primary/payments/{paymentId}
```

Profile and boarding-house documents must be created atomically. Ownership,
currency (`PHP`), timezone (`Asia/Manila`), schema version, and creation time
cannot be changed by the client. Phase 2 lifecycle writes must be atomic: a
move-in updates the boarder, occupancy, and room counter together; a transfer
also closes the previous occupancy; and a move-out keeps the closed history.
Deletes, other owners, and all not-yet-implemented collections are denied.

Phase 3 electricity writes are also owner-scoped and transaction-validated.
Initial setup creates the room meter state, sequence-one meter, and opening
reading as one graph. A normal reading must extend the current sequence with a
later business date and non-decreasing Wh value. Reset, replacement, and
clean-start operations atomically retire the previous sequence and create the
next sequence with a documented reason and closing/opening readings. The latest
active, unbilled reading can be corrected in a separate atomic transaction that
updates the meter head and creates an immutable before/after audit record.
There is no password or MPIN prompt; the app requires a reason and a final
warning/review. Older, billed, inactive-sequence, and legacy unmigrated readings
remain read-only. A billing record is an immutable snapshot whose room,
boarder, adjustment, allocated, unallocated, and overall centavo totals must
reconcile. Saving it also locks every referenced reading in the same
transaction, so billing and correction cannot race.

### Meter-reading lock backfill

Do not deploy the correction-enabled rules over existing production data until
the source-reading and lock backfill has completed. The utility uses Firebase
Admin credentials, validates every billing snapshot against its source
readings, and defaults to a dry run:

```powershell
cd firebase-tests
npm ci
gcloud auth application-default login
npm run migrate:meter-reading-locks -- --project=marianobh-fcc1b
```

Review the counts, put the app in a maintenance window so no bill can be saved
during the migration, then apply explicitly:

```powershell
npm run migrate:meter-reading-locks -- --project=marianobh-fcc1b --apply
npm run migrate:meter-reading-locks -- --project=marianobh-fcc1b
```

The final dry run must report `0 total write(s)` before deploying the new rules.
The script never changes reading dates, meter values, charges, or billing
totals. Do not commit service-account credentials.

Phase 4 water settings and records are owner-scoped. Settings allow one
validated `config` document and preserve its creation time. Water billing
records are create-once snapshots. Person-day records cannot claim an
electricity source. Electricity-percentage records must reference an existing
owner-scoped electricity billing record with the exact same period, and their
stored total basis must equal that source's base charge or consumption total.
Allocated plus unallocated centavos must equal the original water bill.

The current rent flow stores fixed-rent agreements and full anniversary cycles
separately from utilities. A June 10-July 9 period becomes due on July 10.
Rent-cycle payments are append-only and transactionally update their matching
account. Legacy Phase 5 prorated rent snapshots remain immutable for historical
compatibility but are no longer part of current bill creation.

The current utility flow combines independently finalized electricity and
water batches into immutable room statements. Source batches are locked in the
same transaction so they cannot be reused. Room payments are append-only and
must transactionally update the matching room account without overpayment.
Legacy Phase 6 boarder monthly cycles remain protected and readable, but rent
is never included in a newly created room utility bill.

Phase 7 does not add a writable Firestore collection. PDF reports are generated
on the authenticated device from the owner-scoped finalized cycle, referenced
immutable source records, and append-only payment ledger. Generated files are
not uploaded to Firebase automatically and contain no boarder contact numbers
or authentication details.

## 5. Test the rules locally

The rules suite uses the headless Firestore emulator. It never starts an Android
emulator:

```powershell
cd firebase-tests
npm ci
npm run test:rules
```

Tests always use the `demo-boarding-house-manager` project ID, which prevents
the rules test environment from contacting a production Firestore project.

## 6. Run on the personal phone

Install Android SDK Platform-Tools, enable USB debugging, then:

```powershell
flutter devices
flutter run -d <physical-device-id>
```

Use a real inbox to test registration, email verification, and password reset.
Sign in on a second physical phone with the same account to confirm that the UID
resolves the same owner workspace.

No Android emulator is required. For Phases 3 through 8, use the personal phone to set up
a baseline meter, add readings on later dates, exercise the reset/replacement/
clean-start flow, correct the latest unbilled reading after reviewing the final
warning, calculate a multi-boarder period, and reopen the saved read-only
record. Confirm that the audit preserves the prior values and that billed
readings cannot be corrected. Also test large system text, portrait and landscape,
and dark mode. Then calculate water by person-days, save a matching electricity
period and calculate summer water, verify transfers and empty rooms, and reopen
the saved read-only water record. The Firestore Local Emulator Suite used by `npm run test:rules`
is only a headless rules-test process; it is not an Android device emulator.
For rent, verify that a full anniversary period becomes due after the period,
supports partial/final payments, and stays separate from utilities. For room
utility billing, finalize independent electricity and water batches, confirm
the sources cannot be reused, record partial and final room payments, and reject
an overpayment. For reports, preview the room utility summary and an individual
room statement. Use Android's
system print dialog to choose **Save as PDF**, then use the native share sheet
to share the file to Messenger or another supported application. The app does
not automatically choose a group conversation or send on the owner's behalf.

## Release notes

Follow `PHASE_8_RELEASE.md`. Release builds now fail closed without a protected
keystore unless the explicit internal-phone test switch is set. Configure
authorized domains and Firebase email templates, complete a scheduled-backup
recovery drill, and stage Play Integrity App Check before production
enforcement.
