import 'package:boarding_house_manager/features/authentication/domain/auth_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes.dart';
import '../../../helpers/pump_app.dart';

void main() {
  testWidgets('login validates input before calling authentication', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    final owners = FakeOwnerRepository();
    addTearDown(auth.dispose);
    await pumpTestApp(tester, authRepository: auth, ownerRepository: owners);

    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();

    expect(find.text('Email address is required.'), findsOneWidget);
    expect(find.text('Password is required.'), findsOneWidget);
    expect(auth.signInCalls, 0);
  });

  testWidgets('login sends normalized credentials once', (tester) async {
    final auth = FakeAuthRepository()..signInResult = unverifiedUser;
    final owners = FakeOwnerRepository();
    addTearDown(auth.dispose);
    await pumpTestApp(tester, authRepository: auth, ownerRepository: owners);

    await tester.enterText(
      find.byKey(const Key('login-email')),
      ' owner@example.com ',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'password123',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(auth.signInCalls, 1);
    expect(auth.lastEmail, ' owner@example.com ');
    expect(find.text('Verify your email'), findsOneWidget);
  });

  testWidgets('password reset gives a non-enumerating success message', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    final owners = FakeOwnerRepository();
    addTearDown(auth.dispose);
    await pumpTestApp(tester, authRepository: auth, ownerRepository: owners);

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reset-email')),
      'unknown@example.com',
    );
    await tester.tap(find.byKey(const Key('reset-submit')));
    await tester.pumpAndSettle();

    expect(auth.resetCalls, 1);
    expect(
      find.textContaining('If an account uses that email'),
      findsOneWidget,
    );
  });

  testWidgets('verified owner can create the deterministic workspace', (
    tester,
  ) async {
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository();
    addTearDown(auth.dispose);
    await pumpTestApp(tester, authRepository: auth, ownerRepository: owners);

    await tester.enterText(
      find.byKey(const Key('setup-house-name')),
      'Mariano Boarding House',
    );
    await tester.tap(find.byKey(const Key('setup-submit')));
    await tester.pumpAndSettle();

    expect(owners.createCalls, 1);
    expect(owners.lastOwnerName, 'Maria Santos');
    expect(owners.lastHouseName, 'Mariano Boarding House');
    expect(find.text('Welcome, Maria'), findsOneWidget);
  });

  testWidgets('login offers Google sign-in and starts it once', (tester) async {
    final auth = FakeAuthRepository()..googleSignInResult = verifiedUser;
    final owners = FakeOwnerRepository();
    addTearDown(auth.dispose);
    await pumpTestApp(tester, authRepository: auth, ownerRepository: owners);

    expect(find.text('Continue with Google'), findsOneWidget);

    await tester.tap(find.byKey(const Key('login-google')));
    await tester.pumpAndSettle();

    expect(auth.signInWithGoogleCalls, 1);
    expect(find.text('Set up your boarding house'), findsOneWidget);
  });

  testWidgets('Google sign-in failure shows a friendly message', (tester) async {
    final auth = FakeAuthRepository()
      ..nextError = const AuthException(
        'Google sign-in could not be completed. Try again.',
      );
    final owners = FakeOwnerRepository();
    addTearDown(auth.dispose);
    await pumpTestApp(tester, authRepository: auth, ownerRepository: owners);

    await tester.tap(find.byKey(const Key('login-google')));
    await tester.pumpAndSettle();

    expect(auth.signInWithGoogleCalls, 1);
    expect(
      find.text('Google sign-in could not be completed. Try again.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
  });

  testWidgets('register screen offers Google sign-in', (tester) async {
    final auth = FakeAuthRepository()..googleSignInResult = verifiedUser;
    final owners = FakeOwnerRepository();
    addTearDown(auth.dispose);
    await pumpTestApp(tester, authRepository: auth, ownerRepository: owners);

    await tester.ensureVisible(find.text('Create the owner account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create the owner account'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('register-google')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('register-google')));
    await tester.pumpAndSettle();

    expect(auth.signInWithGoogleCalls, 1);
    expect(find.text('Set up your boarding house'), findsOneWidget);
  });

  testWidgets('Google sign-in is hidden on unsupported platforms', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final auth = FakeAuthRepository();
    final owners = FakeOwnerRepository();
    addTearDown(auth.dispose);
    await pumpTestApp(tester, authRepository: auth, ownerRepository: owners);

    expect(find.byKey(const Key('login-google')), findsNothing);
    expect(find.text('Continue with Google'), findsNothing);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
