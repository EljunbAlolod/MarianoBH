import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/monthly_billing_providers.dart';
import '../domain/monthly_billing_models.dart';
import '../domain/room_billing_assembler.dart';
import '../domain/room_billing_models.dart';
import '../domain/utility_billing_models.dart';
import 'monthly_billing_formatters.dart';
import 'monthly_billing_widgets.dart';

class RoomBillingScreen extends ConsumerWidget {
  const RoomBillingScreen({super.key});

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
    final cycles = ref.watch(roomBillingCyclesProvider(ownerId));
    final controls = ref.watch(roomBillingControlsProvider(ownerId));
    final accounts = ref.watch(roomBillAccountsProvider(ownerId));
    final utilityBatches = ref.watch(utilityBillingBatchesProvider(ownerId));
    final utilityAccounts = ref.watch(utilityRoomBillAccountsProvider(ownerId));
    final values = [
      cycles,
      controls,
      accounts,
      utilityBatches,
      utilityAccounts,
    ];
    final error = values.where((value) => value.hasError).firstOrNull;
    final loading = values.any((value) => value.isLoading);
    return Scaffold(
      appBar: AppBar(title: const Text('Room bills')),
      body: SafeArea(
        child: error != null
            ? AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Room bills could not be loaded',
                  message: propertyErrorMessage(error.error!),
                  actionLabel: 'Try again',
                  onAction: () {
                    ref.invalidate(roomBillingCyclesProvider(ownerId));
                    ref.invalidate(roomBillingControlsProvider(ownerId));
                    ref.invalidate(roomBillAccountsProvider(ownerId));
                    ref.invalidate(utilityBillingBatchesProvider(ownerId));
                    ref.invalidate(utilityRoomBillAccountsProvider(ownerId));
                  },
                ),
              )
            : loading
            ? const Center(child: CircularProgressIndicator())
            : _Content(
                cycles: cycles.requireValue,
                controls: controls.requireValue,
                accounts: accounts.requireValue,
                utilityBatches: utilityBatches.requireValue,
                utilityAccounts: utilityAccounts.requireValue,
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
    required this.utilityBatches,
    required this.utilityAccounts,
  });

  final List<RoomBillingCycle> cycles;
  final List<BillingCycleControl> controls;
  final List<RoomBillAccount> accounts;
  final List<UtilityBillingBatch> utilityBatches;
  final List<UtilityRoomBillAccount> utilityAccounts;

  @override
  Widget build(BuildContext context) {
    final summary = const RoomBillingAssembler().summarize(
      cycles: cycles,
      controls: controls,
      accounts: accounts,
    );
    final utilityBilled = utilityAccounts.fold<int>(
      0,
      (sum, account) => sum + account.totalChargesCentavos,
    );
    final utilityPaid = utilityAccounts.fold<int>(
      0,
      (sum, account) => sum + account.totalPaidCentavos,
    );
    final utilityUnpaidCount = utilityAccounts
        .where((account) => account.status != BillPaymentStatus.paid)
        .length;
    final controlsById = {
      for (final control in controls) control.billingCycleId: control,
    };
    final accountsByCycle = <String, List<RoomBillAccount>>{};
    for (final account in accounts) {
      accountsByCycle
          .putIfAbsent(account.billingCycleId, () => [])
          .add(account);
    }
    return ListView(
      children: [
        AdaptivePageBody(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Room billing dashboard',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                summary.currentCycle != null
                    ? 'Latest month: ${formatMonthlyPeriod(summary.currentCycle!.startDate, summary.currentCycle!.endDateExclusive)}'
                    : utilityBatches.isNotEmpty
                    ? 'Latest combined utility bill: ${utilityBatches.first.billingBatchReference}. Rent remains separate.'
                    : 'Create the first room utility bill.',
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
                      centavos: utilityBilled,
                      icon: Icons.receipt_long_outlined,
                    ),
                    BillingMetricCard(
                      label: 'Collected',
                      centavos: utilityPaid,
                      icon: Icons.payments_outlined,
                    ),
                    BillingMetricCard(
                      label: 'Outstanding',
                      centavos: utilityBilled - utilityPaid,
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
              FilledButton.icon(
                key: const Key('create-room-bills-button'),
                onPressed: () => context.push('/billing/monthly/new'),
                icon: const Icon(Icons.add_chart_rounded),
                label: const Text('Create room bills'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('view-created-bills-button'),
                onPressed: () => context.push('/billing/created'),
                icon: const Icon(Icons.pending_actions_outlined),
                label: Text(
                  'Created bills (${utilityBatches.length}) · $utilityUnpaidCount unpaid',
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => context.push('/billing/monthly/legacy'),
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Legacy boarder bills'),
              ),
              const SizedBox(height: 28),
              Text(
                'Combined utility bills',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (utilityBatches.isEmpty)
                const PropertyStatePanel(
                  icon: Icons.receipt_long_outlined,
                  title: 'No combined bills yet',
                  message: 'Finalized electricity and water batches will be combined here without rent.',
                )
              else
                ...utilityBatches.map(
                  (batch) => Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(
                        batch.billingBatchReference,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${batch.electricityBatchReference} + ${batch.waterBatchReference} · ${formatPeso(batch.totalBilledCentavos)}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push(
                        '/billing/utility/${Uri.encodeComponent(batch.billingBatchId)}',
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 28),
              Text(
                'Legacy room bill history',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (cycles.isEmpty)
                const PropertyStatePanel(
                  icon: Icons.receipt_long_outlined,
                  title: 'No room bills yet',
                  message: 'Finalized room billing months will appear here with each room’s payment status.',
                )
              else
                ...cycles.map((cycle) {
                  final control = controlsById[cycle.billingCycleId];
                  final voided = control?.state == BillingCycleState.voided;
                  final roomAccounts =
                      accountsByCycle[cycle.billingCycleId] ?? [];
                  roomAccounts.sort(
                    (a, b) => a.roomName.toLowerCase().compareTo(
                      b.roomName.toLowerCase(),
                    ),
                  );
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.push(
                        '/billing/monthly/room/${Uri.encodeComponent(cycle.billingCycleId)}',
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                Text(
                                  formatMonthlyPeriod(
                                    cycle.startDate,
                                    cycle.endDateExclusive,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (voided)
                                  const Chip(label: Text('Voided'))
                                else if (control != null)
                                  PaymentStatusPill(
                                    status: control.paymentStatus,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final account in roomAccounts)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final name = Text(
                                      account.roomName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    );
                                    final amount = Text(
                                      '${formatPeso(account.totalPaidCentavos)} / ${formatPeso(account.totalChargesCentavos)}',
                                    );
                                    final status = PaymentStatusPill(
                                      status: account.status,
                                    );
                                    if (constraints.maxWidth < 520 ||
                                        MediaQuery.textScalerOf(context)
                                                .scale(16) >
                                            20) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          name,
                                          const SizedBox(height: 4),
                                          amount,
                                          const SizedBox(height: 6),
                                          status,
                                        ],
                                      );
                                    }
                                    return Row(
                                      children: [
                                        Expanded(child: name),
                                        const SizedBox(width: 8),
                                        amount,
                                        const SizedBox(width: 8),
                                        status,
                                      ],
                                    );
                                  },
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
