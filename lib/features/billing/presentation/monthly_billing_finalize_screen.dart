import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../electricity/application/electricity_providers.dart';
import '../../electricity/domain/electricity_models.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../../rent/application/rent_providers.dart';
import '../../rent/domain/rent_models.dart';
import '../../water/application/water_providers.dart';
import '../../water/domain/water_models.dart';
import '../application/monthly_billing_providers.dart';
import '../domain/monthly_billing_assembler.dart';
import '../domain/monthly_billing_models.dart';
import 'monthly_billing_widgets.dart';

class MonthlyBillingFinalizeScreen extends ConsumerStatefulWidget {
  const MonthlyBillingFinalizeScreen({super.key});

  @override
  ConsumerState<MonthlyBillingFinalizeScreen> createState() =>
      _MonthlyBillingFinalizeScreenState();
}

class _MonthlyBillingFinalizeScreenState
    extends ConsumerState<MonthlyBillingFinalizeScreen> {
  late BusinessDate _startDate;
  late BusinessDate _endDateExclusive;
  MonthlyBillingResult? _result;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final today = BusinessDate.todayInManila();
    _endDateExclusive = today;
    _startDate = BusinessDate(today.year, today.month, 1);
    if (!_startDate.isBefore(_endDateExclusive)) _startDate = today.addDays(-1);
  }

  void _invalidate() {
    setState(() {
      _result = null;
      _error = null;
    });
  }

  T? _matching<T>(
    List<T> items,
    BusinessDate Function(T) start,
    BusinessDate Function(T) end,
  ) => items
      .where(
        (item) => start(item) == _startDate && end(item) == _endDateExclusive,
      )
      .firstOrNull;

  void _calculate({
    required ElectricityBillingRecord electricity,
    required WaterBillingRecord water,
    required RentBillingRecord rent,
    required List<MonthlyBillingCycle> cycles,
    required List<BillingCycleControl> controls,
    required List<BoarderBillAccount> accounts,
  }) {
    try {
      final controlsById = {
        for (final item in controls) item.billingCycleId: item,
      };
      final cyclesById = {for (final item in cycles) item.billingCycleId: item};
      final previous = <String, int>{};
      for (final account in accounts) {
        final cycle = cyclesById[account.billingCycleId];
        if (cycle == null ||
            controlsById[cycle.billingCycleId]?.state !=
                BillingCycleState.active ||
            cycle.endDateExclusive.isAfter(_startDate) ||
            account.outstandingCentavos <= 0) {
          continue;
        }
        previous.update(
          account.boarderId,
          (value) => value + account.outstandingCentavos,
          ifAbsent: () => account.outstandingCentavos,
        );
      }
      final result = const MonthlyBillingAssembler().assemble(
        electricity: electricity,
        water: water,
        rent: rent,
        previousBalancesByBoarder: previous,
      );
      setState(() {
        _result = result;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _result = null;
        _error = propertyErrorMessage(error);
      });
    }
  }

  Future<void> _save(String ownerId) async {
    final result = _result;
    if (result == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.lock_outline_rounded),
        title: const Text('Finalize this monthly bill?'),
        content: const Text(
          'The source records and boarder charge breakdown become an immutable snapshot. Corrections require voiding and reissuing the cycle.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep reviewing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finalize bill'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(monthlyBillingRepositoryProvider)
          .finalizeCycle(ownerId: ownerId, result: result);
      if (mounted) context.go('/billing/monthly/$id');
    } catch (error) {
      if (mounted) setState(() => _error = propertyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
    final electricity = ref.watch(electricityBillingRecordsProvider(ownerId));
    final water = ref.watch(waterBillingRecordsProvider(ownerId));
    final rent = ref.watch(rentBillingRecordsProvider(ownerId));
    final cycles = ref.watch(monthlyBillingCyclesProvider(ownerId));
    final controls = ref.watch(billingCycleControlsProvider(ownerId));
    final accounts = ref.watch(boarderBillAccountsProvider(ownerId));
    final sources = [electricity, water, rent, cycles, controls, accounts];
    final failure = sources.where((source) => source.hasError).firstOrNull;
    final loading = sources.any((source) => source.isLoading);
    return Scaffold(
      appBar: AppBar(title: const Text('Create monthly bill')),
      body: SafeArea(
        child: failure != null
            ? AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Billing records could not be loaded',
                  message: propertyErrorMessage(failure.error!),
                  actionLabel: 'Try again',
                  onAction: () {
                    ref.invalidate(electricityBillingRecordsProvider(ownerId));
                    ref.invalidate(waterBillingRecordsProvider(ownerId));
                    ref.invalidate(rentBillingRecordsProvider(ownerId));
                    ref.invalidate(monthlyBillingCyclesProvider(ownerId));
                    ref.invalidate(billingCycleControlsProvider(ownerId));
                    ref.invalidate(boarderBillAccountsProvider(ownerId));
                  },
                ),
              )
            : loading
            ? const Center(child: CircularProgressIndicator())
            : _content(
                ownerId: ownerId,
                electricityRecords: electricity.requireValue,
                waterRecords: water.requireValue,
                rentRecords: rent.requireValue,
                cycles: cycles.requireValue,
                controls: controls.requireValue,
                accounts: accounts.requireValue,
              ),
      ),
    );
  }

  Widget _content({
    required String ownerId,
    required List<ElectricityBillingRecord> electricityRecords,
    required List<WaterBillingRecord> waterRecords,
    required List<RentBillingRecord> rentRecords,
    required List<MonthlyBillingCycle> cycles,
    required List<BillingCycleControl> controls,
    required List<BoarderBillAccount> accounts,
  }) {
    final electricity = _matching(
      electricityRecords,
      (item) => item.startDate,
      (item) => item.endDateExclusive,
    );
    final water = _matching(
      waterRecords,
      (item) => item.startDate,
      (item) => item.endDateExclusive,
    );
    final rent = _matching(
      rentRecords,
      (item) => item.startDate,
      (item) => item.endDateExclusive,
    );
    final controlsById = {
      for (final item in controls) item.billingCycleId: item,
    };
    final activeDuplicate = cycles.any(
      (cycle) =>
          cycle.startDate == _startDate &&
          cycle.endDateExclusive == _endDateExclusive &&
          controlsById[cycle.billingCycleId]?.state == BillingCycleState.active,
    );
    final ready =
        electricity != null &&
        water != null &&
        rent != null &&
        !activeDuplicate;
    return ListView(
      children: [
        AdaptivePageBody(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Select billing period',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'All three finalized source records must use these exact dates. The end date is not billable.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked =
                      constraints.maxWidth < 560 ||
                      MediaQuery.textScalerOf(context).scale(16) > 20;
                  final start = _DateField(
                    label: 'First billable day',
                    value: _startDate,
                    lastDate: _endDateExclusive.addDays(-1),
                    onChanged: (value) {
                      _startDate = value;
                      _invalidate();
                    },
                  );
                  final end = _DateField(
                    label: 'End date (not billed)',
                    value: _endDateExclusive,
                    firstDate: _startDate.addDays(1),
                    onChanged: (value) {
                      _endDateExclusive = value;
                      _invalidate();
                    },
                  );
                  if (stacked) {
                    return Column(
                      children: [start, const SizedBox(height: 12), end],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: start),
                      const SizedBox(width: 12),
                      Expanded(child: end),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Source records',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              _SourceCard(
                title: 'Electricity',
                ready: electricity != null,
                amount: electricity?.totalAllocatedCentavos,
                onOpen: () => context.push('/billing/electricity'),
              ),
              _SourceCard(
                title: 'Water',
                ready: water != null,
                amount: water?.totalAllocatedCentavos,
                onOpen: () => context.push('/billing/water'),
              ),
              _SourceCard(
                title: 'Rent & adjustments',
                ready: rent != null,
                amount: rent?.grandTotalCentavos,
                onOpen: () => context.push('/billing/rent'),
              ),
              if (activeDuplicate) ...[
                const SizedBox(height: 8),
                const BillingNotice(
                  isError: true,
                  message: 'This period is already finalized. Open its statement to record payments or void it before issuing a corrected version.',
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const Key('review-monthly-bill-button'),
                onPressed: ready
                    ? () => _calculate(
                        electricity: electricity,
                        water: water,
                        rent: rent,
                        cycles: cycles,
                        controls: controls,
                        accounts: accounts,
                      )
                    : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Review monthly bill'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                BillingNotice(message: _error!, isError: true),
              ],
              if (_result != null) ...[
                const SizedBox(height: 28),
                _Preview(result: _result!),
                const SizedBox(height: 18),
                FilledButton.icon(
                  key: const Key('finalize-monthly-bill-button'),
                  onPressed: _saving ? null : () => _save(ownerId),
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_outline_rounded),
                  label: Text(_saving ? 'Finalizing...' : 'Finalize bill'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.title,
    required this.ready,
    required this.amount,
    required this.onOpen,
  });
  final String title;
  final bool ready;
  final int? amount;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              ready
                  ? Icons.check_circle_outline_rounded
                  : Icons.warning_amber_rounded,
              color: ready ? colors.primary : colors.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    ready
                        ? '${formatPeso(amount)} allocated'
                        : 'Exact-date record required',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onOpen,
              child: Text(ready ? 'View' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.result});
  final MonthlyBillingResult result;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Final review',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                BillingValueRow(
                  label: 'Electricity allocated',
                  value: formatPeso(result.electricityTotalCentavos),
                ),
                BillingValueRow(
                  label: 'Water allocated',
                  value: formatPeso(result.waterTotalCentavos),
                ),
                BillingValueRow(
                  label: 'Rent',
                  value: formatPeso(result.rentTotalCentavos),
                ),
                BillingValueRow(
                  label: 'Rent adjustments',
                  value: _signedPeso(result.rentAdjustmentCentavos),
                ),
                const Divider(height: 24),
                BillingValueRow(
                  label: 'Total billed',
                  value: formatPeso(result.totalBilledCentavos),
                  emphasized: true,
                ),
                if (result.totalUnallocatedCentavos > 0)
                  BillingValueRow(
                    label: 'Landlady-paid / unallocated',
                    value: formatPeso(result.totalUnallocatedCentavos),
                  ),
              ],
            ),
          ),
        ),
        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...result.warnings.map(
            (warning) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BillingNotice(message: warning),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          'Boarder statements',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...result.statements.map(
          (statement) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    statement.boarderName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  BillingValueRow(
                    label: 'Current charges',
                    value: formatPeso(statement.currentChargesCentavos),
                    emphasized: true,
                  ),
                  if (statement.previousBalanceCentavos > 0)
                    BillingValueRow(
                      label: 'Previous unpaid balance (informational)',
                      value: formatPeso(statement.previousBalanceCentavos),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });
  final String label;
  final BusinessDate value;
  final ValueChanged<BusinessDate> onChanged;
  final BusinessDate? firstDate;
  final BusinessDate? lastDate;

  Future<void> _pick(BuildContext context) async {
    final first = firstDate ?? BusinessDate(2000, 1, 1);
    final last = lastDate ?? BusinessDate.todayInManila();
    final initial = value.isBefore(first)
        ? first
        : value.isAfter(last)
        ? last
        : value;
    final selected = await showDatePicker(
      context: context,
      helpText: label,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: DateTime(last.year, last.month, last.day),
    );
    if (selected != null) onChanged(BusinessDate.fromDateTime(selected));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, ${formatBusinessDate(value)}',
      child: InkWell(
        onTap: () => _pick(context),
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.calendar_today_outlined),
            suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
          ),
          child: Text(formatBusinessDate(value)),
        ),
      ),
    );
  }
}

String _signedPeso(int centavos) {
  if (centavos == 0) return formatPeso(0);
  return '${centavos > 0 ? '+' : '-'}${formatPeso(centavos.abs())}';
}
