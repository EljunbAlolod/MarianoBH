import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/water_providers.dart';
import '../domain/water_batch_models.dart';
import '../domain/water_repository.dart';
import 'water_formatters.dart';
import 'water_selection_panel.dart';

class WaterBatchDetailScreen extends ConsumerWidget {
  const WaterBatchDetailScreen({required this.batchId, super.key});

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
    final batches = ref.watch(waterBillingBatchesProvider(ownerId));
    return Scaffold(
      appBar: AppBar(title: const Text('Water batch')),
      body: SafeArea(
        child: batches.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: [
              AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Water batch could not be loaded',
                  message: propertyErrorMessage(error),
                  actionLabel: 'Try again',
                  onAction: () =>
                      ref.invalidate(waterBillingBatchesProvider(ownerId)),
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
                      title: 'Water batch not found',
                      message: 'It may no longer be available.',
                      actionLabel: 'Back to water billing',
                      onAction: () => context.go('/billing/water'),
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
  final WaterBillingBatch batch;

  Future<void> _voidBatch(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Void water batch?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This keeps the finalized snapshot and its audit history. It does not change the electricity batch used as an allocation reference.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('void-water-batch-reason'),
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
          .read(waterRepositoryProvider)
          .voidBillingBatch(
            ownerId: ownerId,
            batchId: batch.batchId,
            reason: reason,
          );
      if (!context.mounted) return;
      ref.invalidate(waterBillingBatchesProvider(ownerId));
      showPropertyMessage(
        context,
        'Water batch voided. Its snapshot was preserved.',
      );
    } on WaterRepositoryException catch (error) {
      if (context.mounted) {
        showPropertyMessage(context, error.message, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final style = _statusStyle(batch.status, colors);
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
                        formatWaterPeriod(
                          batch.startDate,
                          batch.endDateExclusive,
                        ),
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                  StatusPill(
                    label: formatWaterBatchStatus(batch.status),
                    icon: style.icon,
                    background: style.background,
                    foreground: style.foreground,
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
                        formatPeso(batch.waterBillCentavos),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${formatWaterMethod(batch.method)} · received ${formatBusinessDate(batch.receiptDate)}',
                      ),
                      const Divider(height: 24),
                      Text(
                        '${formatPeso(batch.totalAllocatedCentavos)} allocated',
                      ),
                      Text(
                        '${formatPeso(batch.totalUnallocatedCentavos)} landlady-paid',
                      ),
                    ],
                  ),
                ),
              ),
              if (batch.electricityBatchId != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Electricity allocation reference',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          batch.electricityBatchReference ??
                              batch.electricityBatchId!,
                        ),
                        if (batch.electricityMeasurementStart != null &&
                            batch.electricityMeasurementEnd != null)
                          Text(
                            '${formatBusinessDate(batch.electricityMeasurementStart!)} – ${formatBusinessDate(batch.electricityMeasurementEnd!)}',
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Reference only — electricity is not billed again.',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        if (batch.referenceExplanation != null) ...[
                          const SizedBox(height: 8),
                          Text(batch.referenceExplanation!),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              if (batch.status == WaterBillingBatchStatus.voided) ...[
                const SizedBox(height: 12),
                Material(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Voided: ${batch.voidReason ?? 'No reason recorded.'}',
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (batch.decisions.isNotEmpty)
                WaterSelectionPanel(decisions: batch.decisions, preview: batch),
              Text(
                'Room allocation',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (final room in batch.roomAllocations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      title: Text(
                        room.roomName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text('${room.occupancyDays} occupancy-days'),
                      trailing: Text(
                        formatPeso(room.roomChargeCentavos),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              if (batch.notes != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Notes',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(batch.notes!),
              ],
              const SizedBox(height: 20),
              if (batch.canEdit)
                FilledButton.icon(
                  onPressed: () => context.push(
                    '/billing/water/batches/${batch.batchId}/edit',
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Continue editing draft'),
                ),
              if (batch.canVoid)
                OutlinedButton.icon(
                  key: const Key('void-water-batch'),
                  onPressed: () => _voidBatch(context, ref),
                  icon: const Icon(Icons.block_outlined),
                  label: const Text('Void batch'),
                ),
              if (batch.status == WaterBillingBatchStatus.finalized) ...[
                const SizedBox(height: 10),
                Text(
                  'This finalized allocation is read-only and ready for monthly billing.',
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

String formatWaterBatchStatus(WaterBillingBatchStatus status) =>
    switch (status) {
      WaterBillingBatchStatus.draft => 'Draft',
      WaterBillingBatchStatus.finalized => 'Finalized',
      WaterBillingBatchStatus.usedInBilling => 'Used in billing',
      WaterBillingBatchStatus.voided => 'Voided',
    };

_StatusStyle _statusStyle(WaterBillingBatchStatus status, ColorScheme colors) =>
    switch (status) {
      WaterBillingBatchStatus.draft => _StatusStyle(
        Icons.edit_note_outlined,
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      WaterBillingBatchStatus.finalized => _StatusStyle(
        Icons.lock_outline,
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      WaterBillingBatchStatus.usedInBilling => _StatusStyle(
        Icons.receipt_long_outlined,
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
      ),
      WaterBillingBatchStatus.voided => _StatusStyle(
        Icons.block_outlined,
        colors.errorContainer,
        colors.onErrorContainer,
      ),
    };

class _StatusStyle {
  const _StatusStyle(this.icon, this.background, this.foreground);
  final IconData icon;
  final Color background;
  final Color foreground;
}
