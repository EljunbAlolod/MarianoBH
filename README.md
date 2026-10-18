# Boarding House Manager

Android-first Flutter application for a boarding-house owner. This repository
currently contains **Phases 1 through 8**: secure owner access, room and
occupancy management, room-based utilities, fixed anniversary rent, immutable
billing snapshots, append-only payment tracking, shareable PDF reports, and
release/recovery hardening.

## Implemented features

- Material 3 mobile interface with large controls and clear validation
- Firebase email/password registration and sign-in
- Google account sign-in option on the sign-in and registration screens
  (Android and iOS; see [Google sign-in setup](docs/GOOGLE_SIGN_IN_SETUP.md))
- Email verification gate before any boarding-house data can be accessed
- Password recovery with a non-enumerating confirmation message
- Firebase Auth session persistence across app restarts
- Idempotent, transactional creation of one private owner workspace
- GoRouter protection for signed-out, unverified, unconfigured, and offline states
- Home, rooms, boarders, billing, and settings navigation shell
- Logout and replacement-device support through the same Firebase Auth UID
- Room creation, editing, deactivation, reactivation, and exact centavo rent
- Multiple current boarders in the same room
- Boarder contact/notes, moved-out and inactive lifecycle states
- Atomic move-in, move-out, and mid-month room transfers
- Immutable occupancy history using half-open date ranges
- Dated, append-only electricity readings with an automatic previous-reading
  reference and non-negative consumption validation
- Separate reset, replacement, and clean-start meter sequences with a required
  reason, closing reading, and new opening reading
- Room-level meter-reading history with a controlled correction action for the
  latest active, unbilled reading, a final warning/review, required reason, and
  immutable before/after audit history
- Configurable per-period electricity rates and exact integer-only charge math
- Occupancy-day allocation for multiple boarders, including explicit estimated
  and unallocated amounts that always reconcile to the room total
- Documented room surcharges and discounts that never rewrite meter readings
- Immutable electricity billing snapshots containing the rate, readings,
  adjustments, room totals, boarder shares, and calculation warnings
- Landlady-controlled normal water allocation: equal shares among selected
  boarders, occupancy evidence, required exclusion reasons, explicit transfer
  room decisions, and immutable decision snapshots; legacy person-day records
  remain available
- Summer water allocation by each room's percentage of a matching electricity
  record, using either base electricity charge or metered consumption
- Configurable summer months, default method, electricity basis, and whether a
  calculation may override the recommended method
- Immutable water snapshots whose boarder, room, allocated, and unallocated
  centavo totals always reconcile to the original bill
- Fixed full-month rent tracked separately for each boarder and paid after the
  anniversary period (for example, June 10-July 9 is due July 10)
- Independent rent and room-utility balances with unpaid, partially paid, and
  paid lifecycle states
- Documented boarder charges and credits that preserve the source occupancy
  and room-rate history
- Immutable rent snapshots with reconciled room, boarder, rent, adjustment,
  and grand totals
- Room utility bills that combine finalized electricity and water batches
  without assigning private boarder shares inside the app
- Duplicate-period protection, documented voiding, and versioned reissue for
  corrections without rewriting financial history
- Append-only cash, GCash, bank-transfer, and other payment records with dates,
  notes, partial/paid/unpaid status, and transactional overpayment prevention
- A live billing dashboard for the current period, billed, collected,
  outstanding, unpaid bills, and operational quick actions
- A4 room-utility summaries and room statements regenerated from immutable
  electricity/water snapshots, with legacy boarder-cycle reports kept read-only
- In-app PDF preview, consistent privacy-safe filenames, Android save/print
  flow, and native file sharing to Messenger or other supported applications
- Owner-scoped Firestore rules with atomic lifecycle validation
- Host-side Flutter tests and headless Firestore Security Rules tests
- Release-signing guard plus a documented backup, recovery, App Check, and
  physical-phone release procedure

## Technology

- Flutter 3.47.7 / Dart 3.13.5
- Firebase Core 4.15.0
- Firebase Auth 6.7.0
- Cloud Firestore 6.10.0
- Riverpod 3.4.3
- GoRouter 18.0.2
- google_sign_in 7.2.0
- pdf 3.13.1
- printing 5.15.1
- share_plus 13.3.1

Exact resolved versions are recorded in `pubspec.lock`.

## Before running

1. Install Flutter and add `flutter/bin` to `PATH`.
2. In Android Studio's SDK Manager, install an Android SDK platform, Android SDK
   Build-Tools, Android SDK Command-line Tools, and Android SDK Platform-Tools.
3. Run `flutter doctor` and accept any Android licenses.
4. Complete the remaining console steps in
   [Firebase setup](docs/FIREBASE_SETUP.md).

The Android client is connected to the `marianobh-fcc1b` Firebase project. No
private administrative credentials are committed.

## Run on a personal Android phone

No Android emulator is required or used by this project.

1. Enable **Developer options** and **USB debugging** on the phone.
2. Connect it over USB and approve the computer's debugging prompt.
3. Verify that Flutter sees it:

   ```powershell
   flutter devices
   ```

4. Run the app, replacing the ID with the one shown above:

   ```powershell
   flutter run -d <physical-device-id>
   ```

To create an installable development APK instead:

```powershell
flutter build apk --debug
```

The APK will be under `build/app/outputs/flutter-apk/`.

Production signing, the internal release-mode APK switch, Firebase deployment,
backup recovery, and the no-emulator acceptance checklist are documented in
[the Phase 8 runbook](docs/PHASE_8_RELEASE.md).

## Verification

Run the Flutter analyzer and host-side tests (neither starts an Android
emulator):

```powershell
flutter analyze
flutter test
```

Run Firestore Security Rules tests with the headless Firebase Local Emulator
Suite:

```powershell
cd firebase-tests
npm install
npm run test:rules
```

The Firebase emulator is a local database/rules process, not an Android device
emulator. The application itself should be smoke-tested on the personal phone.

## Architecture

The source is organized by feature. Authentication and onboarding depend on
repository interfaces, so session/routing behavior is testable without Firebase
or a device.

```text
lib/
  app/                     theme and protected GoRouter configuration
  core/                    shared validation
  features/
    authentication/        domain, Firebase adapter, session, screens
    onboarding/            owner workspace and Firestore transaction
    dashboard/             live room and boarder overview
    property_management/   room, boarder, occupancy domain/data/screens
    electricity/           meter sequences, readings, allocation, history
    water/                 settings, dual allocation methods, history
    rent/                  fixed anniversary rent, payments, move-out handling
    billing/               room utility bills, legacy cycles, payments, dashboard
    reports/               snapshot validation, A4 PDFs, preview and sharing
    settings/              account and business defaults
  shared/                  navigation and reusable widgets
```

The authorization boundary is encoded in the document path:

```text
/users/{authenticatedUid}
/owners/{authenticatedUid}/boardingHouses/primary
/owners/{authenticatedUid}/boardingHouses/primary/rooms/{roomId}
/owners/{authenticatedUid}/boardingHouses/primary/boarders/{boarderId}
/owners/{authenticatedUid}/boardingHouses/primary/occupancies/{occupancyId}
/owners/{authenticatedUid}/boardingHouses/primary/roomMeterStates/{roomId}
/owners/{authenticatedUid}/boardingHouses/primary/electricityMeters/{meterId}
/owners/{authenticatedUid}/boardingHouses/primary/meterReadings/{readingId}
/owners/{authenticatedUid}/boardingHouses/primary/meterReadingCorrections/{correctionId}
/owners/{authenticatedUid}/boardingHouses/primary/electricityBillingRecords/{recordId}
/owners/{authenticatedUid}/boardingHouses/primary/waterSettings/config
/owners/{authenticatedUid}/boardingHouses/primary/waterBillingRecords/{recordId}
/owners/{authenticatedUid}/boardingHouses/primary/rentSettings/config
/owners/{authenticatedUid}/boardingHouses/primary/rentBillingRecords/{recordId}
/owners/{authenticatedUid}/boardingHouses/primary/billingPeriods/{periodId}
/owners/{authenticatedUid}/boardingHouses/primary/monthlyBillingCycles/{cycleId}
/owners/{authenticatedUid}/boardingHouses/primary/billingCycleControls/{cycleId}
/owners/{authenticatedUid}/boardingHouses/primary/boarderBillAccounts/{accountId}
/owners/{authenticatedUid}/boardingHouses/primary/payments/{paymentId}
```

The UID—not an email address or a client-editable field—is the source of
ownership. A new account can create only its own new workspace; it cannot claim
or discover another owner's records. Undeclared future collections remain
denied.

Occupancy ranges are `[moveInDate, moveOutDate)`: move-in is billable and
move-out is the first non-billable date. Transfers close the old occupancy and
open the new one on the same date in a single Firestore transaction. Records
are deactivated rather than deleted so later billing phases can keep stable
historical references.

Electricity uses explicit integer units: readings are watt-hours (Wh), rates
are micro-pesos per kWh, and money is centavos. The base charge is calculated
with `round-half-up(consumptionWh * rateMicropesosPerKwh / 10,000,000)` using
`BigInt`, never binary floating point. Largest-remainder allocation makes every
boarder share sum exactly to its room charge.

A reading can only extend its meter sequence on a later date and at the same or
higher value. A physical reset, meter replacement, or clean start closes the
old sequence and opens a new one in one transaction; the reason and both
boundary readings remain in history. The latest active reading may instead be
corrected only while it is unbilled. The app shows an explicit final warning,
requires a reason, updates the reading and meter head atomically, and writes an
immutable before/after audit record. No password or MPIN is requested for this
owner-only action. Older, billed, inactive-sequence, and unmigrated readings
remain read-only. Billing periods use the same half-open
`[startDate, endDate)` convention as occupancies. Saved billing records are
read-only snapshots, so later rate, occupancy, or meter changes cannot alter a
historical bill. Add intermediate readings chronologically when a period needs
more accurate splits; otherwise occupancy-day splits are clearly marked as
estimates. Charges for intervals with no eligible occupant remain explicitly
unallocated.

Water also uses integer centavos and the same half-open billing periods. New
normal batches divide the bill equally among unique boarders selected by the
landlady. Full-period occupants start included; partial occupants need review.
Exclusions require reasons and transferred boarders require an explicit billing
room and explanation. Days are supporting evidence only. Decisions and occupancy
snapshots are frozen with the allocation; historical person-day records retain
their saved values. See [the current workflow](docs/CURRENT_WORKFLOW.md).
The summer method first allocates the water bill to rooms by
their percentage of an immutable electricity record with the exact same dates,
then divides each room share by its occupants' person-days. Electricity
adjustments are excluded when charge is selected as the basis. A missing,
date-mismatched, or zero-total electricity basis cannot be divided; the UI
explains how to save the matching electricity period or use person-days.

Current rent uses the monthly rate stored on each room but is tracked against
the boarder's own agreement. Every completed anniversary period is the full
rent: a June 10 move-in covers June 10-July 9 and becomes due on July 10. Rent
is not added to a utility bill and is never prorated by the number of days in a
normal completed cycle. Partial and full payments update an append-only rent
ledger. The earlier prorated rent calculator and monthly-cycle collections are
retained only for compatibility with historical records.

Current utility billing combines independently finalized electricity and water
batches into one immutable statement per room. The app does not divide that
room balance among boarders. Source batches are atomically locked against reuse,
and each room account supports unpaid, partially paid, and paid states without
rewriting the statement. Legacy boarder monthly cycles remain readable but are
not the current bill-creation workflow.

PDFs are generated locally from the selected immutable room utility statement
and append-only payment ledger. Current and historical room PDFs can be
regenerated without recalculating against current rates or settings. The
preview contains no contact numbers or account credentials. Saving uses
Android's native print/save flow, while sharing uses the native share sheet;
the app does not attempt to post directly into a Messenger group conversation.

Firestore disk persistence is disabled in the current build. This prevents a missing
offline cache from being mistaken for a new owner and avoids exposing one
owner's cached data after logout. Offline drafts can be designed explicitly in
a later phase.

## Important physical-phone checks

After Firebase is connected, use the physical phone to verify:

- registration and receipt of the real verification email;
- blocked access before verification;
- password-reset email delivery;
- sign in with a Google account from the sign-in screen, and from the
  registration screen, and confirm the boarding-house setup or dashboard loads;
- sign out and confirm that Google sign-in can be repeated successfully;
- sign in with Google using an email that already has a password account and
  confirm the friendly "use your email and password" message appears;
- session persistence after force-closing the app;
- offline/error messaging rather than accidental onboarding;
- logout and login with a second account;
- login with the same owner account on another physical device;
- create two boarders in one room and verify both names appear on the room;
- transfer a boarder on a mid-month date and inspect both history rows;
- move a boarder out, move them in again, then deactivate the moved-out record;
- disable the network and confirm that edits show a clear retryable error;
- test light/dark mode, large system text, portrait, and landscape layouts;
- set up each room's baseline meter, then record later dated readings;
- verify a lower reading is rejected and use the reset, replacement, or
  clean-start workflow instead;
- open each room's reading history, correct the latest unbilled reading after
  reviewing the warning, and confirm the old values and reason stay visible;
- save an electricity bill and confirm every reading used by it becomes
  read-only and links back to the immutable bill;
- calculate a period with two boarders and confirm their centavo shares sum to
  the room total;
- verify estimated labels when intermediate readings are unavailable, and
  unallocated labels when no eligible occupant covers an interval;
- save an electricity record, change later data, and confirm the saved history
  is still unchanged.
- calculate a water bill by person-days and confirm all boarder shares plus the
  landlady-paid amount equal the exact source bill;
- transfer a boarder inside a water period and confirm their days and room
  split remain correct;
- save a matching electricity period, calculate summer water by charge and by
  consumption, then verify each room's percentage and occupant split;
- confirm an empty room's water share is explicitly landlady-paid and that a
  missing or zero electricity basis offers the person-day alternative;
- save a water record, change later occupancy/settings, and confirm the saved
  snapshot is unchanged.
- set up a June 10 agreement and confirm the full June 10-July 9 rent becomes
  due July 10, separately from all utility bills;
- confirm an in-progress anniversary period is not charged early;
- finalize independently dated electricity and water batches into one room
  utility bill without including rent or boarder shares;
- confirm the same source batch cannot be attached to a second room bill;
- record partial payments and verify collected, outstanding, payment history,
  and unpaid/partially-paid/paid status update together;
- attempt an overpayment and confirm it is rejected;
- verify the billing dashboard and payment dialog at large system text in both
  portrait and landscape on the personal phone.
- preview the room utility summary and one room statement;
- confirm PDF room totals match the finalized bill exactly;
- use Android's system dialog to save the PDF, then reopen the saved file;
- share the PDF attachment through the native share sheet and select Messenger;
- regenerate an older room bill after changing current settings and confirm its
  historical charges remain unchanged.

Do not add service-account JSON, private keys, or release signing keys to this
repository.
