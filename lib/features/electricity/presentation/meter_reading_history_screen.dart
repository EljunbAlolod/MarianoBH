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
import '../domain/electricity_models.dart';
import '../domain/electricity_repository.dart';
import '../domain/electricity_values.dart';
import 'electricity_formatters.dart';

class MeterReadingHistoryScreen extends ConsumerWidget {
  const MeterReadingHistoryScreen({required this.roomId, super.key});

  final String roomId;

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
    final corrections = ref.watch(meterReadingCorrectionsProvider(ownerId));
    final records = ref.watch(electricityBillingRecordsProvider(ownerId));
    final sources = [rooms, states, meters, readings, corrections, records];
    final errorSource = sources.where((source) => source.hasError).firstOrNull;
    final loading = sources.any((source) => source.isLoading);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reading history'),
        actions: [
          IconButton(
            tooltip: 'Refresh reading history',
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
                  title: 'Reading history could not be loaded',
                  message: propertyErrorMessage(errorSource.error!),
                  actionLabel: 'Try again',
                  onAction: () => _refresh(ref, ownerId),
                ),
              )
            : loading
            ? const Center(child: CircularProgressIndicator())
            : _HistoryContent(
                ownerId: ownerId,
                roomId: roomId,
                rooms: rooms.requireValue,
                states: states.requireValue,
                meters: meters.requireValue,
                readings: readings.requireValue,
                corrections: corrections.requireValue,
                records: records.requireValue,
              ),
      ),
    );
  }

  void _refresh(WidgetRef ref, String ownerId) {
    ref.invalidate(roomsProvider(ownerId));
    ref.invalidate(roomMeterStatesProvider(ownerId));
    ref.invalidate(electricityMetersProvider(ownerId));
    ref.invalidate(meterReadingsProvider(ownerId));
    ref.invalidate(meterReadingCorrectionsProvider(ownerId));
    ref.invalidate(electricityBillingRecordsProvider(ownerId));
  }
}

class _HistoryContent extends ConsumerWidget {
  const _HistoryContent({
    required this.ownerId,
    required this.roomId,
    required this.rooms,
    required this.states,
    required this.meters,
    required this.readings,
    required this.corrections,
    required this.records,
  });

  final String ownerId;
  final String roomId;
  final List<Room> rooms;
  final List<RoomMeterState> states;
  final List<ElectricityMeter> meters;
  final List<MeterReading> readings;
  final List<MeterReadingCorrection> corrections;
  final List<ElectricityBillingRecord> records;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = rooms.where((item) => item.roomId == roomId).firstOrNull;
    if (room == null) {
      return const AdaptivePageBody(
        child: PropertyStatePanel(
          icon: Icons.meeting_room_outlined,
          title: 'Room not found',
          message: 'This room may have been removed or is unavailable.',
        ),
      );
    }
    final state = states.where((item) => item.roomId == roomId).firstOrNull;
    final meterById = {for (final meter in meters) meter.meterId: meter};
    final activeMeter = state == null ? null : meterById[state.currentMeterId];
    final roomReadings =
        readings.where((reading) => reading.roomId == roomId).toList()
          ..sort((a, b) {
            final date = b.readingDate.compareTo(a.readingDate);
            if (date != 0) return date;
            return b.sequence.compareTo(a.sequence);
          });
    final correctionsByReading = <String, List<MeterReadingCorrection>>{};
    for (final correction in corrections.where(
      (item) => item.roomId == roomId,
    )) {
      correctionsByReading
          .putIfAbsent(correction.readingId, () => [])
          .add(correction);
    }
    final recordsById = {
      for (final record in records) record.billingRecordId: record,
    };
    final insertionGaps = _historicalInsertionGaps(roomReadings, activeMeter);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(meterReadingsProvider(ownerId));
        ref.invalidate(meterReadingCorrectionsProvider(ownerId));
        ref.invalidate(electricityMetersProvider(ownerId));
        ref.invalidate(electricityBillingRecordsProvider(ownerId));
        await ref.read(meterReadingsProvider(ownerId).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          AdaptivePageBody(
            maxWidth: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  room.roomName,
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Saved readings stay visible. Only the latest active, unbilled reading can be corrected.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                if (insertionGaps.isNotEmpty) ...[
                  OutlinedButton.icon(
                    key: const Key('add-missing-historical-reading'),
                    onPressed: () async {
                      final inserted = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => _HistoricalReadingDialog(
                          ownerId: ownerId,
                          room: room,
                          meterId: activeMeter!.meterId,
                          gaps: insertionGaps,
                        ),
                      );
                      if (inserted == true) {
                        ref.invalidate(meterReadingsProvider(ownerId));
                        if (context.mounted) {
                          showPropertyMessage(
                            context,
                            'Missing reading added. The surrounding consumption was recalculated and the audit record was saved.',
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.add_chart_rounded),
                    label: const Text('Add missing historical reading'),
                  ),
                  const SizedBox(height: 16),
                ],
                if (roomReadings.isEmpty)
                  const PropertyStatePanel(
                    icon: Icons.speed_outlined,
                    title: 'No readings yet',
                    message: 'Set up this room meter to create its baseline.',
                  )
                else
                  ...roomReadings.map((reading) {
                    final eligibility = meterReadingCorrectionEligibility(
                      reading: reading,
                      activeMeter: activeMeter,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ReadingCard(
                        room: room,
                        reading: reading,
                        eligibility: eligibility,
                        corrections:
                            correctionsByReading[reading.readingId] ?? const [],
                        recordsById: recordsById,
                        onCorrect:
                            eligibility ==
                                MeterReadingCorrectionEligibility.eligible
                            ? () async {
                                final changed = await context.push<bool>(
                                  '/billing/electricity/rooms/$roomId/readings/${reading.readingId}/correct',
                                );
                                if (changed == true && context.mounted) {
                                  showPropertyMessage(
                                    context,
                                    '${room.roomName} reading corrected. The previous values remain in the audit history.',
                                  );
                                }
                              }
                            : null,
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingGap {
  const _ReadingGap({required this.predecessor, required this.successor});

  final MeterReading predecessor;
  final MeterReading successor;
}

List<_ReadingGap> _historicalInsertionGaps(
  List<MeterReading> roomReadings,
  ElectricityMeter? activeMeter,
) {
  if (activeMeter == null) return const [];
  final active =
      roomReadings
          .where(
            (reading) =>
                reading.meterId == activeMeter.meterId &&
                reading.lockTrackingComplete &&
                reading.billingRecordIds.isEmpty,
          )
          .toList()
        ..sort((a, b) => a.readingDate.compareTo(b.readingDate));
  final gaps = <_ReadingGap>[];
  for (var index = 1; index < active.length; index++) {
    final predecessor = active[index - 1];
    final successor = active[index];
    if (successor.previousReadingId == predecessor.readingId &&
        predecessor.readingDate.daysUntil(successor.readingDate) > 1) {
      gaps.add(_ReadingGap(predecessor: predecessor, successor: successor));
    }
  }
  return gaps;
}

class _HistoricalReadingDialog extends ConsumerStatefulWidget {
  const _HistoricalReadingDialog({
    required this.ownerId,
    required this.room,
    required this.meterId,
    required this.gaps,
  });

  final String ownerId;
  final Room room;
  final String meterId;
  final List<_ReadingGap> gaps;

  @override
  ConsumerState<_HistoricalReadingDialog> createState() =>
      _HistoricalReadingDialogState();
}

class _HistoricalReadingDialogState
    extends ConsumerState<_HistoricalReadingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _readingController = TextEditingController();
  final _reasonController = TextEditingController();
  late _ReadingGap _gap = widget.gaps.first;
  BusinessDate? _date;
  bool _saving = false;

  @override
  void dispose() {
    _readingController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate:
          (_date ?? _gap.predecessor.readingDate.addDays(1)).asUtcDateTime,
      firstDate: _gap.predecessor.readingDate.addDays(1).asUtcDateTime,
      lastDate: _gap.successor.readingDate.addDays(-1).asUtcDateTime,
      helpText: 'Missing reading date',
    );
    if (selected != null) {
      setState(() => _date = BusinessDate.fromDateTime(selected));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_date == null) {
      showPropertyMessage(context, 'Choose the missing reading date.');
      return;
    }
    final readingWh = _parseReadingWh(_readingController.text);
    if (readingWh == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(electricityRepositoryProvider)
          .insertHistoricalReading(
            ownerId: widget.ownerId,
            roomId: widget.room.roomId,
            meterId: widget.meterId,
            predecessorReadingId: _gap.predecessor.readingId,
            expectedPredecessorDate: _gap.predecessor.readingDate,
            expectedPredecessorWh: _gap.predecessor.readingWh,
            successorReadingId: _gap.successor.readingId,
            expectedSuccessorDate: _gap.successor.readingDate,
            expectedSuccessorWh: _gap.successor.readingWh,
            readingDate: _date!,
            readingWh: readingWh,
            reason: _reasonController.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ElectricityRepositoryException catch (error) {
      if (mounted) showPropertyMessage(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Add missing reading'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Warning: this inserts a boundary inside existing meter history and recalculates the following reading\'s consumption. It is allowed only when neither surrounding reading has been billed. The change is permanently audited.',
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<_ReadingGap>(
                  initialValue: _gap,
                  decoration: const InputDecoration(
                    labelText: 'Insert between',
                  ),
                  items: widget.gaps
                      .map(
                        (gap) => DropdownMenuItem(
                          value: gap,
                          child: Text(
                            '${formatBusinessDate(gap.predecessor.readingDate)} – ${formatBusinessDate(gap.successor.readingDate)}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (gap) {
                          if (gap != null) {
                            setState(() {
                              _gap = gap;
                              _date = null;
                              _readingController.clear();
                            });
                          }
                        },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(
                    _date == null
                        ? 'Choose reading date'
                        : formatBusinessDate(_date!),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _readingController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Meter reading (kWh)',
                    helperText:
                        'Must be between ${formatElectricityReading(_gap.predecessor.readingWh)} and ${formatElectricityReading(_gap.successor.readingWh)}.',
                  ),
                  validator: (value) {
                    final parsed = _parseReadingWh(value ?? '');
                    if (parsed == null) return 'Enter a valid meter reading.';
                    if (parsed < _gap.predecessor.readingWh ||
                        parsed > _gap.successor.readingWh) {
                      return 'Keep the value between the surrounding readings.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reasonController,
                  enabled: !_saving,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    helperText: 'Required for the permanent audit record.',
                  ),
                  validator: (value) {
                    final length = value?.trim().length ?? 0;
                    return length < 3 ? 'Enter at least 3 characters.' : null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add and recalculate'),
        ),
      ],
    );
  }
}

int? _parseReadingWh(String value) {
  try {
    return ElectricityValues.parseKilowattHoursToWattHours(value);
  } on ElectricityValidationException {
    return null;
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({
    required this.room,
    required this.reading,
    required this.eligibility,
    required this.corrections,
    required this.recordsById,
    required this.onCorrect,
  });

  final Room room;
  final MeterReading reading;
  final MeterReadingCorrectionEligibility eligibility;
  final List<MeterReadingCorrection> corrections;
  final Map<String, ElectricityBillingRecord> recordsById;
  final VoidCallback? onCorrect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final eligible = eligibility == MeterReadingCorrectionEligibility.eligible;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  formatBusinessDate(reading.readingDate),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Chip(
                  avatar: Icon(
                    eligible ? Icons.edit_outlined : Icons.lock_outline_rounded,
                    size: 18,
                  ),
                  label: Text(eligible ? 'Eligible' : 'Read-only'),
                  backgroundColor: eligible
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _FactRow(
              label: 'Meter value',
              value: formatElectricityReading(reading.readingWh),
            ),
            const SizedBox(height: 6),
            _FactRow(label: 'Purpose', value: _purposeLabel(reading.kind)),
            const SizedBox(height: 6),
            _FactRow(
              label: 'Derived consumption',
              value: formatElectricityReading(reading.consumptionWh),
            ),
            const SizedBox(height: 10),
            Text(
              _eligibilityMessage(eligibility, reading),
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
            ),
            if (onCorrect != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                key: Key('correct-reading-${reading.readingId}'),
                onPressed: onCorrect,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Correct reading'),
              ),
            ],
            if (reading.billingRecordIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...reading.billingRecordIds.map((recordId) {
                final record = recordsById[recordId];
                if (record == null) return const SizedBox.shrink();
                return Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => context.push(
                      '/billing/electricity/${record.billingRecordId}',
                    ),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(
                      'Open ${formatElectricityPeriod(record.startDate, record.endDateExclusive)} bill',
                    ),
                  ),
                );
              }),
            ],
            if (corrections.isNotEmpty) ...[
              const Divider(height: 28),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history_rounded),
                title: Text(
                  '${corrections.length} recorded ${corrections.length == 1 ? 'correction' : 'corrections'}',
                ),
                children: corrections
                    .map(
                      (correction) => _CorrectionEntry(correction: correction),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CorrectionEntry extends StatelessWidget {
  const _CorrectionEntry({required this.correction});

  final MeterReadingCorrection correction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatBusinessDate(correction.before.readingDate)} at ${formatElectricityReading(correction.before.readingWh)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(
            'Changed to ${formatBusinessDate(correction.after.readingDate)} at ${formatElectricityReading(correction.after.readingWh)}',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text('Reason: ${correction.reason}'),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: '$label: ',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
    );
  }
}

String _purposeLabel(MeterReadingKind kind) => switch (kind) {
  MeterReadingKind.opening => 'Opening baseline',
  MeterReadingKind.regular => 'Period boundary',
  MeterReadingKind.intermediate => 'Intermediate allocation point',
  MeterReadingKind.closing => 'Sequence closing reading',
};

String _eligibilityMessage(
  MeterReadingCorrectionEligibility eligibility,
  MeterReading reading,
) => switch (eligibility) {
  MeterReadingCorrectionEligibility.eligible =>
    'Latest active reading and not used by a saved electricity bill.',
  MeterReadingCorrectionEligibility.migrationRequired =>
    'This legacy reading is locked until billing references are migrated.',
  MeterReadingCorrectionEligibility.billed =>
    'Used by ${reading.billingRecordIds.length} saved electricity ${reading.billingRecordIds.length == 1 ? 'bill' : 'bills'}. Use the billing correction process instead.',
  MeterReadingCorrectionEligibility.newerReadingExists =>
    'A newer reading exists. Older readings are preserved as history.',
  MeterReadingCorrectionEligibility.inactiveSequence =>
    'This reading belongs to an inactive meter sequence and is preserved.',
  MeterReadingCorrectionEligibility.unsupportedReading => 'Sequence transition readings are preserved. Start a clean sequence when needed.',
};
