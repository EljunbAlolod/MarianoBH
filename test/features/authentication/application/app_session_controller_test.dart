import 'package:boarding_house_manager/features/authentication/application/app_session_controller.dart';
import 'package:boarding_house_manager/features/onboarding/domain/owner_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeOwnerRepository owners;
  late AppSessionController controller;

  setUp(() {
    auth = FakeAuthRepository();
    owners = FakeOwnerRepository();
    controller = AppSessionController(auth, owners)..start();
  });

  tearDown(() async {
    controller.dispose();
    await auth.dispose();
  });

  test('signed-out users never load owner data', () async {
    auth.emit(null);
    await pumpEventQueue();

    expect(controller.state.status, AppSessionStatus.signedOut);
    expect(owners.fetchCalls, 0);
  });

  test('unverified users are held before Firestore access', () async {
    auth.emit(unverifiedUser);
    await pumpEventQueue();

    expect(controller.state.status, AppSessionStatus.emailUnverified);
    expect(owners.fetchCalls, 0);
  });

  test('verified user without a workspace requires onboarding', () async {
    auth.emit(verifiedUser);
    await pumpEventQueue();

    expect(controller.state.status, AppSessionStatus.onboardingRequired);
    expect(owners.fetchCalls, 1);
  });

  test('verified returning owner becomes ready', () async {
    owners.workspace = ownerWorkspace;
    auth.emit(verifiedUser);
    await pumpEventQueue();

    expect(controller.state.status, AppSessionStatus.ready);
    expect(controller.state.workspace?.houseName, 'Mariano Boarding House');
  });

  test('offline owner lookup is not mistaken for new onboarding', () async {
    owners.fetchError = const OwnerRepositoryException(
      'Offline',
      code: 'unavailable',
      isOffline: true,
    );
    auth.emit(verifiedUser);
    await pumpEventQueue();

    expect(controller.state.status, AppSessionStatus.offline);
    expect(controller.state.status, isNot(AppSessionStatus.onboardingRequired));
  });
}
