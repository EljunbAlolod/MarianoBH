import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/application/property_providers.dart';
import '../../property_management/domain/boarder.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/domain/occupancy.dart';
import '../../property_management/domain/room.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/electricity_providers.dart';
import '../domain/electricity_calculator.dart';
import '../domain/electricity_models.dart';
import '../domain/electricity_values.dart';
import 'electricity_formatters.dart';

class ElectricityCalculationScreen extends ConsumerStatefulWidget {
  const ElectricityCalculationScreen({
    super.key,
    this.initialStartDate,
    this.initialEndDateExclusive,
    this.returnTo,
  });

  final BusinessDate? initialStartDate;
  final BusinessDate? initialEndDateExclusive;
  final String? returnTo;

  @override
  ConsumerState<ElectricityCalculationScreen> createState() =>
      _ElectricityCalculationScreenState();
}

class _ElectricityCalculationScreenState
    extends ConsumerState<ElectricityCalculationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _rateController = TextEditingController();
  late BusinessDate _startDate;
  late BusinessDate _endDateExclusive;
  final List<ElectricityAdjustment> _adjustments = [];
  ElectricityCalculationResult? _result;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final today = BusinessDate.todayInManila();
    _endDateExclusive = widget.initialEndDateExclusive ?? today;
    _startDate =
        widget.initialStartDate ?? BusinessDate(today.year, today.month, 1);
    if (!_startDate.isBefore(_endDateExclusive)) {
      _startDate = today.addDays(-1);
    }
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  void _invalidateResult() {
    if (_result != null || _error != null) {
      setState(() {
        _result = null;
        _error = null;
      });
    }
  }

  String? _validateRate(String? value) {
    try {
      final rate = ElectricityValues.parsePesosPerKwhToMicropesos(value ?? '');
      if (rate == 0) return 'Electricity rate must be greater than zero.';
      return null;
    } on ElectricityValidationException catch (error) {
      return error.message;
    }
  }

  void _calculate({
    required List<Room> rooms,
    required List<ElectricityMeter> meters,
    required List<MeterReading> readings,
    required List<Occupancy> occupancies,
    required List<Boarder> boarders,
  }) {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (!_startDate.isBefore(_endDateExclusive)) {
      setState(() => _error = 'Period end must be after the start date.');
      return;
    }
    try {
      final meterRoomIds = meters.map((item) => item.roomId).toSet();
      final relevantRooms = rooms
          .where((room) => room.isActive || meterRoomIds.contains(room.roomId))
          .toList();
      final result = const ElectricityCalculator().calculate(
        ElectricityCalculationInput(
          startDate: _startDate,
          endDateExclusive: _endDateExclusive,
          rateMicropesosPerKwh: ElectricityValues.parsePesosPerKwhToMicropesos(
            _rateController.text,
          ),
          rooms: relevantRooms,
          meters: meters,
          readings: readings,
          occupancies: occupancies,
          boarders: boarders,
          adjustments: _adjustments,
        ),
      );
      setState(() => _result = result);
    } catch (error) {
      setState(() {
        _result = null;
        _error = propertyErrorMessage(error);
      });
    }
  }

  Future<void> _addAdjustment(List<Room> rooms) async {
    if (rooms.isEmpty) {
      setState(() {
        _result = null;
        _error = 'Add a room before documenting an adjustment.';
      });
      return;
    }
    final adjustment = await showDialog<ElectricityAdjustment>(
      context: context,
      builder: (context) => _AdjustmentDialog(
        rooms: rooms,
        startDate: _startDate,
        endDateExclusive: _endDateExclusive,
      ),
    );
    if (adjustment != null) {
      setState(() {
        _adjustments.add(adjustment);
        _result = null;
        _error = null;
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
        title: const Text('Save this electricity record?'),
        content: const Text(
          'The readings, rate, adjustments, room totals, and boarder shares will be stored as a read-only historical snapshot.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep reviewing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save record'),
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
          .read(electricityRepositoryProvider)
          .recordBillingSnapshot(
            ownerId: ownerId,
            result: result,
            roomBillingSource: widget.returnTo != null,
          );
      if (mounted) {
        context.go(widget.returnTo ?? '/billing/electricity/$id');
      }
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
    final rooms = ref.watch(roomsProvider(ownerId));
    final meters = ref.watch(electricityMetersProvider(ownerId));
    final readings = ref.watch(meterReadingsProvider(ownerId));
    final occupancies = ref.watch(allOccupanciesProvider(ownerId));
    final boarders = ref.watch(boardersProvider(ownerId));
    final sources = [rooms, meters, readings, occupancies, boarders];
    final errorSource = sources.where((item) => item.hasError).firstOrNull;
    final loading = sources.any((item) => item.isLoading);

    return Scaffold(
      appBar: AppBar(title: const Text('Calculate electricity')),
      body: SafeArea(
        child: errorSource != null
            ? AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Calculation data could not be loaded',
                  message: propertyErrorMessage(errorSource.error!),
                  actionLabel: 'Try again',
                  onAction: () {
                    ref.invalidate(roomsProvider(ownerId));
                    ref.invalidate(electricityMetersProvider(ownerId));
                    ref.invalidate(meterReadingsProvider(ownerId));
                    ref.invalidate(allOccupanciesProvider(ownerId));
                    ref.invalidate(boardersProvider(ownerId));
                  },
                ),
              )
            : loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  AdaptivePageBody(
                    maxWidth: 900,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Period and rate',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Both dates require saved meter readings. The end date is the first day outside the billed period.',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 20),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final stacked =
                                  constraints.maxWidth < 600 ||
                                  MediaQuery.textScalerOf(context).scale(16) >
                                      20;
                              final start = _PeriodDateField(
                                label: 'Start date',
                                value: _startDate,
                                onChanged: (value) {
                                  setState(() => _startDate = value);
                                  _invalidateResult();
                                },
                              );
                              final end = _PeriodDateField(
                                label: 'End date (exclusive)',
                                value: _endDateExclusive,
                                onChanged: (value) {
                                  setState(() => _endDateExclusive = value);
                                  _invalidateResult();
                                },
                              );
                              if (stacked) {
                                return Column(
                                  children: [
                                    start,
                                    const SizedBox(height: 16),
                                    end,
                                  ],
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
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('electricity-rate-field'),
                            controller: _rateController,
                            enabled: !_saving,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Electricity rate',
                              prefixText: '₱ ',
                              suffixText: 'per kWh',
                              helperText: 'Use up to six decimal places.',
                              prefixIcon: Icon(Icons.bolt_outlined),
                            ),
                            validator: _validateRate,
                            onChanged: (_) => _invalidateResult(),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Documented adjustments',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _saving || rooms.requireValue.isEmpty
                                    ? null
                                    : () => _addAdjustment(rooms.requireValue),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Adjustments never overwrite meter readings and must include a room, date, type, and reason.',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_adjustments.isEmpty)
                            const _AdjustmentEmpty()
                          else
                            ..._adjustments.indexed.map((entry) {
                              final (index, adjustment) = entry;
                              final room = rooms.requireValue
                                  .where(
                                    (item) => item.roomId == adjustment.roomId,
                                  )
                                  .firstOrNull;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _AdjustmentTile(
                                  adjustment: adjustment,
                                  roomName: room?.roomName ?? 'Unknown room',
                                  onRemove: _saving
                                      ? null
                                      : () {
                                          setState(() {
                                            _adjustments.removeAt(index);
                                            _result = null;
                                          });
                                        },
                                ),
                              );
                            }),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            _CalculationError(message: _error!),
                          ],
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            key: const Key('review-electricity-button'),
                            onPressed: _saving
                                ? null
                                : () => _calculate(
                                    rooms: rooms.requireValue,
                                    meters: meters.requireValue,
                                    readings: readings.requireValue,
                                    occupancies: occupancies.requireValue,
                                    boarders: boarders.requireValue,
                                  ),
                            icon: const Icon(Icons.calculate_outlined),
                            label: const Text('Review calculation'),
                          ),
                          if (_result != null) ...[
                            const SizedBox(height: 32),
                            _CalculationPreview(result: _result!),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              key: const Key('save-electricity-record-button'),
                              onPressed: _saving ? null : () => _save(ownerId),
                              icon: _saving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.lock_outline_rounded),
                              label: Text(
                                _saving
                                    ? 'Saving record…'
                                    : 'Save read-only record',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CalculationPreview extends StatelessWidget {
  const _CalculationPreview({required this.result});

  final ElectricityCalculationResult result;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Calculation review',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _SummaryRow(
                  label: 'Period',
                  value: formatElectricityPeriod(
                    result.startDate,
                    result.endDateExclusive,
                  ),
                ),
                _SummaryRow(
                  label: 'Rate',
                  value: formatElectricityRate(result.rateMicropesosPerKwh),
                ),
                _SummaryRow(
                  label: 'Total consumption',
                  value: formatElectricityReading(result.totalConsumptionWh),
                ),
                _SummaryRow(
                  label: 'Base charges',
                  value: formatPeso(result.totalBaseChargeCentavos),
                ),
                _SummaryRow(
                  label: 'Adjustments',
                  value: formatSignedPeso(result.totalAdjustmentsCentavos),
                ),
                _SummaryRow(
                  label: 'Total electricity',
                  value: formatPeso(result.totalChargeCentavos),
                  emphasized: true,
                ),
              ],
            ),
          ),
        ),
        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...result.warnings.map(
            (warning) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CalculationWarning(message: warning),
            ),
          ),
        ],
        const SizedBox(height: 12),
        ...result.roomCharges.map(
          (room) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RoomChargeCard(room: room),
          ),
        ),
      ],
    );
  }
}

class _RoomChargeCard extends StatelessWidget {
  const _RoomChargeCard({required this.room});

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    room.roomName,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
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
            _SummaryRow(
              label: 'Consumption',
              value: formatElectricityReading(room.consumptionWh),
            ),
            _SummaryRow(
              label: 'Base charge',
              value: formatPeso(room.baseChargeCentavos),
            ),
            if (room.adjustmentCentavos != 0)
              _SummaryRow(
                label: 'Adjustment',
                value: formatSignedPeso(room.adjustmentCentavos),
              ),
            _SummaryRow(
              label: 'Room total',
              value: formatPeso(room.finalChargeCentavos),
              emphasized: true,
            ),
            const Divider(height: 28),
            Text(
              'Boarder shares',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (room.boarderShares.isEmpty && room.unallocatedCentavos == 0)
              const Text('No charge to allocate.')
            else ...[
              ...room.boarderShares.map(
                (share) => _SummaryRow(
                  label:
                      '${share.boarderName} · ${share.occupancyDays} ${share.occupancyDays == 1 ? 'day' : 'days'}${share.isEstimated ? ' · estimate' : ''}',
                  value: formatPeso(share.amountCentavos),
                ),
              ),
              if (room.unallocatedCentavos > 0)
                _SummaryRow(
                  label: 'Unallocated / landlady-paid',
                  value: formatPeso(room.unallocatedCentavos),
                ),
            ],
            const Divider(height: 28),
            Text(
              '${room.segments.length} reading ${room.segments.length == 1 ? 'interval' : 'intervals'} used',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
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
  }
}

class _AdjustmentDialog extends StatefulWidget {
  const _AdjustmentDialog({
    required this.rooms,
    required this.startDate,
    required this.endDateExclusive,
  });

  final List<Room> rooms;
  final BusinessDate startDate;
  final BusinessDate endDateExclusive;

  @override
  State<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<_AdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  late String _roomId;
  ElectricityAdjustmentType _type = ElectricityAdjustmentType.surcharge;
  late BusinessDate _date;

  @override
  void initState() {
    super.initState();
    _roomId = widget.rooms.first.roomId;
    _date = widget.startDate;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = parsePesoToCentavos(_amountController.text)!;
    Navigator.pop(
      context,
      ElectricityAdjustment(
        adjustmentId: 'adjustment-${DateTime.now().microsecondsSinceEpoch}',
        roomId: _roomId,
        type: _type,
        magnitudeCentavos: amount,
        reason: _reasonController.text.trim(),
        adjustmentDate: _date,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add electricity adjustment'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _roomId,
                  decoration: const InputDecoration(labelText: 'Room'),
                  items: widget.rooms
                      .map(
                        (room) => DropdownMenuItem(
                          value: room.roomId,
                          child: Text(room.roomName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _roomId = value!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<ElectricityAdjustmentType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(
                      value: ElectricityAdjustmentType.surcharge,
                      child: Text('Additional charge'),
                    ),
                    DropdownMenuItem(
                      value: ElectricityAdjustmentType.discount,
                      child: Text('Discount / credit'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _type = value!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₱ ',
                  ),
                  validator: (value) {
                    try {
                      final amount = parsePesoToCentavos(value ?? '');
                      if (amount == null || amount <= 0) {
                        return 'Enter an amount greater than zero.';
                      }
                      return null;
                    } on FormatException catch (error) {
                      return error.message;
                    }
                  },
                ),
                const SizedBox(height: 16),
                _PeriodDateField(
                  label: 'Adjustment date',
                  value: _date,
                  firstDate: widget.startDate,
                  lastDate: widget.endDateExclusive.addDays(-1),
                  onChanged: (value) => setState(() => _date = value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _reasonController,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'A reason is required.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add adjustment')),
      ],
    );
  }
}

class _PeriodDateField extends StatelessWidget {
  const _PeriodDateField({
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

class _AdjustmentEmpty extends StatelessWidget {
  const _AdjustmentEmpty();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No adjustments. Raw meter calculations remain unchanged.'),
      ),
    );
  }
}

class _AdjustmentTile extends StatelessWidget {
  const _AdjustmentTile({
    required this.adjustment,
    required this.roomName,
    required this.onRemove,
  });

  final ElectricityAdjustment adjustment;
  final String roomName;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          adjustment.type == ElectricityAdjustmentType.surcharge
              ? Icons.add_circle_outline_rounded
              : Icons.remove_circle_outline_rounded,
        ),
        title: Text(
          '$roomName · ${formatSignedPeso(adjustment.signedCentavos)}',
        ),
        subtitle: Text(
          '${formatBusinessDate(adjustment.adjustmentDate)} · ${adjustment.reason}',
        ),
        trailing: IconButton(
          tooltip: 'Remove adjustment',
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded),
        ),
      ),
    );
  }
}

class _CalculationWarning extends StatelessWidget {
  const _CalculationWarning({required this.message});

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

class _CalculationError extends StatelessWidget {
  const _CalculationError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
