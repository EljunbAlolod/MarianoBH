import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/monthly_billing_providers.dart';
import '../domain/monthly_billing_assembler.dart';
import '../domain/monthly_billing_models.dart';
import 'monthly_billing_formatters.dart';
import 'monthly_billing_widgets.dart';

class MonthlyBillingScreen extends ConsumerWidget {
  const MonthlyBillingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(appSessionProvider).state.workspace;
    if (workspace == null) {
      return const Scaffold(
        body: PropertyStatePanel(
          icon: Icons.lock_outline_rounded,
          title: 'Owner workspace unavailable',
          message: 'Return to the dashboard and try again.',
        ),
      );
    }
    final ownerId = workspace.ownerUid;
    final cycles = ref.watch(monthlyBillingCyclesProvider(ownerId));
    final controls = ref.watch(billingCycleControlsProvider(ownerId));
    final accounts = ref.watch(boarderBillAccountsProvider(ownerId));
    final values = [cycles, controls, accounts];
    final error = values.where((value) => value.hasError).firstOrNull;
    final loading = values.any((value) => value.isLoading);
    return Scaffold(
      appBar: AppBar(title: const Text('Legacy boarder bills')),
      body: SafeArea(
        child: error != null
            ? AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Monthly billing could not be loaded',
                  message: propertyErrorMessage(error.error!),
                  actionLabel: 'Try again',
                  onAction: () {
                    ref.invalidate(monthlyBillingCyclesProvider(ownerId));
                    ref.invalidate(billingCycleControlsProvider(ownerId));
                    ref.invalidate(boarderBillAccountsProvider(ownerId));
                  },
                ),
              )
            : loading
            ? const Center(child: CircularProgressIndicator())
            : _Content(
                cycles: cycles.requireValue,
                controls: controls.requireValue,
                accounts: accounts.requireValue,
              ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.cycles,
    required this.controls,
    required this.accounts,
  });
  final List<MonthlyBillingCycle> cycles;
  final List<BillingCycleControl> controls;
  final List<BoarderBillAccount> accounts;

  @override
  Widget build(BuildContext context) {
    final summary = const MonthlyBillingAssembler().summarize(
      cycles: cycles,
      controls: controls,
      accounts: accounts,
    );
    final controlsById = {
      for (final control in controls) control.billingCycleId: control,
    };
    return ListView(
      children: [
        AdaptivePageBody(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Legacy boarder bills',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                summary.currentCycle == null
                    ? 'No boarder-based billing records were finalized before room billing was enabled.'
                    : 'Read-only archive through ${formatMonthlyPeriod(summary.currentCycle!.startDate, summary.currentCycle!.endDateExclusive)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked =
                      constraints.maxWidth < 680 ||
                      MediaQuery.textScalerOf(context).scale(16) > 20;
                  final cards = [
                    BillingMetricCard(
                      label: 'Billed',
                      centavos: summary.totalBilledCentavos,
                      icon: Icons.receipt_long_outlined,
                    ),
                    BillingMetricCard(
                      label: 'Collected',
                      centavos: summary.totalCollectedCentavos,
                      icon: Icons.payments_outlined,
                    ),
                    BillingMetricCard(
                      label: 'Outstanding',
                      centavos: summary.totalOutstandingCentavos,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ];
                  if (stacked) {
                    return Column(
                      children: [
                        for (var index = 0; index < cards.length; index++) ...[
                          cards[index],
                          if (index != cards.length - 1)
                            const SizedBox(height: 10),
                        ],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < cards.length; index++) ...[
                        Expanded(child: cards[index]),
                        if (index != cards.length - 1)
                          const SizedBox(width: 10),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              const BillingNotice(
                message: 'These boarder statements and payments are preserved exactly as recorded. New bills are created for rooms.',
              ),
              const SizedBox(height: 28),
              Text(
                'Billing history',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (cycles.isEmpty)
                const PropertyStatePanel(
                  icon: Icons.receipt_long_outlined,
                  title: 'No monthly bills yet',
                  message: 'Finalized cycles will appear here with their payment status.',
                )
              else
                ...cycles.map((cycle) {
                  final control = controlsById[cycle.billingCycleId];
                  final voided = control?.state == BillingCycleState.voided;
                  return Card(
                    child: InkWell(
                      onTap: () => context.push(
                        '/billing/monthly/${Uri.encodeComponent(cycle.billingCycleId)}',
                      ),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final period = Text(
                                  formatMonthlyPeriod(
                                    cycle.startDate,
                                    cycle.endDateExclusive,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                );
                                final status = voided
                                    ? const Chip(label: Text('Voided'))
                                    : control == null
                                    ? null
                                    : PaymentStatusPill(
                                        status: control.paymentStatus,
                                      );
                                final stacked =
                                    constraints.maxWidth < 480 ||
                                    MediaQuery.textScalerOf(context).scale(16) >
                                        20;
                                if (stacked) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      period,
                                      if (status != null) ...[
                                        const SizedBox(height: 8),
                                        status,
                                      ],
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: period),
                                    if (status != null) ...[
                                      const SizedBox(width: 8),
                                      status,
                                    ],
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Version ${cycle.version} - ${formatPeso(cycle.totalBilledCentavos)} billed',
                            ),
                            if (!voided && control != null)
                              Text(
                                '${formatPeso(control.outstandingCentavos)} outstanding',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}
