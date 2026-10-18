# Phase 8 release and recovery runbook

Phase 8 hardens the app for owner-only production use without changing the
current billing policy. Rent remains a separate fixed monthly obligation paid
after each anniversary period. Electricity and water are combined into room
utility bills; boarders divide a room bill outside the app.

This runbook separates checks that are safe to perform locally from operations
that change the live Firebase project. It never requires an Android emulator.

## Release status

- Firestore documents are stored below the authenticated owner's UID.
- Firestore rules deny undeclared collections and require a verified email.
- Financial snapshots and audit records are immutable; payments and lifecycle
  controls are stored separately and changed transactionally.
- Firestore disk persistence is intentionally disabled. The app must show a
  retryable connection error instead of pretending that an offline write was
  finalized.
- The repository currently requires no composite Firestore indexes. Keep
  `firestore.indexes.json` deployed so future additions are explicit.
- App Check is not enforced yet. Enabling enforcement before a registered build
  is installed can block the landlady's physical phone.

## 1. Configure secure Android signing

The Gradle build refuses a release build unless real signing credentials are
configured. The one exception is the explicitly named internal-test switch
described below.

Create a private upload keystore once. Android Studio's bundled Java `keytool`
can be used if it is not on `PATH`:

```powershell
keytool -genkey -v -keystore C:\private\marianobh-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias marianobh-upload
```

Copy `android/key.properties.example` to `android/key.properties`, then replace
every placeholder. The actual file and all `*.jks`/`*.keystore` files are
ignored by Git. Store an encrypted backup of the keystore, alias, and passwords
somewhere separate from this computer; losing the upload key can prevent future
updates.

Instead of `key.properties`, a protected build environment may supply:

```text
MARIANOBH_KEYSTORE_PATH
MARIANOBH_KEYSTORE_PASSWORD
MARIANOBH_KEY_ALIAS
MARIANOBH_KEY_PASSWORD
```

Build the production Play artifact only after signing is configured:

```powershell
flutter build appbundle --release
```

For a release-mode APK installed only on the landlady's personal phone, the
debug key may be enabled deliberately for that one terminal session:

```powershell
$env:MARIANOBH_ALLOW_DEBUG_RELEASE='true'
flutter build apk --release
Remove-Item Env:MARIANOBH_ALLOW_DEBUG_RELEASE
```

That APK exercises release-mode behavior but is **not production signed** and
must not be uploaded to Google Play.

## 2. Verify and deploy Firebase safely

Run all local checks before changing the Firebase project:

```powershell
flutter analyze
flutter test
Set-Location firebase-tests
npm ci
npm run test:rules
```

The Firebase Local Emulator Suite in that command tests Firestore rules only;
it is not an Android emulator.

Before the first production deploy, review the selected Firebase project and
complete any required meter-reading lock migration from `FIREBASE_SETUP.md`.
Then deploy rules and indexes together:

```powershell
firebase use <production-project-id>
firebase deploy --only firestore:rules,firestore:indexes
```

Do not run these commands against live data without confirming the project ID
and reviewing the rules diff.

## 3. Backups and recovery

Scheduled Firestore backups are a Firebase/Google Cloud project operation and
may require the Blaze plan. Configure them in the Firebase or Google Cloud
console only after the owner accepts the billing impact. A practical small-app
starting policy is daily backups retained for 14 days plus weekly backups
retained for 12 weeks; adjust this to the property's legal and cost needs.

At least once before launch, perform a recovery drill:

1. Create a backup from the production candidate database.
2. Restore it to a **new test database**, not over the live source.
3. Verify room counts, active occupancies, meter heads, utility batches, rent
   agreements/cycles, room bills, payment totals, and audit records.
4. Record the backup timestamp, restore target, verifier, and outcome.
5. Delete the test database only after the result is documented.

An in-place restore is destructive and cannot be treated as an undo operation.
Never run it without a separate verified backup and explicit owner approval.

## 4. Offline and conflict behavior

Financial finalization is online-only by design. The app must not label a bill,
payment, meter correction, or occupancy mutation as saved until Firestore has
committed it. When connectivity is lost:

- retain the visible form values where the screen already supports it;
- explain that no record was finalized;
- offer a clear retry path after reconnection;
- reload current server values after a transaction conflict; and
- never replace a specific conflict with a generic success message.

Transactions protect meter-head updates, source-batch locks, finalized room
bills, rent payments, and immutable audit creation against concurrent writes.
The same owner signing in on a replacement phone retains access because the UID,
not the device, defines ownership.

## 5. Stage App Check after the phone build is stable

Do not turn on enforcement during initial physical-phone testing. For the
production rollout:

1. Register the Android app for App Check with Play Integrity.
2. Add and initialize the Flutter App Check package in a separate reviewed
   change.
3. Distribute the registered build to the landlady's phone.
4. Monitor App Check metrics for legitimate requests.
5. Enable enforcement only after valid traffic is consistently recognized.

This staged order avoids locking the owner out of Firestore during setup.

## 6. Physical-phone release checklist

Use at least a 375 logical-pixel portrait layout, landscape orientation, dark
mode, and the largest practical system text size.

- Install the candidate APK on the personal phone without an emulator.
- Register, verify email, sign out, reset the password, and sign back in.
- Sign in with the same UID on a second physical phone when available.
- Create and edit a room; move a boarder in, transfer, and move out.
- Record meter baselines/readings and correct only a latest unbilled reading.
- Finalize matching electricity and water batches into room utility bills.
- Confirm source batches cannot be reused and saved snapshots remain unchanged.
- Set up rent and verify June 10-July 9 becomes due on July 10 at full rent.
- Record partial and final payments and verify unpaid/partial/paid states.
- Generate, preview, save, and share both current and historical PDFs.
- Disable the network during a save and confirm a clear retryable failure.
- Confirm Back returns to the previous workflow without losing saved context.
- Recheck loading, empty, error, and disabled states with TalkBack enabled.
- Install the candidate over the previous internal APK and verify existing data.

## 7. Release exit criteria

A production release is ready only when:

- analysis, Flutter tests, and the complete Firestore rules suite pass;
- the physical-phone checklist has no release-blocking defect;
- a recovery drill has succeeded;
- the final Firebase project and rules deployment are confirmed;
- the App Check decision is recorded;
- the version/build number is incremented; and
- the AAB is signed with the protected production upload key.

Keep the test result, Git commit, artifact SHA-256, Firebase project ID, release
date, and installer identity together in the release record.
