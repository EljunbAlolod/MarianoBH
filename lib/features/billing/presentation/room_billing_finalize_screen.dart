import 'package:flutter/material.dart';

import '../../../shared/widgets/app_components.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../electricity/application/electricity_providers.dart';
import '../../electricity/domain/electricity_batch_models.dart';
import '../../electricity/presentation/electricity_formatters.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../../water/application/water_providers.dart';
import '../../water/domain/water_batch_models.dart';
import '../../water/presentation/water_formatters.dart';
import '../application/monthly_billing_providers.dart';
import '../domain/utility_billing_models.dart';
import 'monthly_billing_widgets.dart';

class RoomBillingFinalizeScreen extends ConsumerStatefulWidget {
  const RoomBillingFinalizeScreen({super.key, this.initialStartDate});

  // Kept for old deep links. Combined billing no longer assumes one month.
  final BusinessDate? initialStartDate;

  @override
  ConsumerState<RoomBillingFinalizeScreen> createState() =>
      _RoomBillingFinalizeScreenState();
}

class _RoomBillingFinalizeScreenState
    extends ConsumerState<RoomBillingFinalizeScreen> {
  String? _electricityBatchId;
  String? _waterBatchId;
  bool _associationMismatchConfirmed = false;
  UtilityBillingResult? _result;
  String? _error;
  bool _saving = false;

  T? _find<T>(List<T> values, bool Function(T) matches) =>
      values.where(matches).firstOrNull;

  void _invalidate() {
    setState(() {
      _result = null;
      _error = null;
    });
  }

  void _review({
    required ElectricityReadingBatch? electricity,
    required WaterBillingBatch? water,
  }) {
    if (electricity == null || water == null) {
      setState(
        () => _error = 'Select one electricity batch and one water batch.',
      );
      return;
    }
    try {
      final result = const UtilityBillingAssembler().assemble(
        issuedOn: BusinessDate.todayInManila(),
        electricity: electricity,
        water: water,
        associationMismatchConfirmed: _associationMismatchConfirmed,
      );
      setState(() {
        _result = result;
        _error = null;
      });
    } on UtilityBillingException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _finalize(String ownerId) async {
    final result = _result;
    if (result == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.lock_outline),
        title: const Text('Finalize room utility bills?'),
        content: const Text(
          'The electricity and water batches will be locked as used. This creates one immutable bill for each room and does not include rent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep reviewing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Finalize bills'),
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
          .finalizeUtilityBillingBatch(ownerId: ownerId, result: result);
      ref
        ..invalidate(utilityBillingBatchesProvider(ownerId))
        ..invalidate(electricityReadingBatchesProvider(ownerId))
        ..invalidate(waterBillingBatchesProvider(ownerId));
      if (mounted) context.go('/billing/utility/$id');
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
          icon: Icons.lock_outline,
          title: 'Owner workspace unavailable',
          message: 'Return to the dashboard and try again.',
        ),
      );
    }
    final ownerId = workspace.ownerUid;
    final electricity = ref.watch(electricityReadingBatchesProvider(ownerId));
    final water = ref.watch(waterBillingBatchesProvider(ownerId));
    final sources = [electricity, water];
    final failure = sources.where((source) => source.hasError).firstOrNull;
    final loading = sources.any((source) => source.isLoading);
    return Scaffold(
      appBar: AppBar(title: const Text('Create room bills')),
      body: SafeArea(
        child: failure != null
            ? ListView(
                children: [
                  AdaptivePageBody(
                    child: PropertyStatePanel(
                      icon: Icons.cloud_off_outlined,
                      title: 'Utility batches could not be loaded',
                      message: propertyErrorMessage(failure.error!),
                      actionLabel: 'Try again',
                      onAction: () {
                        ref.invalidate(
                          electricityReadingBatchesProvider(ownerId),
                        );
                        ref.invalidate(waterBillingBatchesProvider(ownerId));
                      },
                    ),
                  ),
                ],
              )
            : loading
            ? const Center(child: CircularProgressIndicator())
            : _content(
                ownerId: ownerId,
                electricityBatches: electricity.requireValue
                    .where(
                      (batch) =>
                          batch.status ==
                          ElectricityReadingBatchStatus.finalized,
                    )
                    .toList(),
                waterBatches: water.requireValue
                    .where(
                      (batch) =>
                          batch.status == WaterBillingBatchStatus.finalized,
                    )
                    .toList(),
              ),
      ),
    );
  }

  Widget _content({
    required String ownerId,
    required List<ElectricityReadingBatch> electricityBatches,
    required List<WaterBillingBatch> waterBatches,
  }) {
    final selectedWater = _find(
      waterBatches,
      (batch) => batch.batchId == _waterBatchId,
    );
    final selectedElectricity = _find(
      electricityBatches,
      (batch) => batch.batchId == _electricityBatchId,
    );
    final mismatch =
        selectedWater?.electricityBatchId != null &&
        selectedWater!.electricityBatchId != selectedElectricity?.batchId;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        AdaptivePageBody(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _result == null
                    ? 'Select utility batches'
                    : 'Review room bills',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                _result == null
                    ? 'Choose existing finalized snapshots. Electricity and water dates remain independent; rent is managed separately.'
                    : 'Confirm the source periods and room totals before locking both utility batches as used.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              WorkflowProgress(
                steps: const ['Select batches', 'Review'],
                current: _result == null ? 0 : 1,
              ),
              if (_result == null) ...[
                _SectionHeading(
                  title: '1. Electricity batch',
                  actionLabel: 'Create batch',
                  onAction: () =>
                      context.push('/billing/electricity/batches/new'),
                ),
                const SizedBox(height: 8),
                if (electricityBatches.isEmpty)
                  const PropertyStatePanel(
                    icon: Icons.electric_meter_outlined,
                    title: 'No available electricity batch',
                    message: 'Finalize a new electricity reading batch first.',
                  )
                else
                  ...electricityBatches.map(
                    (batch) => _SelectableSourceCard(
                      key: Key('select-electricity-${batch.batchId}'),
                      selected: batch.batchId == _electricityBatchId,
                      recommended:
                          selectedWater?.electricityBatchId == batch.batchId,
                      title: batch.batchReference,
                      period:
                          '${formatBusinessDate(electricityBatchMeasurementStart(batch))} – ${formatBusinessDate(batch.effectiveDate)}',
                      amount: batch.totalChargeCentavos,
                      detail:
                          '${formatElectricityReading(batch.totalConsumptionWh)} · ${formatElectricityRate(batch.rateMicropesosPerKwh)}',
                      onTap: _saving
                          ? null
                          : () {
                              _electricityBatchId = batch.batchId;
                              _associationMismatchConfirmed = false;
                              _invalidate();
                            },
                    ),
                  ),
                const SizedBox(height: 24),
                _SectionHeading(
                  title: '2. Water batch',
                  actionLabel: 'Create batch',
                  onAction: () => context.push('/billing/water/batches/new'),
                ),
                const SizedBox(height: 8),
                if (waterBatches.isEmpty)
                  const PropertyStatePanel(
                    icon: Icons.water_drop_outlined,
                    title: 'No available water batch',
                    message: 'Finalize a new water batch first.',
                  )
                else
                  ...waterBatches.map(
                    (batch) => _SelectableSourceCard(
                      key: Key('select-water-${batch.batchId}'),
                      selected: batch.batchId == _waterBatchId,
                      recommended: false,
                      title: batch.batchReference,
                      period: formatWaterPeriod(
                        batch.startDate,
                        batch.endDateExclusive,
                      ),
                      amount: batch.waterBillCentavos,
                      detail:
                          '${formatWaterMethod(batch.method)} · received ${formatBusinessDate(batch.receiptDate)}',
                      onTap: _saving
                          ? null
                          : () {
                              _waterBatchId = batch.batchId;
                              _associationMismatchConfirmed = false;
                              _invalidate();
                            },
                    ),
                  ),
                if (selectedWater?.electricityBatchId != null) ...[
                  const SizedBox(height: 10),
                  BillingNotice(
                    message:
                        'Water allocation reference: ${selectedWater!.electricityBatchReference}. This reference calculated water percentages; it does not charge electricity again.',
                  ),
                ],
                if (mismatch) ...[
                  const SizedBox(height: 10),
                  Material(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: CheckboxListTile(
                      key: const Key('confirm-utility-association-mismatch'),
                      value: _associationMismatchConfirmed,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() {
                              _associationMismatchConfirmed = value ?? false;
                              _result = null;
                            }),
                      title: const Text(
                        'Use a different electricity batch for this bill',
                      ),
                      subtitle: Text(
                        'Water used ${selectedWater.electricityBatchReference}; the selected electricity charge is ${selectedElectricity?.batchReference ?? 'not selected'}.',
                      ),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  BillingNotice(message: _error!, isError: true),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  key: const Key('review-utility-bills-button'),
                  onPressed: _saving
                      ? null
                      : () => _review(
                          electricity: selectedElectricity,
                          water: selectedWater,
                        ),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Review room bills'),
                ),
              ] else ...[
                _UtilityReview(result: _result!),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  BillingNotice(message: _error!, isError: true),
                ],
                if (_saving) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  key: const Key('finalize-utility-bills-button'),
                  onPressed: _saving ? null : () => _finalize(ownerId),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Finalize room bills'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() => _result = null),
                  child: const Text('Back to selection'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Text(
        title,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      );
      final action = TextButton(onPressed: onAction, child: Text(actionLabel));
      if (constraints.maxWidth < 480 ||
          MediaQuery.textScalerOf(context).scale(16) > 20) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, action],
        );
      }
      return Row(
        children: [
          Expanded(child: heading),
          action,
        ],
      );
    },
  );
}

class _SelectableSourceCard extends StatelessWidget {
  const _SelectableSourceCard({
    required this.selected,
    required this.recommended,
    required this.title,
    required this.period,
    required this.amount,
    required this.detail,
    required this.onTap,
    super.key,
  });

  final bool selected;
  final bool recommended;
  final String title;
  final String period;
  final int amount;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: selected ? colors.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (recommended)
                          const Chip(label: Text('Water reference')),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(period),
                    Text(
                      detail,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      formatPeso(amount),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UtilityReview extends StatelessWidget {
  const _UtilityReview({required this.result});

  final UtilityBillingResult result;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.electricityBatchReference,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                'Electricity: ${formatBusinessDate(result.electricityMeasurementStart)} – ${formatBusinessDate(result.electricityMeasurementEnd)}',
              ),
              const SizedBox(height: 10),
              Text(
                result.waterBatchReference,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                'Water: ${formatWaterPeriod(result.waterPeriodStart, result.waterPeriodEndExclusive)}',
              ),
              const SizedBox(height: 10),
              Text(
                'Bill creation date: ${formatBusinessDate(result.issuedOn)}',
              ),
              const Text('Rent: not included'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      Text(
        'Room breakdown',
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
                  statement.roomName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                BillingValueRow(
                  label: 'Electricity',
                  value: formatPeso(statement.electricityCentavos),
                ),
                BillingValueRow(
                  label: 'Water',
                  value: formatPeso(statement.waterCentavos),
                ),
                const Divider(height: 18),
                BillingValueRow(
                  label: 'Room total',
                  value: formatPeso(statement.totalCentavos),
                  emphasized: true,
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      BillingValueRow(
        label: 'All room bills',
        value: formatPeso(result.totalBilledCentavos),
        emphasized: true,
      ),
      if (result.totalUnallocatedCentavos > 0)
        BillingValueRow(
          label: 'Landlady-paid / unallocated',
          value: formatPeso(result.totalUnallocatedCentavos),
        ),
      ...result.warnings.map(
        (warning) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: BillingNotice(message: warning),
        ),
      ),
    ],
  );
}
