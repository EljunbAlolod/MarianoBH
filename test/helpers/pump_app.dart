import 'package:boarding_house_manager/app/app.dart';
import 'package:boarding_house_manager/features/authentication/application/auth_providers.dart';
import 'package:boarding_house_manager/features/billing/application/monthly_billing_providers.dart';
import 'package:boarding_house_manager/features/electricity/application/electricity_providers.dart';
import 'package:boarding_house_manager/features/property_management/application/property_providers.dart';
import 'package:boarding_house_manager/features/rent/application/rent_providers.dart';
import 'package:boarding_house_manager/features/reports/application/billing_pdf_generator.dart';
import 'package:boarding_house_manager/features/reports/application/billing_report_providers.dart';
import 'package:boarding_house_manager/features/reports/application/utility_billing_pdf_generator.dart';
import 'package:boarding_house_manager/features/water/application/water_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Future<void> pumpTestApp(
  WidgetTester tester, {
  required FakeAuthRepository authRepository,
  required FakeOwnerRepository ownerRepository,
  FakeMonthlyBillingRepository? monthlyBillingRepository,
  FakePropertyRepository? propertyRepository,
  FakeElectricityRepository? electricityRepository,
  FakeRentRepository? rentRepository,
  FakeWaterRepository? waterRepository,
  BillingPdfGenerator? billingPdfGenerator,
  UtilityBillingPdfGenerator? utilityBillingPdfGenerator,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        monthlyBillingRepositoryProvider.overrideWithValue(
          monthlyBillingRepository ?? FakeMonthlyBillingRepository(),
        ),
        ownerRepositoryProvider.overrideWithValue(ownerRepository),
        propertyRepositoryProvider.overrideWithValue(
          propertyRepository ?? FakePropertyRepository(),
        ),
        electricityRepositoryProvider.overrideWithValue(
          electricityRepository ?? FakeElectricityRepository(),
        ),
        rentRepositoryProvider.overrideWithValue(
          rentRepository ?? FakeRentRepository(),
        ),
        waterRepositoryProvider.overrideWithValue(
          waterRepository ?? FakeWaterRepository(),
        ),
        if (billingPdfGenerator != null)
          billingPdfGeneratorProvider.overrideWithValue(billingPdfGenerator),
        if (utilityBillingPdfGenerator != null)
          utilityBillingPdfGeneratorProvider.overrideWithValue(
            utilityBillingPdfGenerator,
          ),
      ],
      child: const BoardingHouseApp(),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}
