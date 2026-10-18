import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

void main() {
  testWidgets('signed-out session lands on login', (tester) async {
    final auth = FakeAuthRepository();
    final owners = FakeOwnerRepository();
    addTearDown(auth.dispose);

    await pumpTestApp(tester, authRepository: auth, ownerRepository: owners);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Welcome, Maria'), findsNothing);
  });

  testWidgets('unverified account is routed to verification', (tester) async {
    final auth = FakeAuthRepository(initialUser: unverifiedUser);
    final owners = FakeOwnerRepository();
    addTearDown(auth.dispose);

    await pumpTestApp(tester, authRepository: auth, ownerRepository: owners);

    expect(find.text('Verify your email'), findsOneWidget);
    expect(owners.fetchCalls, 0);
  });

  testWidgets('new verified owner is routed to secure setup', (tester) async {
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository();
    addTearDown(auth.dispose);

    await pumpTestApp(tester, authRepository: auth, ownerRepository: owners);

    expect(find.text('One last step'), findsOneWidget);
    expect(find.byKey(const Key('setup-house-name')), findsOneWidget);
  });

  testWidgets('returning owner is routed to dashboard', (tester) async {
    final auth = FakeAuthRepository(initialUser: verifiedUser);
    final owners = FakeOwnerRepository()..workspace = ownerWorkspace;
    addTearDown(auth.dispose);

    await pumpTestApp(tester, authRepository: auth, ownerRepository: owners);

    expect(find.text('Welcome, Maria'), findsOneWidget);
    expect(find.text('Mariano Boarding House'), findsWidgets);
  });
}
