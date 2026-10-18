import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../electricity/application/electricity_providers.dart';
import '../../electricity/domain/electricity_models.dart';
import '../../property_management/application/property_providers.dart';
import '../../property_management/domain/boarder.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/domain/occupancy.dart';
import '../../property_management/domain/room.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/water_providers.dart';
import '../domain/water_calculator.dart';
import '../domain/water_models.dart';
import '../domain/water_values.dart';
import 'water_formatters.dart';

class WaterCalculationScreen extends ConsumerStatefulWidget {
  const WaterCalculationScreen({
    super.key,
    this.initialStartDate,
    this.initialEndDateExclusive,
    this.returnTo,
  });

  final BusinessDate? initialStartDate;
  final BusinessDate? initialEndDateExclusive;
  final String? returnTo;

  @override
  ConsumerState<WaterCalculationScreen> createState() =>
      _WaterCalculationScreenState();
}

class _WaterCalculationScreenState
    extends ConsumerState<WaterCalculationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _billController = TextEditingController();
  late BusinessDate _startDate;
  late BusinessDate _endDateExclusive;
  WaterBillingMethod? _selectedMethod;
  SummerElectricityBasis? _selectedBasis;
  WaterCalculationResult? _result;
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
    if (widget.returnTo != null) {
      _selectedMethod = WaterBillingMethod.roomDays;
    }
  }

  @override
  void dispose() {
    _billController.dispose();
    super.dispose();
  }

  void _invalidate() {
    setState(() {
      _result = null;
      _error = null;
    });
  }

  String? _validateBill(String? value) {
    try {
      WaterValues.parsePesosToCentavos(value ?? '');
      return null;
    } on WaterValidationException catch (error) {
      return error.message;
    }
  }

  ElectricityBillingRecord? _matchingElectricityRecord(
    List<ElectricityBillingRecord> records,
  ) {
    return records
        .where(
          (record) =>
              record.startDate == _startDate &&
              record.endDateExclusive == _endDateExclusive,
        )
        .firstOrNull;
  }

  void _calculate({
    required WaterSettings settings,
    required List<ElectricityBillingRecord> electricityRecords,
    required List<Room> rooms,
    required List<Boarder> boarders,
    required List<Occupancy> occupancies,
  }) {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final recommended = settings.methodFor(_startDate);
    final method =
        _selectedMethod ??
        (recommended == WaterBillingMethod.selectedBoarders
            ? WaterBillingMethod.personDays
            : recommended);
    final basis = _selectedBasis ?? settings.summerBasis;
    final source = _matchingElectricityRecord(electricityRecords);
    try {
      final result = const WaterCalculator().calculate(
        WaterCalculationInput(
          startDate: _startDate,
          endDateExclusive: _endDateExclusive,
          waterBillCentavos: WaterValues.parsePesosToCentavos(
            _billController.text,
          ),
          method: method,
          summerBasis: basis,
          rooms: rooms,
          boarders: boarders,
          occupancies: occupancies,
          electricityRecord: method == WaterBillingMethod.electricityPercentage
              ? source
              : null,
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

  Future<void> _save(String ownerId) async {
    final result = _result;
    if (result == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.lock_outline_rounded),
        title: const Text('Save this water record?'),
        content: Text(
          widget.returnTo == null
              ? 'The dates, selected method, room allocations, and boarder shares will be preserved as a read-only snapshot.'
              : 'The dates and room-day allocation will be preserved as a read-only source for the room bills.',
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
          .read(waterRepositoryProvider)
          .recordBillingSnapshot(ownerId: ownerId, result: result);
      if (mounted) {
        context.go(widget.returnTo ?? '/billing/water/$id');
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
    final settings = ref.watch(waterSettingsProvider(ownerId));
    final electricity = ref.watch(electricityBillingRecordsProvider(ownerId));
    final rooms = ref.watch(roomsProvider(ownerId));
    final boarders = ref.watch(boardersProvider(ownerId));
    final occupancies = ref.watch(allOccupanciesProvider(ownerId));
    final sources = [settings, electricity, rooms, boarders, occupancies];
    final errorSource = sources.where((source) => source.hasError).firstOrNull;
    final loading = sources.any((source) => source.isLoading);

    return Scaffold(
      appBar: AppBar(title: const Text('Calculate water')),
      body: SafeArea(
        child: errorSource != null
            ? AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Calculation data could not be loaded',
                  message: propertyErrorMessage(errorSource.error!),
                  actionLabel: 'Try again',
                  onAction: () {
                    ref.invalidate(waterSettingsProvider(ownerId));
                    ref.invalidate(electricityBillingRecordsProvider(ownerId));
                    ref.invalidate(roomsProvider(ownerId));
                    ref.invalidate(boardersProvider(ownerId));
                    ref.invalidate(allOccupanciesProvider(ownerId));
                  },
                ),
              )
            : loading
            ? const Center(child: CircularProgressIndicator())
            : _buildForm(
                ownerId: ownerId,
                settings: settings.requireValue,
                electricityRecords: electricity.requireValue,
                rooms: rooms.requireValue,
                boarders: boarders.requireValue,
                occupancies: occupancies.requireValue,
              ),
      ),
    );
  }

  Widget _buildForm({
    required String ownerId,
    required WaterSettings settings,
    required List<ElectricityBillingRecord> electricityRecords,
    required List<Room> rooms,
    required List<Boarder> boarders,
    required List<Occupancy> occupancies,
  }) {
    final recommended = settings.methodFor(_startDate);
    final method =
        _selectedMethod ??
        (recommended == WaterBillingMethod.selectedBoarders
            ? WaterBillingMethod.personDays
            : recommended);
    final basis = _selectedBasis ?? settings.summerBasis;
    final source = _matchingElectricityRecord(electricityRecords);
    final usesElectricity = method == WaterBillingMethod.electricityPercentage;
    return ListView(
      children: [
        AdaptivePageBody(
          maxWidth: 900,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Bill and period',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'The end date is exclusive. Occupancy on that date belongs to the next billing period.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked =
                        constraints.maxWidth < 560 ||
                        MediaQuery.textScalerOf(context).scale(16) > 20;
                    final start = _PeriodDateField(
                      label: 'Start date',
                      value: _startDate,
                      lastDate: _endDateExclusive.addDays(-1),
                      onChanged: (value) {
                        setState(() {
                          _startDate = value;
                          _selectedMethod = null;
                          _result = null;
                          _error = null;
                        });
                      },
                    );
                    final end = _PeriodDateField(
                      label: 'End date (exclusive)',
                      value: _endDateExclusive,
                      firstDate: _startDate.addDays(1),
                      onChanged: (value) {
                        setState(() {
                          _endDateExclusive = value;
                          _result = null;
                          _error = null;
                        });
                      },
                    );
                    return stacked
                        ? Column(
                            children: [start, const SizedBox(height: 12), end],
                          )
                        : Row(
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
                  key: const Key('water-bill-field'),
                  controller: _billController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Total water bill',
                    prefixText: '₱ ',
                    helperText: 'Enter the amount shown on the water bill.',
                    prefixIcon: Icon(Icons.water_drop_outlined),
                  ),
                  validator: _validateBill,
                  onChanged: (_) => _invalidate(),
                ),
                const SizedBox(height: 28),
                Text(
                  'Allocation method',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  settings.isSummerMonth(_startDate)
                      ? 'Summer settings recommend electricity percentage for this start month.'
                      : 'Your saved default is used for this start month.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (widget.returnTo != null)
                  const _RoomDayMethodNotice()
                else
                  _MethodSelector(
                    selected: method,
                    enabled: settings.allowManualMethodOverride && !_saving,
                    onChanged: (value) {
                      setState(() {
                        _selectedMethod = value;
                        _result = null;
                        _error = null;
                      });
                    },
                  ),
                if (widget.returnTo == null &&
                    !settings.allowManualMethodOverride) ...[
                  const SizedBox(height: 8),
                  const Text('Method changes are locked in Water settings.'),
                ],
                if (usesElectricity) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<SummerElectricityBasis>(
                    initialValue: basis,
                    decoration: const InputDecoration(
                      labelText: 'Electricity basis',
                      helperText:
                          'Room charge excludes documented adjustments.',
                    ),
                    items: SummerElectricityBasis.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(formatSummerBasis(item)),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) {
                            setState(() {
                              _selectedBasis = value!;
                              _result = null;
                              _error = null;
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  _ElectricitySourcePanel(source: source, basis: basis),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _Notice(message: _error!, isError: true),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('review-water-button'),
                  onPressed: _saving || (usesElectricity && source == null)
                      ? null
                      : () => _calculate(
                          settings: settings,
                          electricityRecords: electricityRecords,
                          rooms: rooms,
                          boarders: boarders,
                          occupancies: occupancies,
                        ),
                  icon: const Icon(Icons.calculate_outlined),
                  label: const Text('Review allocation'),
                ),
                if (_result != null) ...[
                  const SizedBox(height: 32),
                  _CalculationPreview(result: _result!),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('save-water-record-button'),
                    onPressed: _saving ? null : () => _save(ownerId),
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_outline_rounded),
                    label: Text(_saving ? 'Saving…' : 'Save record'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MethodSelector extends StatelessWidget {
  const _MethodSelector({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final WaterBillingMethod selected;
  final bool enabled;
  final ValueChanged<WaterBillingMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 480 ||
            MediaQuery.textScalerOf(context).scale(16) > 20;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MethodButton(
                icon: Icons.people_outline_rounded,
                label: 'Person-days',
                selected: selected == WaterBillingMethod.personDays,
                onPressed: enabled
                    ? () => onChanged(WaterBillingMethod.personDays)
                    : null,
              ),
              const SizedBox(height: 8),
              _MethodButton(
                icon: Icons.meeting_room_outlined,
                label: 'Occupied room-days',
                selected: selected == WaterBillingMethod.roomDays,
                onPressed: enabled
                    ? () => onChanged(WaterBillingMethod.roomDays)
                    : null,
              ),
              const SizedBox(height: 8),
              _MethodButton(
                icon: Icons.bolt_outlined,
                label: 'Electricity percentage',
                selected: selected == WaterBillingMethod.electricityPercentage,
                onPressed: enabled
                    ? () => onChanged(WaterBillingMethod.electricityPercentage)
                    : null,
              ),
            ],
          );
        }
        return SegmentedButton<WaterBillingMethod>(
          segments: const [
            ButtonSegment(
              value: WaterBillingMethod.personDays,
              label: Text('Person-days'),
              icon: Icon(Icons.people_outline_rounded),
            ),
            ButtonSegment(
              value: WaterBillingMethod.roomDays,
              label: Text('Room-days'),
              icon: Icon(Icons.meeting_room_outlined),
            ),
            ButtonSegment(
              value: WaterBillingMethod.electricityPercentage,
              label: Text('Electricity %'),
              icon: Icon(Icons.bolt_outlined),
            ),
          ],
          selected: {selected},
          onSelectionChanged: enabled
              ? (selection) => onChanged(selection.first)
              : null,
        );
      },
    );
  }
}

class _RoomDayMethodNotice extends StatelessWidget {
  const _RoomDayMethodNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Occupied room-days selected. Each occupied room counts once per day regardless of boarder count.',
      child: Card(
        color: colors.secondaryContainer,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.meeting_room_outlined),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Occupied room-days: each room counts once for every occupied day, regardless of how many boarders stay there.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size.fromHeight(52),
          backgroundColor: selected ? colors.secondaryContainer : null,
          foregroundColor: selected ? colors.onSecondaryContainer : null,
          side: BorderSide(
            color: selected ? colors.primary : colors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        icon: Icon(selected ? Icons.check_circle_rounded : icon),
        label: Text(label),
      ),
    );
  }
}

class _ElectricitySourcePanel extends StatelessWidget {
  const _ElectricitySourcePanel({required this.source, required this.basis});

  final ElectricityBillingRecord? source;
  final SummerElectricityBasis basis;

  @override
  Widget build(BuildContext context) {
    if (source == null) {
      return const _Notice(
        isError: true,
        message: 'No electricity record has these exact dates. Save that electricity period first, or choose Person-days.',
      );
    }
    final value = switch (basis) {
      SummerElectricityBasis.roomElectricityCharge => formatPeso(
        source!.totalBaseChargeCentavos,
      ),
      SummerElectricityBasis.roomConsumption =>
        '${(source!.totalConsumptionWh / 1000).toStringAsFixed(3)} kWh',
    };
    return _Notice(
      message: 'Matched electricity record · total basis $value',
      isError: false,
    );
  }
}

class _CalculationPreview extends StatelessWidget {
  const _CalculationPreview({required this.result});

  final WaterCalculationResult result;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Allocation preview',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _PreviewRow(
                  label: 'Water bill',
                  value: formatPeso(result.waterBillCentavos),
                  emphasized: true,
                ),
                _PreviewRow(
                  label: result.method == WaterBillingMethod.roomDays
                      ? 'Allocated to rooms'
                      : 'Allocated to boarders',
                  value: formatPeso(result.totalAllocatedCentavos),
                ),
                _PreviewRow(
                  label: 'Unallocated / landlady-paid',
                  value: formatPeso(result.totalUnallocatedCentavos),
                ),
                _PreviewRow(
                  label: 'Method',
                  value: formatWaterMethod(result.method),
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
              child: _Notice(message: warning, isError: false),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          result.method == WaterBillingMethod.roomDays
              ? 'Room shares'
              : 'Boarder shares',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (result.method == WaterBillingMethod.roomDays)
          ...result.roomAllocations.map(
            (room) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      room.roomName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${room.occupancyDays} occupied ${room.occupancyDays == 1 ? 'room-day' : 'room-days'}',
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        formatPeso(room.roomChargeCentavos),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (result.boarderShares.isEmpty)
          const _Notice(
            message: 'No boarder occupied a room during this period.',
            isError: false,
          )
        else
          ...result.boarderShares.map(
            (share) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final details = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          share.boarderName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${share.occupancyDays} ${share.occupancyDays == 1 ? 'person-day' : 'person-days'} · ${share.roomIds.length} ${share.roomIds.length == 1 ? 'room' : 'rooms'}',
                        ),
                      ],
                    );
                    final amount = Text(
                      formatPeso(share.amountCentavos),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    );
                    if (constraints.maxWidth < 480 ||
                        MediaQuery.textScalerOf(context).scale(16) > 20) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          details,
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: amount,
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: details),
                        const SizedBox(width: 16),
                        amount,
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final valueText = Text(
      value,
      textAlign: TextAlign.end,
      style: TextStyle(
        fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 480 ||
              MediaQuery.textScalerOf(context).scale(16) > 20) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label),
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerRight, child: valueText),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: Text(label)),
              const SizedBox(width: 16),
              valueText,
            ],
          );
        },
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = isError
        ? colors.errorContainer
        : colors.tertiaryContainer;
    final foreground = isError
        ? colors.onErrorContainer
        : colors.onTertiaryContainer;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            color: foreground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: foreground)),
          ),
        ],
      ),
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
