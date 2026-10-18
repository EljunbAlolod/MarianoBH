import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/water_providers.dart';
import '../domain/water_batch_models.dart';
import '../domain/water_models.dart';
import 'water_batch_detail_screen.dart';
import 'water_formatters.dart';

class WaterBillingScreen extends ConsumerWidget {
  const WaterBillingScreen({super.key});

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
    final settings = ref.watch(waterSettingsProvider(ownerId));
    final records = ref.watch(waterBillingRecordsProvider(ownerId));
    final batches = ref.watch(waterBillingBatchesProvider(ownerId));
    final error = settings.hasError
        ? settings.error
        : records.hasError
        ? records.error
        : batches.error;
    final loading =
        settings.isLoading || records.isLoading || batches.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Water billing'),
        actions: [
          IconButton(
            tooltip: 'Refresh water data',
            onPressed: () {
              ref.invalidate(waterSettingsProvider(ownerId));
              ref.invalidate(waterBillingRecordsProvider(ownerId));
              ref.invalidate(waterBillingBatchesProvider(ownerId));
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: error != null
            ? AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Water data could not be loaded',
                  message: propertyErrorMessage(error),
                  actionLabel: 'Try again',
                  onAction: () {
                    ref.invalidate(waterSettingsProvider(ownerId));
                    ref.invalidate(waterBillingRecordsProvider(ownerId));
                    ref.invalidate(waterBillingBatchesProvider(ownerId));
                  },
                ),
              )
            : loading
            ? const Center(child: CircularProgressIndicator())
            : _WaterContent(
                ownerId: ownerId,
                settings: settings.requireValue,
                records: records.requireValue,
                batches: batches.requireValue,
              ),
      ),
    );
  }
}

class _WaterContent extends ConsumerWidget {
  const _WaterContent({
    required this.ownerId,
    required this.settings,
    required this.records,
    required this.batches,
  });

  final String ownerId;
  final WaterSettings settings;
  final List<WaterBillingRecord> records;
  final List<WaterBillingBatch> batches;

  Future<void> _editSettings(BuildContext context, WidgetRef ref) async {
    final updated = await showModalBottomSheet<WaterSettings>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _WaterSettingsSheet(initial: settings),
    );
    if (updated == null || !context.mounted) return;
    try {
      await ref
          .read(waterRepositoryProvider)
          .saveSettings(ownerId: ownerId, settings: updated);
      ref.invalidate(waterSettingsProvider(ownerId));
      if (context.mounted) {
        showPropertyMessage(context, 'Water settings saved.');
      }
    } catch (error) {
      if (context.mounted) {
        showPropertyMessage(
          context,
          propertyErrorMessage(error),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(waterSettingsProvider(ownerId));
        ref.invalidate(waterBillingRecordsProvider(ownerId));
        ref.invalidate(waterBillingBatchesProvider(ownerId));
        await Future.wait([
          ref.read(waterBillingRecordsProvider(ownerId).future),
          ref.read(waterBillingBatchesProvider(ownerId).future),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          AdaptivePageBody(
            maxWidth: 900,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Water allocation',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Allocate one bill fairly across the people who occupied each room during the selected period.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                _SettingsCard(
                  settings: settings,
                  onEdit: () => _editSettings(context, ref),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('create-water-batch-button'),
                  onPressed: () => context.push('/billing/water/batches/new'),
                  icon: const Icon(Icons.add_outlined),
                  label: const Text('Create water batch'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('calculate-water-button'),
                  onPressed: () => context.push('/billing/water/new'),
                  icon: const Icon(Icons.history_outlined),
                  label: const Text('Calculate historical water period'),
                ),
                const SizedBox(height: 28),
                Text(
                  'Water batches',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (batches.isEmpty)
                  const PropertyStatePanel(
                    icon: Icons.inventory_2_outlined,
                    title: 'No water batches yet',
                    message: 'Create a draft from a provider statement, then review and finalize its allocation.',
                  )
                else
                  ...batches.map(
                    (batch) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _BatchCard(batch: batch),
                    ),
                  ),
                const SizedBox(height: 28),
                Text(
                  'Historical water records',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (records.isEmpty)
                  const PropertyStatePanel(
                    icon: Icons.water_drop_outlined,
                    title: 'No water records yet',
                    message: 'Completed calculations will appear here as read-only records.',
                  )
                else
                  ...records.map(
                    (record) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RecordCard(record: record),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({required this.batch});

  final WaterBillingBatch batch;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(
          batch.batchReference,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${formatWaterPeriod(batch.startDate, batch.endDateExclusive)} · ${formatWaterBatchStatus(batch.status)} · ${formatPeso(batch.waterBillCentavos)}',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push(
          '/billing/water/batches/${Uri.encodeComponent(batch.batchId)}',
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.settings, required this.onEdit});

  final WaterSettings settings;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Allocation settings',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit water settings',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ValueRow(
              label: 'Default method',
              value: formatWaterMethod(settings.defaultMethod),
            ),
            _ValueRow(
              label: 'Summer months',
              value: formatMonthList(settings.summerMonths),
            ),
            _ValueRow(
              label: 'Summer basis',
              value: formatSummerBasis(settings.summerBasis),
            ),
            _ValueRow(
              label: 'Manual override',
              value: settings.allowManualMethodOverride ? 'Allowed' : 'Locked',
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});

  final WaterBillingRecord record;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: const Icon(Icons.water_drop_outlined),
        title: Text(
          formatWaterPeriod(record.startDate, record.endDateExclusive),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${formatWaterMethod(record.method)} · ${formatPeso(record.waterBillCentavos)}',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push(
          '/billing/water/${Uri.encodeComponent(record.waterRecordId)}',
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaterSettingsSheet extends StatefulWidget {
  const _WaterSettingsSheet({required this.initial});

  final WaterSettings initial;

  @override
  State<_WaterSettingsSheet> createState() => _WaterSettingsSheetState();
}

class _WaterSettingsSheetState extends State<_WaterSettingsSheet> {
  late WaterBillingMethod _method;
  late SummerElectricityBasis _basis;
  late Set<int> _months;
  late bool _allowOverride;

  @override
  void initState() {
    super.initState();
    _method = widget.initial.defaultMethod;
    _basis = widget.initial.summerBasis;
    _months = widget.initial.summerMonths.toSet();
    _allowOverride = widget.initial.allowManualMethodOverride;
  }

  @override
  Widget build(BuildContext context) {
    const monthLabels = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Water settings',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<WaterBillingMethod>(
                initialValue: _method,
                decoration: const InputDecoration(
                  labelText: 'Default allocation method',
                  helperText: 'Used outside the selected summer months.',
                ),
                items: WaterBillingMethod.values
                    .map(
                      (method) => DropdownMenuItem(
                        value: method,
                        child: Text(formatWaterMethod(method)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _method = value!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<SummerElectricityBasis>(
                initialValue: _basis,
                decoration: const InputDecoration(
                  labelText: 'Summer electricity basis',
                  helperText: 'Charge excludes documented adjustments.',
                ),
                items: SummerElectricityBasis.values
                    .map(
                      (basis) => DropdownMenuItem(
                        value: basis,
                        child: Text(formatSummerBasis(basis)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _basis = value!),
              ),
              const SizedBox(height: 20),
              Text(
                'Summer months',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Electricity percentage is recommended when the period starts in one of these months.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (var index = 0; index < 12; index++)
                    FilterChip(
                      label: Text(monthLabels[index]),
                      selected: _months.contains(index + 1),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _months.add(index + 1);
                          } else if (_months.length > 1) {
                            _months.remove(index + 1);
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow method override'),
                subtitle: const Text(
                  'Let the calculation screen change the recommended method.',
                ),
                value: _allowOverride,
                onChanged: (value) => setState(() => _allowOverride = value),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('save-water-settings-button'),
                onPressed: () {
                  Navigator.pop(
                    context,
                    WaterSettings(
                      defaultMethod: _method,
                      summerBasis: _basis,
                      summerMonths: (_months.toList()..sort()),
                      allowManualMethodOverride: _allowOverride,
                    ),
                  );
                },
                child: const Text('Save settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
