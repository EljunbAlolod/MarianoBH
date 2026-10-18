# Google sign-in setup

The sign-in and registration screens offer **Continue with Google** on Android
and iOS. The button is hidden on Windows and web because the Google Sign-In
plugin does not support those platforms.

## One-time Firebase console setup

The Google sign-in flow needs two things in the Firebase console for the
`marianobh-fcc1b` project. Repeat them for any new signing key or new Firebase
project.

### Verified repair

The Firebase Android app initially returned **no registered SHA certificates**.
The local debug keystore was verified with keytool; its SHA-1 and SHA-256 below
were registered, and a subsequent Firebase CLI listing confirmed both entries.
Firebase then returned an Android OAuth client (`client_type: 1`) matching
`com.marianobh.boarding_house` and the debug certificate. The returned client
was added to `android/app/google-services.json`, alongside the existing web
OAuth client.

`flutter build apk --debug --no-pub` succeeded. Authentication, router and
Firebase-options checks passed (18 tests). No Android device was connected;
the real Google account-picker flow still needs phone verification using
`build/app/outputs/flutter-apk/app-debug.apk`.

### 1. Enable the Google provider

1. Open the [Firebase console](https://console.firebase.google.com/) and
   select the **marianobh-fcc1b** project.
2. Go to **Build → Authentication → Sign-in method**.
3. Open **Google**, enable it, choose a support email, and save.
4. Enabling Google creates a **web OAuth client**. Confirm that
   `android/app/google-services.json` contains an `oauth_client` entry with
   `"client_type": 3` (the web client). The Android plugin reads this
   automatically, so no client ID is written in Dart code.

### 2. Register signing fingerprints

Google rejects sign-in from any build of the app whose signing certificate is
not registered. Add each fingerprint to the Android app
(`com.marianobh.boarding_house`):

1. Firebase console → **Project settings (gear) → General → Your apps →
   Android app**.
2. Click **Add fingerprint** and paste each value.

The current debug keystore (used by `flutter run` and debug APKs):

```text
SHA-1:   72:80:7C:70:84:41:9B:AC:45:2E:1A:7C:F8:35:49:6B:39:A6:52:6C
SHA-256: 18:B7:7C:90:E8:19:ED:8F:C2:BC:8B:7E:7F:0F:AA:9E:1E:D8:9D:9E:EA:D3:BF:00:19:6D:21:52:DA:5F:CA:A8
```

Before building a release APK, add the release keystore's fingerprints the same
way. Read them from the keystore configured in `android/key.properties`:

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" `
  -list -v -keystore <path-to-release-keystore> -alias <key-alias>
```

The debug keystore values can be re-read at any time with the same command
pointed at `$env:USERPROFILE\.android\debug.keystore` and the alias
`androiddebugkey` (store and key password: `android`).

No `google-services.json` re-download is needed after adding fingerprints.

## Testing it

1. Install the app on the personal phone (`flutter run` or a debug APK).
2. Tap **Continue with Google** on the sign-in screen and pick the Google
   account.
3. A brand-new Google account continues to the boarding-house setup form; an
   account that already has a workspace loads the dashboard.
4. On an Android emulator, only images with the **Google Play Store** include
   Google sign-in support.

## Troubleshooting

- **Error: "Google sign-in is not set up correctly for this app."**
  A `clientConfigurationError`/`providerConfigurationError`. Usually a missing
  fingerprint for this build, the wrong package name, or the Google provider
  turned off. Re-check both console steps above.
- **Tapping the button does nothing after choosing an account.**
  Google can report configuration errors as a silent "canceled" result. If it
  persists, verify the fingerprints; calls using a different keystore fail
  even when debug builds work.
- **"An account already uses this email with a password."**
  The Google email matches an existing email/password account. This is
  intentional: sign in with the password instead. Account linking is a possible
  future enhancement.
- **The button is missing.** Google sign-in is hidden on Windows and web.

## What this feature does not change

- Firestore rules need no update: Google sign-ins are always `email_verified`,
  so the existing verified-owner gate accepts them.
- Email/password sign-in, registration, verification, and password reset keep
  their existing behavior.
