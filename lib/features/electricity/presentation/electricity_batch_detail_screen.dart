import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/electricity_providers.dart';
import '../domain/electricity_batch_models.dart';
import '../domain/electricity_repository.dart';
import 'electricity_formatters.dart';

class ElectricityBatchDetailScreen extends ConsumerWidget {
  const ElectricityBatchDetailScreen({required this.batchId, super.key});

  final String batchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(appSessionProvider).state.workspace;
    if (workspace == null) {
      return const Scaffold(
        body: PropertyStatePanel(
          icon: Icons.lock_outline,
          title: 'Workspace unavailable',
          message: 'Return to the dashboard and try again.',
        ),
      );
    }
    final ownerId = workspace.ownerUid;
    final batches = ref.watch(electricityReadingBatchesProvider(ownerId));
    return Scaffold(
      appBar: AppBar(title: const Text('Reading batch')),
      body: SafeArea(
        child: batches.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: [
              AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Batch could not be loaded',
                  message: propertyErrorMessage(error),
                  actionLabel: 'Try again',
                  onAction: () => ref.invalidate(
                    electricityReadingBatchesProvider(ownerId),
                  ),
                ),
              ),
            ],
          ),
          data: (items) {
            final batch = items
                .where((item) => item.batchId == batchId)
                .firstOrNull;
            if (batch == null) {
              return ListView(
                children: [
                  AdaptivePageBody(
                    child: PropertyStatePanel(
                      icon: Icons.search_off_outlined,
                      title: 'Batch not found',
                      message:
                          'It may have been removed or is no longer available.',
                      actionLabel: 'Back to electricity',
                      onAction: () => context.go('/billing/electricity'),
                    ),
                  ),
                ],
              );
            }
            return _BatchDetails(ownerId: ownerId, batch: batch);
          },
        ),
      ),
    );
  }
}

class _BatchDetails extends ConsumerWidget {
  const _BatchDetails({required this.ownerId, required this.batch});

  final String ownerId;
  final ElectricityReadingBatch batch;

  Future<void> _voidBatch(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Void reading batch?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Voiding this batch does not delete its meter readings. If a reading is wrong, correct the latest eligible reading from that room’s history.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('void-batch-reason'),
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Reason',
                helperText: 'Required, 3–500 characters',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final clean = controller.text.trim();
              if (clean.length >= 3) Navigator.pop(dialogContext, clean);
            },
            child: const Text('Void batch'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !context.mounted) return;
    try {
      await ref
          .read(electricityRepositoryProvider)
          .voidReadingBatch(
            ownerId: ownerId,
            batchId: batch.batchId,
            reason: reason,
          );
      if (!context.mounted) return;
      ref.invalidate(electricityReadingBatchesProvider(ownerId));
      showPropertyMessage(
        context,
        'Reading batch voided. Room readings were preserved.',
      );
    } on ElectricityRepositoryException catch (error) {
      if (context.mounted) {
        showPropertyMessage(context, error.message, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final status = _statusStyle(batch.status, colors);
    return ListView(
      children: [
        AdaptivePageBody(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.batchReference,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatElectricityDateTime(batch.effectiveAt),
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                  StatusPill(
                    label: formatElectricityBatchStatus(batch.status),
                    icon: status.icon,
                    background: status.background,
                    foreground: status.foreground,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${formatElectricityReading(batch.totalConsumptionWh)} · ${formatPeso(batch.totalChargeCentavos)}',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${formatElectricityRate(batch.rateMicropesosPerKwh)} · ${batch.recordedCount} recorded · ${batch.excludedCount} excluded',
                      ),
                    ],
                  ),
                ),
              ),
              if (batch.status == ElectricityReadingBatchStatus.voided) ...[
                const SizedBox(height: 12),
                Material(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Voided: ${batch.voidReason ?? 'No reason recorded.'}\nThe room meter readings remain in history.',
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Room readings',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (var index = 0; index < batch.entries.length; index++) ...[
                _BatchEntryCard(entry: batch.entries[index]),
                if (index != batch.entries.length - 1)
                  const SizedBox(height: 10),
              ],
              const SizedBox(height: 20),
              if (batch.canEdit)
                FilledButton.icon(
                  onPressed: () => context.push(
                    '/billing/electricity/batches/${batch.batchId}/edit',
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Continue editing draft'),
                ),
              if (batch.canVoid)
                OutlinedButton.icon(
                  key: const Key('void-reading-batch'),
                  onPressed: () => _voidBatch(context, ref),
                  icon: const Icon(Icons.block_outlined),
                  label: const Text('Void batch'),
                ),
              if (batch.status == ElectricityReadingBatchStatus.finalized) ...[
                const SizedBox(height: 10),
                Text(
                  'Finalized readings are read-only here. Use each room’s reading history for a controlled correction.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BatchEntryCard extends StatelessWidget {
  const _BatchEntryCard({required this.entry});

  final ElectricityReadingBatchEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final excluded = entry.status == ElectricityBatchEntryStatus.excluded;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.roomName,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(
                  excluded
                      ? Icons.remove_circle_outline
                      : Icons.check_circle_outline,
                  color: excluded ? colors.onSurfaceVariant : colors.primary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (excluded)
              Text('Excluded · ${entry.exclusionReason}')
            else ...[
              Text(
                '${formatElectricityReading(entry.previousReadingWh)} → ${formatElectricityReading(entry.currentReadingWh ?? entry.previousReadingWh)}',
              ),
              const SizedBox(height: 4),
              Text(
                '${formatElectricityReading(entry.consumptionWh)} · ${formatPeso(entry.chargeCentavos)}',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

_BatchStatusStyle _statusStyle(
  ElectricityReadingBatchStatus status,
  ColorScheme colors,
) {
  return switch (status) {
    ElectricityReadingBatchStatus.draft => _BatchStatusStyle(
      Icons.edit_note_outlined,
      colors.secondaryContainer,
      colors.onSecondaryContainer,
    ),
    ElectricityReadingBatchStatus.finalized => _BatchStatusStyle(
      Icons.lock_outline,
      colors.primaryContainer,
      colors.onPrimaryContainer,
    ),
    ElectricityReadingBatchStatus.usedInBilling => _BatchStatusStyle(
      Icons.receipt_long_outlined,
      colors.tertiaryContainer,
      colors.onTertiaryContainer,
    ),
    ElectricityReadingBatchStatus.voided => _BatchStatusStyle(
      Icons.block_outlined,
      colors.errorContainer,
      colors.onErrorContainer,
    ),
  };
}

class _BatchStatusStyle {
  const _BatchStatusStyle(this.icon, this.background, this.foreground);
  final IconData icon;
  final Color background;
  final Color foreground;
}
