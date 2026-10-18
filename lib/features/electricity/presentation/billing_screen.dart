import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/application/property_providers.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/domain/room.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/electricity_providers.dart';
import '../domain/electricity_batch_models.dart';
import '../domain/electricity_models.dart';
import 'electricity_formatters.dart';
import 'meter_forms.dart';

class BillingScreen extends ConsumerWidget {
  const BillingScreen({super.key});

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
    final rooms = ref.watch(roomsProvider(ownerId));
    final states = ref.watch(roomMeterStatesProvider(ownerId));
    final meters = ref.watch(electricityMetersProvider(ownerId));
    final readings = ref.watch(meterReadingsProvider(ownerId));
    final records = ref.watch(electricityBillingRecordsProvider(ownerId));
    final batches = ref.watch(electricityReadingBatchesProvider(ownerId));
    final sources = [rooms, states, meters, readings, records, batches];
    final errorSource = sources.where((item) => item.hasError).firstOrNull;
    final loading = sources.any((item) => item.isLoading);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Electricity billing'),
        actions: [
          IconButton(
            tooltip: 'Refresh electricity data',
            onPressed: () => _refresh(ref, ownerId),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: errorSource != null
            ? AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Electricity data could not be loaded',
                  message: propertyErrorMessage(errorSource.error!),
                  actionLabel: 'Try again',
                  onAction: () => _refresh(ref, ownerId),
                ),
              )
            : loading
            ? const Center(child: CircularProgressIndicator())
            : _BillingContent(
                ownerId: ownerId,
                rooms: rooms.requireValue,
                states: states.requireValue,
                meters: meters.requireValue,
                readings: readings.requireValue,
                records: records.requireValue,
                batches: batches.requireValue,
              ),
      ),
    );
  }

  void _refresh(WidgetRef ref, String ownerId) {
    ref.invalidate(roomsProvider(ownerId));
    ref.invalidate(roomMeterStatesProvider(ownerId));
    ref.invalidate(electricityMetersProvider(ownerId));
    ref.invalidate(meterReadingsProvider(ownerId));
    ref.invalidate(electricityBillingRecordsProvider(ownerId));
    ref.invalidate(electricityReadingBatchesProvider(ownerId));
  }
}

class _BillingContent extends ConsumerWidget {
  const _BillingContent({
    required this.ownerId,
    required this.rooms,
    required this.states,
    required this.meters,
    required this.readings,
    required this.records,
    required this.batches,
  });

  final String ownerId;
  final List<Room> rooms;
  final List<RoomMeterState> states;
  final List<ElectricityMeter> meters;
  final List<MeterReading> readings;
  final List<ElectricityBillingRecord> records;
  final List<ElectricityReadingBatch> batches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateByRoom = {for (final item in states) item.roomId: item};
    final meterById = {for (final item in meters) item.meterId: item};
    final sortedRooms = [...rooms]
      ..sort((a, b) {
        if (a.status != b.status) return a.isActive ? -1 : 1;
        return a.roomName.toLowerCase().compareTo(b.roomName.toLowerCase());
      });
    final configured = sortedRooms
        .where((room) => stateByRoom.containsKey(room.roomId))
        .length;
    final missingActive = sortedRooms
        .where((room) => room.isActive && !stateByRoom.containsKey(room.roomId))
        .length;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(roomsProvider(ownerId));
        ref.invalidate(roomMeterStatesProvider(ownerId));
        ref.invalidate(electricityMetersProvider(ownerId));
        ref.invalidate(meterReadingsProvider(ownerId));
        ref.invalidate(electricityBillingRecordsProvider(ownerId));
        ref.invalidate(electricityReadingBatchesProvider(ownerId));
        await ref.read(electricityMetersProvider(ownerId).future);
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
                  'Electricity meters',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Record dated readings, calculate exact room consumption, and preserve each rate and allocation as a read-only record.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                _ElectricitySummary(
                  configuredRooms: configured,
                  totalRooms: sortedRooms.length,
                  readingCount: readings.length,
                  recordCount: records.length,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('create-reading-batch-button'),
                  onPressed: missingActive == 0 && sortedRooms.isNotEmpty
                      ? () => context.push('/billing/electricity/batches/new')
                      : null,
                  icon: const Icon(Icons.playlist_add_check_rounded),
                  label: const Text('Create reading batch'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('calculate-electricity-button'),
                  onPressed: missingActive == 0 && sortedRooms.isNotEmpty
                      ? () => context.push('/billing/electricity/new')
                      : null,
                  icon: const Icon(Icons.calculate_outlined),
                  label: const Text('Calculate a historical period'),
                ),
                if (missingActive > 0) ...[
                  const SizedBox(height: 12),
                  _WarningPanel(
                    message:
                        'Set up a baseline meter for $missingActive active ${missingActive == 1 ? 'room' : 'rooms'} before calculating a period.',
                  ),
                ],
                const SizedBox(height: 28),
                Text(
                  'Reading batches',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'One dated batch records every active room together. Drafts can be resumed; finalized batches are read-only.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                if (batches.isEmpty)
                  const _BatchEmpty()
                else
                  ...batches.map(
                    (batch) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _BatchCard(batch: batch),
                    ),
                  ),
                const SizedBox(height: 28),
                Text(
                  'Room meters',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (sortedRooms.isEmpty)
                  const PropertyStatePanel(
                    icon: Icons.meeting_room_outlined,
                    title: 'No rooms yet',
                    message: 'Add a room before setting up electricity meters.',
                  )
                else
                  ...sortedRooms.map((room) {
                    final state = stateByRoom[room.roomId];
                    final meter = state == null
                        ? null
                        : meterById[state.currentMeterId];
                    final matchingReadings = readings
                        .where((item) => item.roomId == room.roomId)
                        .toList();
                    final latestReading = meter == null
                        ? null
                        : matchingReadings
                              .where(
                                (reading) =>
                                    reading.readingId == meter.lastReadingId,
                              )
                              .firstOrNull;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _MeterCard(
                        ownerId: ownerId,
                        room: room,
                        meter: meter,
                        latestReading: latestReading,
                        readingCount: matchingReadings.length,
                      ),
                    );
                  }),
                const SizedBox(height: 20),
                Text(
                  'Electricity history',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (records.isEmpty)
                  const _HistoryEmpty()
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

class _ElectricitySummary extends StatelessWidget {
  const _ElectricitySummary({
    required this.configuredRooms,
    required this.totalRooms,
    required this.readingCount,
    required this.recordCount,
  });

  final int configuredRooms;
  final int totalRooms;
  final int readingCount;
  final int recordCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(16) > 20;
        final stacked = constraints.maxWidth < 560 || largeText;
        final items = [
          _Metric(
            icon: Icons.electric_meter_outlined,
            value: '$configuredRooms / $totalRooms',
            label: 'Meters set up',
          ),
          _Metric(
            icon: Icons.show_chart_rounded,
            value: '$readingCount',
            label: 'Saved readings',
          ),
          _Metric(
            icon: Icons.receipt_long_outlined,
            value: '$recordCount',
            label: 'Recorded periods',
          ),
        ];
        if (stacked) {
          return Column(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                SizedBox(width: double.infinity, child: items[index]),
                if (index != items.length - 1) const SizedBox(height: 8),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              Expanded(child: items[index]),
              if (index != items.length - 1) const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(icon, color: colors.onSecondaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colors.onSecondaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(color: colors.onSecondaryContainer),
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

class _BatchCard extends StatelessWidget {
  const _BatchCard({required this.batch});

  final ElectricityReadingBatch batch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, background, foreground) = switch (batch.status) {
      ElectricityReadingBatchStatus.draft => (
        Icons.edit_note_outlined,
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      ElectricityReadingBatchStatus.finalized => (
        Icons.lock_outline,
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      ElectricityReadingBatchStatus.usedInBilling => (
        Icons.receipt_long_outlined,
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
      ),
      ElectricityReadingBatchStatus.voided => (
        Icons.block_outlined,
        colors.errorContainer,
        colors.onErrorContainer,
      ),
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(
          batch.canEdit
              ? '/billing/electricity/batches/${batch.batchId}/edit'
              : '/billing/electricity/batches/${batch.batchId}',
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          batch.batchReference,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatElectricityDateTime(batch.effectiveAt),
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  StatusPill(
                    label: formatElectricityBatchStatus(batch.status),
                    icon: icon,
                    background: background,
                    foreground: foreground,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${batch.roomCount} ${batch.roomCount == 1 ? 'room' : 'rooms'} · ${formatElectricityReading(batch.totalConsumptionWh)} · ${formatPeso(batch.totalChargeCentavos)}',
              ),
              if (batch.canEdit) ...[
                const SizedBox(height: 4),
                Text(
                  '${batch.pendingCount} pending · Tap to continue',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BatchEmpty extends StatelessWidget {
  const _BatchEmpty();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.playlist_add_check_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No reading batches yet',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Create the first batch to capture all active rooms on one effective date and time.',
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

class _MeterCard extends ConsumerWidget {
  const _MeterCard({
    required this.ownerId,
    required this.room,
    required this.meter,
    required this.latestReading,
    required this.readingCount,
  });

  final String ownerId;
  final Room room;
  final ElectricityMeter? meter;
  final MeterReading? latestReading;
  final int readingCount;

  Future<void> _initialize(BuildContext context, WidgetRef ref) async {
    final saved = await showInitializeMeterSheet(
      context,
      ownerId: ownerId,
      room: room,
    );
    if (saved == true && context.mounted) {
      showPropertyMessage(context, '${room.roomName} meter set up.');
    }
  }

  Future<void> _record(BuildContext context, WidgetRef ref) async {
    final saved = await showRecordReadingSheet(
      context,
      ownerId: ownerId,
      room: room,
      meter: meter!,
    );
    if (saved == true && context.mounted) {
      showPropertyMessage(context, '${room.roomName} reading saved.');
    }
  }

  Future<void> _transition(BuildContext context, WidgetRef ref) async {
    final saved = await showTransitionMeterSheet(
      context,
      ownerId: ownerId,
      room: room,
      meter: meter!,
    );
    if (saved == true && context.mounted) {
      showPropertyMessage(
        context,
        '${room.roomName} new meter sequence saved.',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final current = meter;
    final latestIsToday =
        current?.lastReadingDate == BusinessDate.todayInManila();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final roomDetails = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.roomName,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      current == null
                          ? 'Meter setup required'
                          : 'Sequence ${current.sequence} · $readingCount ${readingCount == 1 ? 'reading' : 'readings'}',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                );
                final status = StatusPill(
                  label: room.isActive ? 'Active room' : 'Inactive room',
                  icon: room.isActive
                      ? Icons.check_circle_outline_rounded
                      : Icons.pause_circle_outline_rounded,
                  background: room.isActive
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  foreground: room.isActive
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                );
                final stack =
                    constraints.maxWidth < 420 ||
                    MediaQuery.textScalerOf(context).scale(16) > 20;
                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [roomDetails, const SizedBox(height: 10), status],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: roomDetails),
                    const SizedBox(width: 12),
                    status,
                  ],
                );
              },
            ),
            if (current != null) ...[
              const SizedBox(height: 16),
              _ReadingFact(
                icon: Icons.speed_outlined,
                label: 'Latest reading',
                value: formatElectricityReading(current.lastReadingWh),
              ),
              const SizedBox(height: 10),
              _ReadingFact(
                icon: Icons.calendar_today_outlined,
                label: 'Reading date',
                value: formatBusinessDate(current.lastReadingDate),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                key: Key('reading-history-${room.roomId}'),
                onPressed: () => context.push(
                  '/billing/electricity/rooms/${room.roomId}/readings',
                ),
                icon: const Icon(Icons.history_rounded),
                label: const Text('View reading history'),
              ),
              if (latestReading != null &&
                  meterReadingCorrectionEligibility(
                        reading: latestReading!,
                        activeMeter: current,
                      ) ==
                      MeterReadingCorrectionEligibility.eligible) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: Key('correct-latest-reading-${room.roomId}'),
                  onPressed: () => context.push(
                    '/billing/electricity/rooms/${room.roomId}/readings/${latestReading!.readingId}/correct',
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Correct latest reading'),
                ),
              ],
            ],
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                if (current == null) {
                  return FilledButton.icon(
                    onPressed: room.isActive
                        ? () => _initialize(context, ref)
                        : null,
                    icon: const Icon(Icons.add_chart_rounded),
                    label: const Text('Set up baseline meter'),
                  );
                }
                final stack =
                    constraints.maxWidth < 430 ||
                    MediaQuery.textScalerOf(context).scale(16) > 20;
                final addButton = FilledButton.icon(
                  onPressed: latestIsToday ? null : () => _record(context, ref),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(
                    latestIsToday ? 'Reading saved today' : 'Add reading',
                  ),
                );
                final sequenceButton = OutlinedButton.icon(
                  onPressed: latestIsToday
                      ? null
                      : () => _transition(context, ref),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('New sequence'),
                );
                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      addButton,
                      const SizedBox(height: 8),
                      sequenceButton,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: addButton),
                    const SizedBox(width: 8),
                    Expanded(child: sequenceButton),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadingFact extends StatelessWidget {
  const _ReadingFact({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 20, color: color)),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: color),
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
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

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});

  final ElectricityBillingRecord record;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            context.push('/billing/electricity/${record.billingRecordId}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.receipt_long_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatElectricityPeriod(
                        record.startDate,
                        record.endDateExclusive,
                      ),
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatElectricityReading(record.totalConsumptionWh)} · ${formatPeso(record.totalChargeCentavos)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryEmpty extends StatelessWidget {
  const _HistoryEmpty();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(
              child: Icon(Icons.history_toggle_off_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No recorded periods yet',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Once boundary readings are available, calculate and save the first electricity record.',
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

class _WarningPanel extends StatelessWidget {
  const _WarningPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
