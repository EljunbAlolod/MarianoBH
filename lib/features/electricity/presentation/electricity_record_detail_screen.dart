import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/electricity_providers.dart';
import '../domain/electricity_models.dart';
import 'electricity_formatters.dart';

class ElectricityRecordDetailScreen extends ConsumerWidget {
  const ElectricityRecordDetailScreen({required this.recordId, super.key});

  final String recordId;

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
    final records = ref.watch(electricityBillingRecordsProvider(ownerId));

    return records.when(
      loading: () => const Scaffold(
        appBar: _RecordAppBar(),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: const _RecordAppBar(),
        body: AdaptivePageBody(
          child: PropertyStatePanel(
            icon: Icons.cloud_off_outlined,
            title: 'Electricity record could not be loaded',
            message: propertyErrorMessage(error),
            actionLabel: 'Try again',
            onAction: () =>
                ref.invalidate(electricityBillingRecordsProvider(ownerId)),
          ),
        ),
      ),
      data: (items) {
        final record = _findRecord(items, recordId);
        if (record == null) {
          return const Scaffold(
            appBar: _RecordAppBar(),
            body: AdaptivePageBody(
              child: PropertyStatePanel(
                icon: Icons.receipt_long_outlined,
                title: 'Electricity record not found',
                message: 'This record is unavailable or does not belong to this boarding house.',
              ),
            ),
          );
        }
        return _RecordDetails(record: record);
      },
    );
  }
}

class _RecordAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _RecordAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(title: const Text('Electricity record'));
  }
}

class _RecordDetails extends StatelessWidget {
  const _RecordDetails({required this.record});

  final ElectricityBillingRecord record;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const _RecordAppBar(),
      body: SafeArea(
        child: ListView(
          children: [
            AdaptivePageBody(
              maxWidth: 900,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RecordHeader(record: record),
                  const SizedBox(height: 16),
                  _RecordSummary(record: record),
                  if (record.warnings.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Calculation notes',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    ...record.warnings.map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _RecordNotice(message: warning),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Room breakdown',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Room names, boarder names, meter readings, adjustments, and shares are preserved as they were when this record was saved.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (record.roomCharges.isEmpty)
                    const PropertyStatePanel(
                      icon: Icons.meeting_room_outlined,
                      title: 'No room charges',
                      message: 'This historical record has no room breakdown.',
                    )
                  else
                    ...record.roomCharges.map(
                      (room) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _RoomRecordCard(room: room),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordHeader extends StatelessWidget {
  const _RecordHeader({required this.record});

  final ElectricityBillingRecord record;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusPill(
              label: 'Read-only historical record',
              icon: Icons.lock_outline_rounded,
              background: colors.primaryContainer,
              foreground: colors.onPrimaryContainer,
            ),
            const SizedBox(height: 16),
            Text(
              formatElectricityPeriod(
                record.startDate,
                record.endDateExclusive,
              ),
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Saved ${_formatTimestamp(record.recordedAt)}. Later meter readings or occupancy changes do not alter this snapshot.',
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordSummary extends StatelessWidget {
  const _RecordSummary({required this.record});

  final ElectricityBillingRecord record;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _RecordValueRow(
              label: 'Rate',
              value: formatElectricityRate(record.rateMicropesosPerKwh),
            ),
            _RecordValueRow(
              label: 'Total consumption',
              value: formatElectricityReading(record.totalConsumptionWh),
            ),
            _RecordValueRow(
              label: 'Base charges',
              value: formatPeso(record.totalBaseChargeCentavos),
            ),
            _RecordValueRow(
              label: 'Adjustments',
              value: formatSignedPeso(record.totalAdjustmentsCentavos),
            ),
            const Divider(height: 24),
            _RecordValueRow(
              label: 'Total electricity',
              value: formatPeso(record.totalChargeCentavos),
              emphasized: true,
            ),
            _RecordValueRow(
              label: 'Allocated to boarders',
              value: formatPeso(record.totalAllocatedCentavos),
            ),
            _RecordValueRow(
              label: 'Unallocated / landlady-paid',
              value: formatPeso(record.totalUnallocatedCentavos),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomRecordCard extends StatelessWidget {
  const _RoomRecordCard({required this.room});

  final RoomElectricityCharge room;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  room.roomName,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (room.hasEstimatedShares)
                  StatusPill(
                    label: 'Estimated shares',
                    icon: Icons.info_outline_rounded,
                    background: colors.tertiaryContainer,
                    foreground: colors.onTertiaryContainer,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _RecordValueRow(
              label: 'Consumption',
              value: formatElectricityReading(room.consumptionWh),
            ),
            _RecordValueRow(
              label: 'Base charge',
              value: formatPeso(room.baseChargeCentavos),
            ),
            if (room.adjustmentCentavos != 0)
              _RecordValueRow(
                label: 'Documented adjustments',
                value: formatSignedPeso(room.adjustmentCentavos),
              ),
            _RecordValueRow(
              label: 'Room total',
              value: formatPeso(room.finalChargeCentavos),
              emphasized: true,
            ),
            const Divider(height: 28),
            _SubsectionTitle(
              icon: Icons.people_outline_rounded,
              label: 'Boarder shares',
            ),
            const SizedBox(height: 8),
            if (room.boarderShares.isEmpty && room.unallocatedCentavos == 0)
              const Text('No charge was available to allocate.')
            else ...[
              ...room.boarderShares.map(
                (share) => _RecordValueRow(
                  label:
                      '${share.boarderName} · ${share.occupancyDays} ${share.occupancyDays == 1 ? 'day' : 'days'}${share.isEstimated ? ' · estimate' : ''}',
                  value: formatPeso(share.amountCentavos),
                ),
              ),
              if (room.unallocatedCentavos > 0)
                _RecordValueRow(
                  label: 'Unallocated / landlady-paid',
                  value: formatPeso(room.unallocatedCentavos),
                ),
            ],
            if (room.adjustments.isNotEmpty) ...[
              const Divider(height: 28),
              const _SubsectionTitle(
                icon: Icons.tune_rounded,
                label: 'Documented adjustments',
              ),
              const SizedBox(height: 8),
              ...room.adjustments.map(
                (adjustment) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AdjustmentRecord(adjustment: adjustment),
                ),
              ),
            ],
            const Divider(height: 28),
            const _SubsectionTitle(
              icon: Icons.timeline_rounded,
              label: 'Reading intervals',
            ),
            const SizedBox(height: 8),
            if (room.segments.isEmpty)
              const Text('No reading intervals were stored for this room.')
            else
              ...room.segments.indexed.map(
                (entry) => Padding(
                  padding: EdgeInsets.only(
                    bottom: entry.$1 == room.segments.length - 1 ? 0 : 10,
                  ),
                  child: _SegmentRecord(
                    segment: entry.$2,
                    number: entry.$1 + 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SegmentRecord extends StatelessWidget {
  const _SegmentRecord({required this.segment, required this.number});

  final ElectricitySegmentSnapshot segment;
  final int number;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (
      qualityLabel,
      background,
      foreground,
    ) = switch (segment.allocationQuality) {
      ElectricityAllocationQuality.exact => (
        'Exact allocation',
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      ElectricityAllocationQuality.estimated => (
        'Estimated allocation',
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
      ),
      ElectricityAllocationQuality.unallocated => (
        'Unallocated',
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                  'Interval $number · sequence ${segment.sequence}',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                StatusPill(
                  label: qualityLabel,
                  icon:
                      segment.allocationQuality ==
                          ElectricityAllocationQuality.exact
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                  background: background,
                  foreground: foreground,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${formatBusinessDate(segment.startDate)} → ${formatBusinessDate(segment.endDateExclusive)}',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            _RecordValueRow(
              label: 'Previous reading',
              value: formatElectricityReading(segment.previousReadingWh),
            ),
            _RecordValueRow(
              label: 'Current reading',
              value: formatElectricityReading(segment.currentReadingWh),
            ),
            _RecordValueRow(
              label: 'Consumption',
              value: formatElectricityReading(segment.consumptionWh),
            ),
            _RecordValueRow(
              label: 'Interval charge',
              value: formatPeso(segment.chargeCentavos),
              emphasized: true,
            ),
            if (segment.boarderShares.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...segment.boarderShares.map(
                (share) => _RecordValueRow(
                  label:
                      '${share.boarderName} · ${share.occupancyDays} ${share.occupancyDays == 1 ? 'day' : 'days'}',
                  value: formatPeso(share.amountCentavos),
                ),
              ),
            ],
            if (segment.unallocatedCentavos > 0)
              _RecordValueRow(
                label: 'Unallocated',
                value: formatPeso(segment.unallocatedCentavos),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdjustmentRecord extends StatelessWidget {
  const _AdjustmentRecord({required this.adjustment});

  final ElectricityAdjustment adjustment;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RecordValueRow(
              label: formatBusinessDate(adjustment.adjustmentDate),
              value: formatSignedPeso(adjustment.signedCentavos),
              emphasized: true,
            ),
            const SizedBox(height: 4),
            Text(adjustment.reason),
          ],
        ),
      ),
    );
  }
}

class _SubsectionTitle extends StatelessWidget {
  const _SubsectionTitle({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ExcludeSemantics(child: Icon(icon, size: 20)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _RecordValueRow extends StatelessWidget {
  const _RecordValueRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800)
        : Theme.of(context).textTheme.bodyMedium;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(16) > 22;
        if (stacked) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label, style: style),
                const SizedBox(height: 2),
                Text(value, style: style),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: Text(label, style: style)),
              const SizedBox(width: 12),
              Flexible(
                flex: 2,
                child: Text(value, textAlign: TextAlign.end, style: style),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecordNotice extends StatelessWidget {
  const _RecordNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.tertiaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: colors.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

ElectricityBillingRecord? _findRecord(
  List<ElectricityBillingRecord> items,
  String recordId,
) {
  for (final record in items) {
    if (record.billingRecordId == recordId) return record;
  }
  return null;
}

String _formatTimestamp(DateTime value) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '${months[local.month - 1]} ${local.day}, ${local.year} at $hour:$minute $period';
}
