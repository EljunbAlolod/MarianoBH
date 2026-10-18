import 'package:flutter/material.dart';

import '../../../shared/widgets/app_components.dart';

import 'package:flutter/services.dart';
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
import '../domain/electricity_repository.dart';
import '../domain/electricity_values.dart';
import 'electricity_formatters.dart';

class ElectricityBatchEditorScreen extends ConsumerStatefulWidget {
  const ElectricityBatchEditorScreen({this.batchId, super.key});

  final String? batchId;

  @override
  ConsumerState<ElectricityBatchEditorScreen> createState() =>
      _ElectricityBatchEditorScreenState();
}

class _ElectricityBatchEditorScreenState
    extends ConsumerState<ElectricityBatchEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _rateController = TextEditingController();
  final Map<String, TextEditingController> _readingControllers = {};
  final Map<String, TextEditingController> _reasonControllers = {};
  final Set<String> _excludedRooms = {};
  BusinessDate _date = BusinessDate.todayInManila();
  TimeOfDay _time = TimeOfDay.now();
  bool _reviewing = false;
  bool _busy = false;
  bool _initialized = false;

  @override
  void dispose() {
    _rateController.dispose();
    for (final controller in _readingControllers.values) {
      controller.dispose();
    }
    for (final controller in _reasonControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _initialize(
    ElectricityReadingBatch? batch,
    List<ElectricityBatchRoomSource> sources,
  ) {
    if (_initialized) return;
    _initialized = true;
    if (batch != null) {
      _date = batch.effectiveDate;
      _time = TimeOfDay.fromDateTime(batch.effectiveAt.toLocal());
      _rateController.text = ElectricityValues.formatMicropesosAsPesosPerKwh(
        batch.rateMicropesosPerKwh,
      );
      for (final entry in batch.entries) {
        _readingControllers[entry.roomId] = TextEditingController(
          text: entry.currentReadingWh == null
              ? ''
              : ElectricityValues.formatWattHoursAsKilowattHours(
                  entry.currentReadingWh!,
                ),
        );
        _reasonControllers[entry.roomId] = TextEditingController(
          text: entry.exclusionReason ?? '',
        );
        if (entry.status == ElectricityBatchEntryStatus.excluded) {
          _excludedRooms.add(entry.roomId);
        }
      }
    } else {
      for (final source in sources) {
        _readingControllers[source.roomId] = TextEditingController();
        _reasonControllers[source.roomId] = TextEditingController();
      }
    }
  }

  DateTime get _effectiveAt =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  int? get _rate {
    try {
      return ElectricityValues.parsePesosPerKwhToMicropesos(
        _rateController.text,
      );
    } catch (_) {
      return null;
    }
  }

  List<ElectricityBatchEntryDraft> _drafts(
    List<ElectricityBatchRoomSource> sources,
  ) {
    return sources.map((source) {
      final excluded = _excludedRooms.contains(source.roomId);
      int? reading;
      if (!excluded) {
        try {
          reading = ElectricityValues.parseKilowattHoursToWattHours(
            _readingControllers[source.roomId]!.text,
          );
        } catch (_) {
          reading = null;
        }
      }
      return ElectricityBatchEntryDraft(
        roomId: source.roomId,
        currentReadingWh: reading,
        actualReadAt: _effectiveAt,
        exclusionReason: excluded
            ? _reasonControllers[source.roomId]!.text.trim()
            : null,
      );
    }).toList();
  }

  bool _validate(List<ElectricityBatchRoomSource> sources) {
    final valid = _formKey.currentState?.validate() ?? false;
    if (_effectiveAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      showPropertyMessage(
        context,
        'The effective reading time cannot be in the future.',
        isError: true,
      );
      return false;
    }
    for (final source in sources) {
      if (!_excludedRooms.contains(source.roomId) &&
          !_date.isAfter(source.previousReadingDate)) {
        showPropertyMessage(
          context,
          '${source.roomName} already has a reading on or after this date.',
          isError: true,
        );
        return false;
      }
    }
    return valid;
  }

  Future<void> _save({required bool finalize}) async {
    final workspace = ref.read(appSessionProvider).state.workspace;
    if (workspace == null) return;
    final ownerId = workspace.ownerUid;
    final data = _pageData(ownerId);
    if (data == null || !_validate(data.sources)) return;
    final rate = _rate!;
    setState(() => _busy = true);
    try {
      final repository = ref.read(electricityRepositoryProvider);
      var batchId = data.batch?.batchId;
      var version = data.batch?.version;
      if (batchId == null) {
        batchId = await repository.createReadingBatchDraft(
          ownerId: ownerId,
          effectiveDate: _date,
          effectiveAt: _effectiveAt,
          rateMicropesosPerKwh: rate,
          rooms: data.sources,
        );
        version = 1;
      }
      await repository.updateReadingBatchDraft(
        ownerId: ownerId,
        batchId: batchId,
        expectedVersion: version!,
        effectiveDate: _date,
        effectiveAt: _effectiveAt,
        rateMicropesosPerKwh: rate,
        entries: _drafts(data.sources),
      );
      if (finalize) {
        await repository.finalizeReadingBatch(
          ownerId: ownerId,
          batchId: batchId,
        );
      }
      if (!mounted) return;
      ref.invalidate(electricityReadingBatchesProvider(ownerId));
      ref.invalidate(electricityMetersProvider(ownerId));
      ref.invalidate(meterReadingsProvider(ownerId));
      context.go('/billing/electricity/batches/$batchId');
      showPropertyMessage(
        context,
        finalize ? 'Reading batch finalized.' : 'Reading batch saved as draft.',
      );
    } on ElectricityRepositoryException catch (error) {
      if (!mounted) return;
      showPropertyMessage(context, error.message, isError: true);
    } catch (error) {
      if (!mounted) return;
      showPropertyMessage(context, propertyErrorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  _BatchPageData? _pageData(String ownerId) {
    final rooms = ref.read(roomsProvider(ownerId)).asData?.value;
    final states = ref.read(roomMeterStatesProvider(ownerId)).asData?.value;
    final meters = ref.read(electricityMetersProvider(ownerId)).asData?.value;
    final batches = ref
        .read(electricityReadingBatchesProvider(ownerId))
        .asData
        ?.value;
    if (rooms == null || states == null || meters == null || batches == null) {
      return null;
    }
    final batch = widget.batchId == null
        ? null
        : batches.where((item) => item.batchId == widget.batchId).firstOrNull;
    final sources = batch != null
        ? batch.entries
              .map(
                (entry) => ElectricityBatchRoomSource(
                  roomId: entry.roomId,
                  roomName: entry.roomName,
                  meterId: entry.meterId,
                  sequence: entry.sequence,
                  previousReadingId: entry.previousReadingId,
                  previousReadingDate: entry.previousReadingDate,
                  previousReadingWh: entry.previousReadingWh,
                ),
              )
              .toList()
        : _sourcesFor(rooms, states, meters);
    final activeCount = rooms.where((room) => room.isActive).length;
    return _BatchPageData(
      batch: batch,
      sources: sources,
      missingMeterCount: batch == null ? activeCount - sources.length : 0,
    );
  }

  List<ElectricityBatchRoomSource> _sourcesFor(
    List<Room> rooms,
    List<RoomMeterState> states,
    List<ElectricityMeter> meters,
  ) {
    final stateByRoom = {for (final state in states) state.roomId: state};
    final meterById = {for (final meter in meters) meter.meterId: meter};
    final active = rooms.where((room) => room.isActive).toList()
      ..sort((a, b) => a.roomName.compareTo(b.roomName));
    return active
        .map((room) {
          final state = stateByRoom[room.roomId];
          final meter = state == null ? null : meterById[state.currentMeterId];
          if (meter == null || meter.status != ElectricityMeterStatus.active) {
            return null;
          }
          return ElectricityBatchRoomSource(
            roomId: room.roomId,
            roomName: room.roomName,
            meterId: meter.meterId,
            sequence: meter.sequence,
            previousReadingId: meter.lastReadingId,
            previousReadingDate: meter.lastReadingDate,
            previousReadingWh: meter.lastReadingWh,
          );
        })
        .whereType<ElectricityBatchRoomSource>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
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
    final values = [
      ref.watch(roomsProvider(ownerId)),
      ref.watch(roomMeterStatesProvider(ownerId)),
      ref.watch(electricityMetersProvider(ownerId)),
      ref.watch(electricityReadingBatchesProvider(ownerId)),
    ];
    final error = values.where((value) => value.hasError).firstOrNull;
    final loading = values.any((value) => value.isLoading);
    final data = loading || error != null ? null : _pageData(ownerId);
    if (data != null) _initialize(data.batch, data.sources);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.batchId == null ? 'New reading batch' : 'Edit reading batch',
        ),
      ),
      body: SafeArea(
        child: error != null
            ? AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Batch could not be loaded',
                  message: propertyErrorMessage(error.error!),
                ),
              )
            : loading || data == null
            ? const Center(child: CircularProgressIndicator())
            : data.batch != null && !data.batch!.canEdit
            ? AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.lock_outline,
                  title: 'This batch is read-only',
                  message:
                      'Finalized, billed, and voided batches cannot be edited.',
                  actionLabel: 'View batch',
                  onAction: () => context.go(
                    '/billing/electricity/batches/${data.batch!.batchId}',
                  ),
                ),
              )
            : data.missingMeterCount > 0
            ? AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.speed_outlined,
                  title: 'Set up every active room first',
                  message:
                      '${data.missingMeterCount} active ${data.missingMeterCount == 1 ? 'room needs' : 'rooms need'} a baseline meter before a complete batch can be created.',
                  actionLabel: 'Back to room meters',
                  onAction: () => context.go('/billing/electricity'),
                ),
              )
            : data.sources.isEmpty
            ? const AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.meeting_room_outlined,
                  title: 'No active rooms',
                  message: 'Activate and configure at least one room before creating a reading batch.',
                ),
              )
            : _buildForm(data),
      ),
    );
  }

  Widget _buildForm(_BatchPageData data) {
    final colors = Theme.of(context).colorScheme;
    final rate = _rate;
    final drafts = _drafts(data.sources);
    var totalWh = 0;
    var totalCentavos = 0;
    if (rate != null) {
      for (var index = 0; index < data.sources.length; index++) {
        final source = data.sources[index];
        final draft = drafts[index];
        if (draft.isExcluded ||
            draft.currentReadingWh == null ||
            draft.currentReadingWh! < source.previousReadingWh) {
          continue;
        }
        final consumption = draft.currentReadingWh! - source.previousReadingWh;
        totalWh += consumption;
        totalCentavos += ElectricityValues.chargeCentavos(
          consumptionWh: consumption,
          rateMicropesosPerKwh: rate,
        );
      }
    }
    return Form(
      key: _formKey,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          AdaptivePageBody(
            maxWidth: 900,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _reviewing ? 'Review the batch' : 'Record all room meters',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  _reviewing
                      ? 'Step 2 of 2 · Confirm every value before finalizing. Finalization creates permanent room readings.'
                      : 'Step 1 of 2 · Enter a reading for every active room, or explicitly exclude it with a reason.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                WorkflowProgress(
                  steps: const ['Readings', 'Review'],
                  current: _reviewing ? 1 : 0,
                ),
                if (_reviewing)
                  _ReviewSummary(
                    date: _date,
                    time: _time,
                    rate: rate!,
                    roomCount: data.sources.length,
                    excludedCount: _excludedRooms.length,
                    totalWh: totalWh,
                    totalCentavos: totalCentavos,
                  )
                else ...[
                  _BatchDateTimeFields(
                    date: _date,
                    time: _time,
                    onDateChanged: (value) => setState(() => _date = value),
                    onTimeChanged: (value) => setState(() => _time = value),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const Key('batch-rate-field'),
                    controller: _rateController,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Electricity rate',
                      prefixIcon: Icon(Icons.bolt_outlined),
                      prefixText: '₱ ',
                      suffixText: 'per kWh',
                      helperText: 'Use the rate effective for this batch.',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    validator: (value) {
                      try {
                        final parsed =
                            ElectricityValues.parsePesosPerKwhToMicropesos(
                              value ?? '',
                            );
                        if (parsed <= 0) {
                          return 'Enter a rate greater than zero.';
                        }
                        return null;
                      } on ElectricityValidationException catch (error) {
                        return error.message;
                      }
                    },
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Rooms (${data.sources.length})',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                for (var index = 0; index < data.sources.length; index++) ...[
                  _RoomReadingCard(
                    source: data.sources[index],
                    draft: drafts[index],
                    rate: rate,
                    controller:
                        _readingControllers[data.sources[index].roomId]!,
                    reasonController:
                        _reasonControllers[data.sources[index].roomId]!,
                    excluded: _excludedRooms.contains(
                      data.sources[index].roomId,
                    ),
                    recorded:
                        data.batch?.entries
                            .where(
                              (entry) =>
                                  entry.roomId == data.sources[index].roomId,
                            )
                            .firstOrNull
                            ?.status ==
                        ElectricityBatchEntryStatus.recorded,
                    readOnly:
                        _reviewing ||
                        _busy ||
                        data.batch?.entries
                                .where(
                                  (entry) =>
                                      entry.roomId ==
                                      data.sources[index].roomId,
                                )
                                .firstOrNull
                                ?.status ==
                            ElectricityBatchEntryStatus.recorded,
                    onChanged: () => setState(() {}),
                    onExcludeChanged: (value) => setState(() {
                      if (value) {
                        _excludedRooms.add(data.sources[index].roomId);
                      } else {
                        _excludedRooms.remove(data.sources[index].roomId);
                      }
                    }),
                  ),
                  if (index != data.sources.length - 1)
                    const SizedBox(height: 12),
                ],
                const SizedBox(height: 20),
                if (_reviewing) ...[
                  Material(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: colors.onErrorContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Finalizing records the included readings and updates each room meter. The batch cannot be edited afterward; corrections must use room reading history.',
                              style: TextStyle(
                                color: colors.onErrorContainer,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_busy) const LinearProgressIndicator(),
                const SizedBox(height: 12),
                if (_reviewing) ...[
                  FilledButton.icon(
                    key: const Key('finalize-reading-batch'),
                    onPressed: _busy ? null : () => _save(finalize: true),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Finalize reading batch'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _reviewing = false),
                    child: const Text('Back to edit'),
                  ),
                ] else ...[
                  FilledButton.icon(
                    key: const Key('review-reading-batch'),
                    onPressed: _busy
                        ? null
                        : () {
                            if (_validate(data.sources)) {
                              setState(() => _reviewing = true);
                            }
                          },
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Review batch'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('save-reading-batch-draft'),
                    onPressed: _busy ? null : () => _save(finalize: false),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save draft'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchPageData {
  const _BatchPageData({
    required this.batch,
    required this.sources,
    required this.missingMeterCount,
  });
  final ElectricityReadingBatch? batch;
  final List<ElectricityBatchRoomSource> sources;
  final int missingMeterCount;
}

class _BatchDateTimeFields extends StatelessWidget {
  const _BatchDateTimeFields({
    required this.date,
    required this.time,
    required this.onDateChanged,
    required this.onTimeChanged,
  });
  final BusinessDate date;
  final TimeOfDay time;
  final ValueChanged<BusinessDate> onDateChanged;
  final ValueChanged<TimeOfDay> onTimeChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fields = [
          InkWell(
            key: const Key('batch-date-field'),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime(date.year, date.month, date.day),
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                onDateChanged(BusinessDate.fromDateTime(picked));
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Effective reading date',
                prefixIcon: Icon(Icons.calendar_today_outlined),
              ),
              child: Text(formatBusinessDate(date)),
            ),
          ),
          InkWell(
            key: const Key('batch-time-field'),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: time,
              );
              if (picked != null) onTimeChanged(picked);
            },
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Effective time',
                prefixIcon: Icon(Icons.schedule_outlined),
              ),
              child: Text(time.format(context)),
            ),
          ),
        ];
        if (constraints.maxWidth < 560) {
          return Column(
            children: [fields[0], const SizedBox(height: 14), fields[1]],
          );
        }
        return Row(
          children: [
            Expanded(child: fields[0]),
            const SizedBox(width: 12),
            Expanded(child: fields[1]),
          ],
        );
      },
    );
  }
}

class _RoomReadingCard extends StatelessWidget {
  const _RoomReadingCard({
    required this.source,
    required this.draft,
    required this.rate,
    required this.controller,
    required this.reasonController,
    required this.excluded,
    required this.recorded,
    required this.readOnly,
    required this.onChanged,
    required this.onExcludeChanged,
  });
  final ElectricityBatchRoomSource source;
  final ElectricityBatchEntryDraft draft;
  final int? rate;
  final TextEditingController controller;
  final TextEditingController reasonController;
  final bool excluded;
  final bool recorded;
  final bool readOnly;
  final VoidCallback onChanged;
  final ValueChanged<bool> onExcludeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final current = draft.currentReadingWh;
    final validReading = current != null && current >= source.previousReadingWh;
    final consumption = validReading
        ? current - source.previousReadingWh
        : null;
    final charge = consumption == null || rate == null
        ? null
        : ElectricityValues.chargeCentavos(
            consumptionWh: consumption,
            rateMicropesosPerKwh: rate!,
          );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              source.roomName,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (recorded) ...[
              const SizedBox(height: 4),
              Text(
                'Already recorded · This room is locked in the resumed draft.',
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Previous: ${formatElectricityReading(source.previousReadingWh)} on ${formatBusinessDate(source.previousReadingDate)}',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            if (!excluded)
              TextFormField(
                key: Key('batch-reading-${source.roomId}'),
                controller: controller,
                readOnly: readOnly,
                decoration: InputDecoration(
                  labelText: 'Current meter reading',
                  suffixText: 'kWh',
                  helperText: consumption == null
                      ? 'Must be at least ${ElectricityValues.formatWattHoursAsKilowattHours(source.previousReadingWh)} kWh.'
                      : 'Consumption: ${formatElectricityReading(consumption)}${charge == null ? '' : ' · ${formatPeso(charge)}'}',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (_) => onChanged(),
                validator: (value) {
                  if (excluded) return null;
                  try {
                    final parsed =
                        ElectricityValues.parseKilowattHoursToWattHours(
                          value ?? '',
                        );
                    if (parsed < source.previousReadingWh) {
                      return 'Reading cannot be below the previous reading.';
                    }
                    return null;
                  } on ElectricityValidationException catch (error) {
                    return error.message;
                  }
                },
              )
            else
              TextFormField(
                key: Key('batch-exclusion-reason-${source.roomId}'),
                controller: reasonController,
                readOnly: readOnly,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Exclusion reason',
                  helperText:
                      'Explain why this active room is not part of this batch.',
                ),
                onChanged: (_) => onChanged(),
                validator: (value) {
                  final clean = value?.trim() ?? '';
                  if (!excluded) return null;
                  if (clean.length < 3) return 'Enter at least 3 characters.';
                  return null;
                },
              ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: excluded,
              onChanged: readOnly ? null : onExcludeChanged,
              title: const Text('Exclude this room'),
              subtitle: const Text(
                'An explicit reason is required and retained in the batch.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({
    required this.date,
    required this.time,
    required this.rate,
    required this.roomCount,
    required this.excludedCount,
    required this.totalWh,
    required this.totalCentavos,
  });
  final BusinessDate date;
  final TimeOfDay time;
  final int rate;
  final int roomCount;
  final int excludedCount;
  final int totalWh;
  final int totalCentavos;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${formatBusinessDate(date)}, ${time.format(context)}',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${formatElectricityRate(rate)} · ${roomCount - excludedCount} included · $excludedCount excluded',
            ),
            const Divider(height: 24),
            Text(
              '${formatElectricityReading(totalWh)} · ${formatPeso(totalCentavos)}',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
