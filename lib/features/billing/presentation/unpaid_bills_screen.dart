import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/monthly_billing_providers.dart';
import '../domain/monthly_billing_models.dart';
import '../domain/room_billing_models.dart';
import 'monthly_billing_formatters.dart';
import 'monthly_billing_widgets.dart';

class UnpaidBillsScreen extends ConsumerWidget {
  const UnpaidBillsScreen({super.key});

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
    final sources = [cycles, controls, accounts];
    final failure = sources.where((source) => source.hasError).firstOrNull;
    final loading = sources.any((source) => source.isLoading);
    return Scaffold(
      appBar: AppBar(title: const Text('Unpaid bills')),
      body: SafeArea(
        child: failure != null
            ? AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Unpaid bills could not be loaded',
                  message: propertyErrorMessage(failure.error!),
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
  final List<RoomBillingCycle> cycles;
  final List<BillingCycleControl> controls;
  final List<RoomBillAccount> accounts;

  @override
  Widget build(BuildContext context) {
    final cyclesById = {for (final item in cycles) item.billingCycleId: item};
    final activeIds = controls
        .where((item) => item.state == BillingCycleState.active)
        .map((item) => item.billingCycleId)
        .toSet();
    final unpaid =
        accounts
            .where(
              (item) =>
                  activeIds.contains(item.billingCycleId) &&
                  item.outstandingCentavos > 0,
            )
            .toList()
          ..sort((a, b) {
            final byName = a.roomName.compareTo(b.roomName);
            return byName != 0
                ? byName
                : b.outstandingCentavos.compareTo(a.outstandingCentavos);
          });
    final total = unpaid.fold<int>(
      0,
      (sum, item) => sum + item.outstandingCentavos,
    );
    return ListView(
      children: [
        AdaptivePageBody(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Outstanding balances',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                '${unpaid.length} ${unpaid.length == 1 ? 'bill' : 'bills'} - ${formatPeso(total)} outstanding',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              if (unpaid.isEmpty)
                const PropertyStatePanel(
                  icon: Icons.task_alt_rounded,
                  title: 'All bills are paid',
                  message: 'There are no active outstanding room bills.',
                )
              else
                ...unpaid.map((account) {
                  final cycle = cyclesById[account.billingCycleId];
                  return Card(
                    child: InkWell(
                      onTap: () => context.push(
                        '/billing/monthly/room/${Uri.encodeComponent(account.billingCycleId)}',
                      ),
                      borderRadius: BorderRadius.circular(16),
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
                                  account.roomName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                PaymentStatusPill(status: account.status),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (cycle != null)
                              Text(
                                formatMonthlyPeriod(
                                  cycle.startDate,
                                  cycle.endDateExclusive,
                                ),
                              ),
                            BillingValueRow(
                              label: 'Remaining',
                              value: formatPeso(account.outstandingCentavos),
                              emphasized: true,
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
