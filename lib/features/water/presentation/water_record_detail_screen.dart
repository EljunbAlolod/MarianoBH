import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/water_providers.dart';
import '../domain/water_models.dart';
import 'water_formatters.dart';

class WaterRecordDetailScreen extends ConsumerWidget {
  const WaterRecordDetailScreen({required this.recordId, super.key});

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
    final records = ref.watch(waterBillingRecordsProvider(ownerId));
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
            title: 'Water record could not be loaded',
            message: propertyErrorMessage(error),
            actionLabel: 'Try again',
            onAction: () =>
                ref.invalidate(waterBillingRecordsProvider(ownerId)),
          ),
        ),
      ),
      data: (items) {
        final record = items
            .where((item) => item.waterRecordId == recordId)
            .firstOrNull;
        if (record == null) {
          return const Scaffold(
            appBar: _RecordAppBar(),
            body: AdaptivePageBody(
              child: PropertyStatePanel(
                icon: Icons.receipt_long_outlined,
                title: 'Water record not found',
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
    return AppBar(title: const Text('Water record'));
  }
}

class _RecordDetails extends StatelessWidget {
  const _RecordDetails({required this.record});

  final WaterBillingRecord record;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
                  Card(
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
                            formatWaterPeriod(
                              record.startDate,
                              record.endDateExclusive,
                            ),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Saved ${_timestamp(record.recordedAt)}. Later occupancy or electricity changes do not alter this snapshot.',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Summary(record: record),
                  if (record.warnings.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Calculation notes',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    ...record.warnings.map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _Notice(message: warning),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Boarder shares',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  if (record.boarderShares.isEmpty)
                    const PropertyStatePanel(
                      icon: Icons.people_outline_rounded,
                      title: 'No boarder shares',
                      message:
                          'This period’s bill is zero or remained unallocated.',
                    )
                  else
                    ...record.boarderShares.map(
                      (share) => Card(
                        child: ListTile(
                          title: Text(
                            share.boarderName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${share.occupancyDays} ${share.occupancyDays == 1 ? 'person-day' : 'person-days'} · ${share.roomIds.length} ${share.roomIds.length == 1 ? 'room' : 'rooms'}',
                          ),
                          trailing: Text(
                            formatPeso(share.amountCentavos),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Room breakdown',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  ...record.roomAllocations.map(
                    (room) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RoomCard(room: room, method: record.method),
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

class _Summary extends StatelessWidget {
  const _Summary({required this.record});

  final WaterBillingRecord record;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _ValueRow(label: 'Method', value: formatWaterMethod(record.method)),
            if (record.method == WaterBillingMethod.electricityPercentage)
              _ValueRow(
                label: 'Electricity basis',
                value: formatSummerBasis(record.summerBasis),
              ),
            _ValueRow(
              label: 'Water bill',
              value: formatPeso(record.waterBillCentavos),
              emphasized: true,
            ),
            const Divider(height: 24),
            _ValueRow(
              label: record.method == WaterBillingMethod.roomDays
                  ? 'Allocated to rooms'
                  : 'Allocated to boarders',
              value: formatPeso(record.totalAllocatedCentavos),
            ),
            _ValueRow(
              label: 'Unallocated / landlady-paid',
              value: formatPeso(record.totalUnallocatedCentavos),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.method});

  final WaterRoomAllocation room;
  final WaterBillingMethod method;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              room.roomName,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (method == WaterBillingMethod.electricityPercentage ||
                method == WaterBillingMethod.roomDays)
              _ValueRow(
                label: 'Room water share',
                value: formatPeso(room.roomChargeCentavos),
              ),
            _ValueRow(
              label: method == WaterBillingMethod.roomDays
                  ? 'Occupied room-days'
                  : 'Occupancy days',
              value: '${room.occupancyDays}',
            ),
            _ValueRow(
              label: 'Allocated',
              value: formatPeso(room.allocatedCentavos),
            ),
            if (room.unallocatedCentavos > 0)
              _ValueRow(
                label: 'Unallocated / landlady-paid',
                value: formatPeso(room.unallocatedCentavos),
              ),
            if (room.boarderShares.isNotEmpty) ...[
              const Divider(height: 24),
              ...room.boarderShares.map(
                (share) => _ValueRow(
                  label:
                      '${share.boarderName} · ${share.occupancyDays} ${share.occupancyDays == 1 ? 'day' : 'days'}',
                  value: formatPeso(share.amountCentavos),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
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
    );
  }
}

String _timestamp(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour == 0
      ? 12
      : local.hour > 12
      ? local.hour - 12
      : local.hour;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.month}/${local.day}/${local.year} at $hour:$minute $suffix';
}
