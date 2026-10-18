import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/application/app_session_controller.dart';
import '../../features/authentication/application/auth_providers.dart';
import '../../features/authentication/presentation/forgot_password_screen.dart';
import '../../features/authentication/presentation/login_screen.dart';
import '../../features/authentication/presentation/register_screen.dart';
import '../../features/authentication/presentation/session_problem_screen.dart';
import '../../features/authentication/presentation/splash_screen.dart';
import '../../features/authentication/presentation/verify_email_screen.dart';
import '../../features/billing/presentation/billing_hub_screen.dart';
import '../../features/billing/presentation/created_utility_bills_screen.dart';
import '../../features/billing/presentation/monthly_bill_detail_screen.dart';
import '../../features/billing/presentation/monthly_billing_finalize_screen.dart';
import '../../features/billing/presentation/monthly_billing_screen.dart';
import '../../features/billing/presentation/room_bill_detail_screen.dart';
import '../../features/billing/presentation/room_billing_finalize_screen.dart';
import '../../features/billing/presentation/room_billing_screen.dart';
import '../../features/billing/presentation/unpaid_bills_screen.dart';
import '../../features/billing/presentation/utility_billing_detail_screen.dart';
import '../../features/billing/presentation/utility_billing_pdf_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/electricity/presentation/billing_screen.dart';
import '../../features/electricity/presentation/electricity_batch_detail_screen.dart';
import '../../features/electricity/presentation/electricity_batch_editor_screen.dart';
import '../../features/electricity/presentation/electricity_calculation_screen.dart';
import '../../features/electricity/presentation/electricity_record_detail_screen.dart';
import '../../features/electricity/presentation/meter_reading_correction_screen.dart';
import '../../features/electricity/presentation/meter_reading_history_screen.dart';
import '../../features/onboarding/presentation/boarding_house_setup_screen.dart';
import '../../features/property_management/presentation/boarders/boarder_detail_screen.dart';
import '../../features/property_management/presentation/boarders/boarders_screen.dart';
import '../../features/property_management/presentation/rooms/rooms_screen.dart';
import '../../features/property_management/presentation/rooms/room_detail_screen.dart';
import '../../features/property_management/domain/business_date.dart';
import '../../features/rent/presentation/rent_billing_screen.dart';
import '../../features/rent/presentation/rent_record_detail_screen.dart';
import '../../features/reports/presentation/billing_report_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/water/presentation/water_billing_screen.dart';
import '../../features/water/presentation/water_batch_detail_screen.dart';
import '../../features/water/presentation/water_batch_editor_screen.dart';
import '../../features/water/presentation/water_calculation_screen.dart';
import '../../features/water/presentation/water_record_detail_screen.dart';
import '../../shared/navigation/app_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(appSessionProvider);
  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: session,
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (context, state) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const BoardingHouseSetupScreen(),
      ),
      GoRoute(
        path: '/problem',
        builder: (context, state) => const SessionProblemScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: _navigationBranches([
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/rooms',
            builder: (context, state) => const RoomsScreen(),
          ),
          GoRoute(
            path: '/rooms/:roomId',
            builder: (context, state) =>
                RoomDetailScreen(roomId: state.pathParameters['roomId']!),
          ),
          GoRoute(
            path: '/boarders',
            builder: (context, state) => const BoardersScreen(),
          ),
          GoRoute(
            path: '/boarders/:boarderId',
            builder: (context, state) => BoarderDetailScreen(
              boarderId: state.pathParameters['boarderId']!,
            ),
          ),
          GoRoute(
            path: '/billing',
            builder: (context, state) => const BillingHubScreen(),
          ),
          GoRoute(
            path: '/billing/monthly',
            builder: (context, state) => const RoomBillingScreen(),
          ),
          GoRoute(
            path: '/billing/monthly/new',
            builder: (context, state) => RoomBillingFinalizeScreen(
              initialStartDate: _queryDate(state, 'start'),
            ),
          ),
          GoRoute(
            path: '/billing/created',
            builder: (context, state) => const CreatedUtilityBillsScreen(),
          ),
          GoRoute(
            path: '/billing/utility/:billingBatchId/pdf',
            builder: (context, state) => UtilityBillingPdfScreen(
              billingBatchId: state.pathParameters['billingBatchId']!,
            ),
          ),
          GoRoute(
            path: '/billing/utility/:billingBatchId',
            builder: (context, state) => UtilityBillingDetailScreen(
              billingBatchId: state.pathParameters['billingBatchId']!,
            ),
          ),
          GoRoute(
            path: '/billing/monthly/legacy',
            builder: (context, state) => const MonthlyBillingScreen(),
          ),
          GoRoute(
            path: '/billing/monthly/legacy/new',
            builder: (context, state) => const MonthlyBillingFinalizeScreen(),
          ),
          GoRoute(
            path: '/billing/monthly/room/:cycleId',
            builder: (context, state) =>
                RoomBillDetailScreen(cycleId: state.pathParameters['cycleId']!),
          ),
          GoRoute(
            path: '/billing/monthly/:cycleId/reports',
            builder: (context, state) =>
                BillingReportScreen(cycleId: state.pathParameters['cycleId']!),
          ),
          GoRoute(
            path: '/billing/monthly/:cycleId',
            builder: (context, state) => MonthlyBillDetailScreen(
              cycleId: state.pathParameters['cycleId']!,
            ),
          ),
          GoRoute(
            path: '/billing/unpaid',
            builder: (context, state) => const UnpaidBillsScreen(),
          ),
          GoRoute(
            path: '/billing/electricity',
            builder: (context, state) => const BillingScreen(),
          ),
          GoRoute(
            path: '/billing/electricity/new',
            builder: (context, state) => ElectricityCalculationScreen(
              initialStartDate: _queryDate(state, 'start'),
              initialEndDateExclusive: _queryDate(state, 'end'),
              returnTo: state.uri.queryParameters['returnTo'],
            ),
          ),
          GoRoute(
            path: '/billing/electricity/batches/new',
            builder: (context, state) => const ElectricityBatchEditorScreen(),
          ),
          GoRoute(
            path: '/billing/electricity/batches/:batchId/edit',
            builder: (context, state) => ElectricityBatchEditorScreen(
              batchId: state.pathParameters['batchId']!,
            ),
          ),
          GoRoute(
            path: '/billing/electricity/batches/:batchId',
            builder: (context, state) => ElectricityBatchDetailScreen(
              batchId: state.pathParameters['batchId']!,
            ),
          ),
          GoRoute(
            path: '/billing/electricity/rooms/:roomId/readings',
            builder: (context, state) => MeterReadingHistoryScreen(
              roomId: state.pathParameters['roomId']!,
            ),
          ),
          GoRoute(
            path: '/billing/electricity/rooms/:roomId/readings/:readingId/correct',
            builder: (context, state) => MeterReadingCorrectionScreen(
              roomId: state.pathParameters['roomId']!,
              readingId: state.pathParameters['readingId']!,
            ),
          ),
          GoRoute(
            path: '/billing/electricity/:recordId',
            builder: (context, state) => ElectricityRecordDetailScreen(
              recordId: state.pathParameters['recordId']!,
            ),
          ),
          GoRoute(
            path: '/billing/water',
            builder: (context, state) => const WaterBillingScreen(),
          ),
          GoRoute(
            path: '/billing/water/new',
            builder: (context, state) => WaterCalculationScreen(
              initialStartDate: _queryDate(state, 'start'),
              initialEndDateExclusive: _queryDate(state, 'end'),
              returnTo: state.uri.queryParameters['returnTo'],
            ),
          ),
          GoRoute(
            path: '/billing/water/batches/new',
            builder: (context, state) => const WaterBatchEditorScreen(),
          ),
          GoRoute(
            path: '/billing/water/batches/:batchId/edit',
            builder: (context, state) => WaterBatchEditorScreen(
              batchId: state.pathParameters['batchId']!,
            ),
          ),
          GoRoute(
            path: '/billing/water/batches/:batchId',
            builder: (context, state) => WaterBatchDetailScreen(
              batchId: state.pathParameters['batchId']!,
            ),
          ),
          GoRoute(
            path: '/billing/water/:recordId',
            builder: (context, state) => WaterRecordDetailScreen(
              recordId: state.pathParameters['recordId']!,
            ),
          ),
          GoRoute(
            path: '/billing/rent',
            builder: (context, state) => const RentBillingScreen(),
          ),
          GoRoute(
            path: '/billing/rent/new',
            redirect: (context, state) => '/billing/rent',
          ),
          GoRoute(
            path: '/billing/rent/:recordId',
            builder: (context, state) => RentRecordDetailScreen(
              recordId: state.pathParameters['recordId']!,
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ]),
      ),
    ],
    redirect: (context, routerState) {
      return _redirect(session, routerState.uri.path);
    },
    errorBuilder: (context, state) =>
        _UnknownRouteScreen(onReturn: () => context.go('/dashboard')),
  );
  ref.onDispose(router.dispose);
  return router;
});

List<StatefulShellBranch> _navigationBranches(List<GoRoute> routes) => [
  for (final prefix in [
    '/dashboard',
    '/rooms',
    '/boarders',
    '/billing',
    '/settings',
  ])
    StatefulShellBranch(
      routes: routes
          .where(
            (route) =>
                route.path == prefix || route.path.startsWith('$prefix/'),
          )
          .toList(),
    ),
];

BusinessDate? _queryDate(GoRouterState state, String key) {
  final raw = state.uri.queryParameters[key];
  if (raw == null) return null;
  try {
    return BusinessDate.parse(raw);
  } catch (_) {
    return null;
  }
}

String? _redirect(AppSessionController session, String location) {
  final status = session.state.status;
  const publicRoutes = {'/login', '/register', '/forgot-password'};
  const gatedRoutes = {'/splash', '/verify-email', '/setup', '/problem'};

  switch (status) {
    case AppSessionStatus.loading:
      return location == '/splash' ? null : '/splash';
    case AppSessionStatus.signedOut:
      if (publicRoutes.contains(location)) return null;
      session.rememberIntendedLocation(location);
      return '/login';
    case AppSessionStatus.emailUnverified:
      return location == '/verify-email' ? null : '/verify-email';
    case AppSessionStatus.onboardingRequired:
      return location == '/setup' ? null : '/setup';
    case AppSessionStatus.ready:
      if (publicRoutes.contains(location) || gatedRoutes.contains(location)) {
        return session.takeIntendedLocation();
      }
      return null;
    case AppSessionStatus.offline:
    case AppSessionStatus.failure:
      return location == '/problem' ? null : '/problem';
  }
}

class _UnknownRouteScreen extends StatelessWidget {
  const _UnknownRouteScreen({required this.onReturn});

  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                'Page not found',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 18),
              FilledButton(onPressed: onReturn, child: const Text('Go home')),
            ],
          ),
        ),
      ),
    );
  }
}
