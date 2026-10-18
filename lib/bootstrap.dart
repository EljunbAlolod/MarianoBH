import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/theme/app_theme.dart';
import 'features/authentication/application/auth_providers.dart';
import 'features/authentication/data/firebase_auth_repository.dart';
import 'features/billing/application/monthly_billing_providers.dart';
import 'features/billing/data/firestore_monthly_billing_repository.dart';
import 'features/electricity/application/electricity_providers.dart';
import 'features/electricity/data/firestore_electricity_repository.dart';
import 'features/onboarding/data/firestore_owner_repository.dart';
import 'features/property_management/application/property_providers.dart';
import 'features/property_management/data/firestore_property_repository.dart';
import 'features/rent/application/rent_providers.dart';
import 'features/rent/data/firestore_rent_repository.dart';
import 'features/water/application/water_providers.dart';
import 'features/water/data/firestore_water_repository.dart';
import 'firebase_options.dart';
import 'shared/widgets/brand_mark.dart';

class FirebaseBootstrapApp extends StatefulWidget {
  const FirebaseBootstrapApp({super.key});

  @override
  State<FirebaseBootstrapApp> createState() => _FirebaseBootstrapAppState();
}

class _FirebaseBootstrapAppState extends State<FirebaseBootstrapApp> {
  late Future<_AppDependencies> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  Future<_AppDependencies> _initialize() async {
    if (Firebase.apps.isEmpty) {
      // `flutterfire configure` replaces the compile-safe placeholder options.
      // No private service-account credentials belong in the mobile app.
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    final firestore = FirebaseFirestore.instance;
    firestore.settings = const Settings(persistenceEnabled: false);
    return _AppDependencies(
      authRepository: FirebaseAuthRepository(FirebaseAuth.instance),
      monthlyBillingRepository: FirestoreMonthlyBillingRepository(firestore),
      ownerRepository: FirestoreOwnerRepository(firestore),
      propertyRepository: FirestorePropertyRepository(firestore),
      electricityRepository: FirestoreElectricityRepository(firestore),
      rentRepository: FirestoreRentRepository(firestore),
      waterRepository: FirestoreWaterRepository(firestore),
    );
  }

  void _retry() {
    setState(() => _initialization = _initialize());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AppDependencies>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const _BootstrapLoadingScreen(),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: _FirebaseSetupRequiredScreen(onRetry: _retry),
          );
        }
        final dependencies = snapshot.requireData;
        return ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              dependencies.authRepository,
            ),
            monthlyBillingRepositoryProvider.overrideWithValue(
              dependencies.monthlyBillingRepository,
            ),
            ownerRepositoryProvider.overrideWithValue(
              dependencies.ownerRepository,
            ),
            propertyRepositoryProvider.overrideWithValue(
              dependencies.propertyRepository,
            ),
            electricityRepositoryProvider.overrideWithValue(
              dependencies.electricityRepository,
            ),
            rentRepositoryProvider.overrideWithValue(
              dependencies.rentRepository,
            ),
            waterRepositoryProvider.overrideWithValue(
              dependencies.waterRepository,
            ),
          ],
          child: const BoardingHouseApp(),
        );
      },
    );
  }
}

class _AppDependencies {
  const _AppDependencies({
    required this.authRepository,
    required this.monthlyBillingRepository,
    required this.ownerRepository,
    required this.propertyRepository,
    required this.electricityRepository,
    required this.rentRepository,
    required this.waterRepository,
  });

  final FirebaseAuthRepository authRepository;
  final FirestoreMonthlyBillingRepository monthlyBillingRepository;
  final FirestoreOwnerRepository ownerRepository;
  final FirestorePropertyRepository propertyRepository;
  final FirestoreElectricityRepository electricityRepository;
  final FirestoreRentRepository rentRepository;
  final FirestoreWaterRepository waterRepository;
}

class _BootstrapLoadingScreen extends StatelessWidget {
  const _BootstrapLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(),
            SizedBox(height: 28),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _FirebaseSetupRequiredScreen extends StatelessWidget {
  const _FirebaseSetupRequiredScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: BrandMark(),
                  ),
                  const SizedBox(height: 36),
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 58,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Firebase setup required',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'This development build has no Firebase project configuration yet. Run the documented FlutterFire setup, rebuild the app, then try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry initialization'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
