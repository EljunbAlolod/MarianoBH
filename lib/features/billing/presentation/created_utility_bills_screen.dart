import 'package:flutter/material.dart';

import '../../../shared/widgets/app_components.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/monthly_billing_providers.dart';
import '../domain/utility_billing_models.dart';
import 'monthly_billing_widgets.dart';

class CreatedUtilityBillsScreen extends ConsumerWidget {
  const CreatedUtilityBillsScreen({super.key});

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
    final batches = ref.watch(utilityBillingBatchesProvider(ownerId));
    final accounts = ref.watch(utilityRoomBillAccountsProvider(ownerId));
    final values = <AsyncValue<Object?>>[batches, accounts];
    final failure = values.where((value) => value.hasError).firstOrNull;
    final loading = values.any((value) => value.isLoading);
    return Scaffold(
      appBar: AppBar(title: const Text('Created bills')),
      body: SafeArea(
        child: failure != null
            ? AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Created bills could not be loaded',
                  message: propertyErrorMessage(failure.error!),
                  actionLabel: 'Try again',
                  onAction: () {
                    ref.invalidate(utilityBillingBatchesProvider(ownerId));
                    ref.invalidate(utilityRoomBillAccountsProvider(ownerId));
                  },
                ),
              )
            : loading
            ? const Center(child: CircularProgressIndicator())
            : _Content(
                batches: batches.requireValue,
                accounts: accounts.requireValue,
              ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.batches, required this.accounts});

  final List<UtilityBillingBatch> batches;
  final List<UtilityRoomBillAccount> accounts;

  @override
  Widget build(BuildContext context) {
    final accountsByBatch = <String, List<UtilityRoomBillAccount>>{};
    for (final account in accounts) {
      accountsByBatch
          .putIfAbsent(account.billingBatchId, () => [])
          .add(account);
    }
    final billed = accounts.fold<int>(
      0,
      (sum, account) => sum + account.totalChargesCentavos,
    );
    final paid = accounts.fold<int>(
      0,
      (sum, account) => sum + account.totalPaidCentavos,
    );
    return ListView(
      children: [
        AdaptivePageBody(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageIntro(
                title: 'Created utility bills',
                subtitle: 'Open any finalized snapshot to record room payments or create a historical PDF. Rent remains separate.',
                icon: Icons.folder_open_outlined,
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
                      centavos: billed,
                      icon: Icons.receipt_long_outlined,
                    ),
                    BillingMetricCard(
                      label: 'Paid',
                      centavos: paid,
                      icon: Icons.payments_outlined,
                    ),
                    BillingMetricCard(
                      label: 'Outstanding',
                      centavos: billed - paid,
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
              const SizedBox(height: 24),
              if (batches.isEmpty)
                PropertyStatePanel(
                  icon: Icons.receipt_long_outlined,
                  title: 'No created bills yet',
                  message: 'Finalize an electricity and water combination to create the first room utility bill.',
                  actionLabel: 'Create room bills',
                  onAction: () => context.push('/billing/monthly/new'),
                )
              else
                ...batches.map((batch) {
                  final batchAccounts =
                      accountsByBatch[batch.billingBatchId] ?? const [];
                  final paidAmount = batchAccounts.fold<int>(
                    0,
                    (sum, account) => sum + account.totalPaidCentavos,
                  );
                  final status = utilityBillingPaymentStatus(batchAccounts);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: Key('created-bill-${batch.billingBatchId}'),
                        onTap: () => context.push(
                          '/billing/utility/${Uri.encodeComponent(batch.billingBatchId)}',
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
                                    batch.billingBatchReference,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  PaymentStatusPill(status: status),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Created ${formatBusinessDate(batch.issuedOn)}',
                              ),
                              Text(
                                '${batch.electricityBatchReference} + ${batch.waterBatchReference}',
                              ),
                              Text(
                                '${batch.statements.length} ${batch.statements.length == 1 ? 'room' : 'rooms'} billed',
                              ),
                              const SizedBox(height: 10),
                              BillingValueRow(
                                label: 'Total',
                                value: formatPeso(batch.totalBilledCentavos),
                                emphasized: true,
                              ),
                              BillingValueRow(
                                label: 'Paid',
                                value: formatPeso(paidAmount),
                              ),
                              BillingValueRow(
                                label: 'Outstanding',
                                value: formatPeso(
                                  batch.totalBilledCentavos - paidAmount,
                                ),
                              ),
                              const SizedBox(height: 10),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final stack =
                                      constraints.maxWidth < 440 ||
                                      MediaQuery.textScalerOf(context)
                                              .scale(16) >
                                          20;
                                  final view = OutlinedButton.icon(
                                    onPressed: () => context.push(
                                      '/billing/utility/${Uri.encodeComponent(batch.billingBatchId)}',
                                    ),
                                    icon: const Icon(Icons.visibility_outlined),
                                    label: const Text('View details'),
                                  );
                                  final pdf = FilledButton.tonalIcon(
                                    key: Key(
                                      'created-bill-pdf-${batch.billingBatchId}',
                                    ),
                                    onPressed: () => context.push(
                                      '/billing/utility/${Uri.encodeComponent(batch.billingBatchId)}/pdf',
                                    ),
                                    icon: const Icon(
                                      Icons.picture_as_pdf_outlined,
                                    ),
                                    label: const Text('PDF'),
                                  );
                                  if (stack) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        view,
                                        const SizedBox(height: 8),
                                        pdf,
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Expanded(child: view),
                                      const SizedBox(width: 8),
                                      Expanded(child: pdf),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
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
