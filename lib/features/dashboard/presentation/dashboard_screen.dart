import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/app_components.dart';
import '../../authentication/application/auth_providers.dart';
import '../../billing/application/monthly_billing_providers.dart';
import '../../property_management/application/property_providers.dart';
import '../../property_management/domain/boarder.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../../rent/application/rent_providers.dart';
import '../../water/application/water_providers.dart';
import '../../water/domain/water_batch_models.dart';
import '../../electricity/application/electricity_providers.dart';
import '../../electricity/domain/electricity_batch_models.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(appSessionProvider).state.workspace;
    final owner = workspace?.ownerUid;
    return Scaffold(
      appBar: AppBar(
        title: Text(workspace?.houseName ?? 'Boarding House Manager'),
      ),
      body: SafeArea(
        child: ListView(
          key: const PageStorageKey('home-scroll'),
          children: [
            AdaptivePageBody(
              maxWidth: 1000,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageIntro(
                    title:
                        'Welcome, ${workspace?.ownerName.trim().split(' ').firstOrNull ?? 'owner'}',
                    subtitle: 'Your property. Your next steps.',
                    eyebrow: 'PROPERTY AT A GLANCE',
                    icon: Icons.home_work_outlined,
                  ),
                  if (owner != null) ...[
                    const SizedBox(height: 20),
                    AdaptiveTiles(
                      children: [
                        FilledButton.icon(
                          onPressed: () => context.push('/billing/monthly/new'),
                          icon: const Icon(Icons.add, size: 22),
                          label: const Text('Create bill'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/billing/created'),
                          icon: const Icon(Icons.payments_outlined, size: 22),
                          label: const Text('Record payment'),
                        ),
                      ],
                    ),
                    const SectionHeader('Property overview'),
                    _PropertyOverview(owner: owner),
                    const SectionHeader(
                      'Your balances',
                      subtitle: 'Current combined utility bills and recorded rent cycles',
                    ),
                    _Balances(owner: owner),
                    const SectionHeader('Quick actions'),
                    AdaptiveTiles(
                      minWidth: 170,
                      children: [
                        _shortcut(
                          context,
                          'Record electricity',
                          Icons.bolt_outlined,
                          '/billing/electricity/batches/new',
                        ),
                        _shortcut(
                          context,
                          'Create water batch',
                          Icons.water_drop_outlined,
                          '/billing/water/batches/new',
                        ),
                        _shortcut(
                          context,
                          'Manage boarders',
                          Icons.people_outline,
                          '/boarders',
                        ),
                        _shortcut(
                          context,
                          'PDF reports',
                          Icons.picture_as_pdf_outlined,
                          '/billing/created',
                        ),
                      ],
                    ),
                    const SectionHeader('Needs attention'),
                    _Attention(owner: owner),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shortcut(
    BuildContext context,
    String label,
    IconData icon,
    String route,
  ) => OutlinedButton.icon(
    onPressed: () => context.push(route),
    icon: Icon(icon, size: 22),
    label: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(label),
    ),
  );
}

class _PropertyOverview extends ConsumerWidget {
  const _PropertyOverview({required this.owner});
  final String owner;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsProvider(owner));
    final boarders = ref.watch(boardersProvider(owner));
    if (rooms.hasError || boarders.hasError) {
      return ActionListItem(
        title: 'Property overview unavailable',
        subtitle: 'Tap to retry',
        icon: Icons.cloud_off_outlined,
        onTap: () {
          ref.invalidate(roomsProvider(owner));
          ref.invalidate(boardersProvider(owner));
        },
      );
    }
    if (!rooms.hasValue || !boarders.hasValue) {
      return const LinearProgressIndicator(
        semanticsLabel: 'Loading property overview',
      );
    }
    final values = [
      ('Total rooms', rooms.requireValue.length),
      (
        'Occupied rooms',
        rooms.requireValue.where((r) => r.activeOccupancyCount > 0).length,
      ),
      (
        'Active boarders',
        boarders.requireValue
            .where((b) => b.status == BoarderStatus.active)
            .length,
      ),
      (
        'Available rooms',
        rooms.requireValue
            .where((r) => r.isActive && r.activeOccupancyCount == 0)
            .length,
      ),
    ];
    return AdaptiveTiles(
      children: [
        for (final (label, count) in values)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Balances extends ConsumerWidget {
  const _Balances({required this.owner});
  final String owner;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final utilities = ref.watch(utilityRoomBillAccountsProvider(owner));
    final rent = ref.watch(rentCyclesProvider(owner));
    final controls = ref.watch(rentCycleControlsProvider(owner));
    final paid = <String, int>{
      for (final c in controls.asData?.value ?? [])
        c.cycleId: c.totalPaidCentavos,
    };
    return Column(
      children: [
        if (utilities.hasError)
          ActionListItem(
            title: 'Utility balances unavailable',
            subtitle: 'Tap to retry',
            icon: Icons.cloud_off_outlined,
            onTap: () => ref.invalidate(utilityRoomBillAccountsProvider(owner)),
          )
        else if (!utilities.hasValue)
          const LinearProgressIndicator(
            semanticsLabel: 'Loading utility balances',
          )
        else ...[
          _BalanceCard(
            title: 'Utilities outstanding',
            amount: utilities.requireValue.fold(
              0,
              (sum, a) => sum + a.outstandingCentavos,
            ),
            subtitle: 'All created combined bills',
            onTap: () => context.push('/billing/created'),
          ),
          _BalanceCard(
            title: 'Utility payments collected',
            amount: utilities.requireValue.fold(
              0,
              (sum, a) => sum + a.totalPaidCentavos,
            ),
            subtitle: 'All-time collections on combined bills',
            onTap: () => context.push('/billing/created'),
          ),
        ],
        if (rent.hasError || controls.hasError)
          ActionListItem(
            title: 'Rent balances unavailable',
            subtitle: 'Tap to retry',
            icon: Icons.cloud_off_outlined,
            onTap: () {
              ref.invalidate(rentCyclesProvider(owner));
              ref.invalidate(rentCycleControlsProvider(owner));
            },
          )
        else if (!rent.hasValue || !controls.hasValue)
          const LinearProgressIndicator(semanticsLabel: 'Loading rent balances')
        else
          _BalanceCard(
            title: 'Rent outstanding',
            amount: rent.requireValue.fold<int>(
              0,
              (sum, r) =>
                  sum +
                  (r.amountCentavos - (paid[r.cycleId] ?? 0)).clamp(
                    0,
                    r.amountCentavos,
                  ),
            ),
            subtitle: 'Recorded cycles · open Rent to update due cycles',
            onTap: () => context.push('/billing/rent'),
          ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.onTap,
  });
  final String title, subtitle;
  final int amount;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            FinancialAmount(amount),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Attention extends ConsumerWidget {
  const _Attention({required this.owner});
  final String owner;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final water = ref.watch(waterBillingBatchesProvider(owner));
    final electricity = ref.watch(electricityReadingBatchesProvider(owner));
    final accounts = ref.watch(utilityRoomBillAccountsProvider(owner));
    return Column(
      children: [
        ActionListItem(
          title: water.hasError
              ? 'Water tasks unavailable'
              : water.hasValue
              ? '${water.requireValue.where((b) => b.status == WaterBillingBatchStatus.draft).length} water drafts to review'
              : 'Loading water tasks…',
          subtitle: 'Review selections and finalize allocations',
          icon: Icons.water_drop_outlined,
          onTap: () => context.push('/billing/water'),
        ),
        ActionListItem(
          title: electricity.hasError
              ? 'Electricity tasks unavailable'
              : electricity.hasValue
              ? '${electricity.requireValue.where((b) => b.status == ElectricityReadingBatchStatus.draft).length} electricity drafts'
              : 'Loading electricity tasks…',
          subtitle: 'Complete readings before creating bills',
          icon: Icons.bolt_outlined,
          onTap: () => context.push('/billing/electricity'),
        ),
        ActionListItem(
          title: accounts.hasError
              ? 'Unpaid accounts unavailable'
              : accounts.hasValue
              ? '${accounts.requireValue.where((a) => a.outstandingCentavos > 0).length} unpaid room accounts'
              : 'Loading unpaid accounts…',
          subtitle: 'Open a bill to record a payment',
          icon: Icons.payments_outlined,
          onTap: () => context.push('/billing/created'),
        ),
        ActionListItem(
          title: 'Review rent & move-outs',
          subtitle: 'Update due rent and resolve extra stays',
          icon: Icons.event_note_outlined,
          onTap: () => context.push('/billing/rent'),
        ),
      ],
    );
  }
}
