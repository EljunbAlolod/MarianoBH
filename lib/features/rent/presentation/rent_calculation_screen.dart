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
import '../application/rent_providers.dart';
import '../domain/rent_calculator.dart';
import '../domain/rent_models.dart';
import 'rent_formatters.dart';

class RentCalculationScreen extends ConsumerStatefulWidget {
  const RentCalculationScreen({
    super.key,
    this.initialStartDate,
    this.initialEndDateExclusive,
    this.returnTo,
  });

  final BusinessDate? initialStartDate;
  final BusinessDate? initialEndDateExclusive;
  final String? returnTo;

  @override
  ConsumerState<RentCalculationScreen> createState() =>
      _RentCalculationScreenState();
}

class _RentCalculationScreenState extends ConsumerState<RentCalculationScreen> {
  late BusinessDate _startDate;
  late BusinessDate _endDateExclusive;
  RentBillingMode? _mode;
  final List<BillingAdjustment> _adjustments = [];
  RentCalculationResult? _result;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final today = BusinessDate.todayInManila();
    _endDateExclusive = widget.initialEndDateExclusive ?? today;
    _startDate =
        widget.initialStartDate ?? BusinessDate(today.year, today.month, 1);
    if (!_startDate.isBefore(_endDateExclusive)) _startDate = today.addDays(-1);
    if (widget.returnTo != null) _mode = RentBillingMode.perRoom;
  }

  void _invalidate() {
    setState(() {
      _result = null;
      _error = null;
    });
  }

  void _calculate({
    required RentSettings settings,
    required List<Room> rooms,
    required List<Boarder> boarders,
    required List<Occupancy> occupancies,
  }) {
    try {
      final result = const RentCalculator().calculate(
        RentCalculationInput(
          startDate: _startDate,
          endDateExclusive: _endDateExclusive,
          mode: _mode ?? settings.mode,
          rooms: rooms,
          boarders: boarders,
          occupancies: occupancies,
          adjustments: _adjustments,
        ),
      );
      setState(() {
        _result = result;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _result = null;
        _error = propertyErrorMessage(error);
      });
    }
  }

  Future<void> _addAdjustment({
    required List<Boarder> boarders,
    required List<Occupancy> occupancies,
  }) async {
    final eligibleIds = occupancies
        .where(
          (item) =>
              item.moveInDate.isBefore(_endDateExclusive) &&
              (item.moveOutDate == null ||
                  _startDate.isBefore(item.moveOutDate!)),
        )
        .map((item) => item.boarderId)
        .toSet();
    final eligible =
        boarders.where((item) => eligibleIds.contains(item.boarderId)).toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));
    if (eligible.isEmpty) {
      showPropertyMessage(
        context,
        'No boarder occupied a room during this period.',
        isError: true,
      );
      return;
    }
    final value = await showDialog<BillingAdjustment>(
      context: context,
      builder: (context) => _AdjustmentDialog(
        boarders: eligible,
        startDate: _startDate,
        endDateExclusive: _endDateExclusive,
      ),
    );
    if (value == null) return;
    setState(() {
      _adjustments.add(value);
      _result = null;
      _error = null;
    });
  }

  Future<void> _save(String ownerId) async {
    final result = _result;
    if (result == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.lock_outline_rounded),
        title: const Text('Save this rent record?'),
        content: const Text(
          'The policy, dates, room rates, occupancy shares, and adjustments will be preserved as a read-only snapshot.',
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
          .read(rentRepositoryProvider)
          .recordBillingSnapshot(
            ownerId: ownerId,
            result: result,
            roomBillingSource: widget.returnTo != null,
          );
      if (mounted) {
        context.go(widget.returnTo ?? '/billing/rent/$id');
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
    final settings = ref.watch(rentSettingsProvider(ownerId));
    final rooms = ref.watch(roomsProvider(ownerId));
    final boarders = ref.watch(boardersProvider(ownerId));
    final occupancies = ref.watch(allOccupanciesProvider(ownerId));
    final sources = [settings, rooms, boarders, occupancies];
    final errorSource = sources.where((source) => source.hasError).firstOrNull;
    final loading = sources.any((source) => source.isLoading);

    return Scaffold(
      appBar: AppBar(title: const Text('Calculate rent')),
      body: SafeArea(
        child: errorSource != null
            ? AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Calculation data could not be loaded',
                  message: propertyErrorMessage(errorSource.error!),
                  actionLabel: 'Try again',
                  onAction: () {
                    ref.invalidate(rentSettingsProvider(ownerId));
                    ref.invalidate(roomsProvider(ownerId));
                    ref.invalidate(boardersProvider(ownerId));
                    ref.invalidate(allOccupanciesProvider(ownerId));
                  },
                ),
              )
            : loading
            ? const Center(child: CircularProgressIndicator())
            : _form(
                ownerId: ownerId,
                settings: settings.requireValue,
                rooms: rooms.requireValue,
                boarders: boarders.requireValue,
                occupancies: occupancies.requireValue,
              ),
      ),
    );
  }

  Widget _form({
    required String ownerId,
    required RentSettings settings,
    required List<Room> rooms,
    required List<Boarder> boarders,
    required List<Occupancy> occupancies,
  }) {
    final mode = _mode ?? settings.mode;
    final occupiedRoomIds = occupancies
        .where(
          (item) =>
              item.moveInDate.isBefore(_endDateExclusive) &&
              (item.moveOutDate == null ||
                  _startDate.isBefore(item.moveOutDate!)),
        )
        .map((item) => item.roomId)
        .toSet();
    final missingRates = mode == RentBillingMode.disabled
        ? <Room>[]
        : rooms
              .where(
                (room) =>
                    occupiedRoomIds.contains(room.roomId) &&
                    room.defaultMonthlyRentCentavos == null,
              )
              .toList();
    return ListView(
      children: [
        AdaptivePageBody(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Period and policy',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'The end date is exclusive. A boarder moving out on that date is not charged for that day.',
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
                    label: 'First billable day',
                    value: _startDate,
                    lastDate: _endDateExclusive.addDays(-1),
                    onChanged: (value) {
                      _startDate = value;
                      _adjustments.clear();
                      _invalidate();
                    },
                  );
                  final end = _PeriodDateField(
                    label: 'End date (not billed)',
                    value: _endDateExclusive,
                    firstDate: _startDate.addDays(1),
                    onChanged: (value) {
                      _endDateExclusive = value;
                      _adjustments.clear();
                      _invalidate();
                    },
                  );
                  if (stacked) {
                    return Column(
                      children: [start, const SizedBox(height: 12), end],
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
              const SizedBox(height: 20),
              Text(
                'Billing policy',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (widget.returnTo != null)
                const _Notice(
                  isError: false,
                  message: 'Per-room billing is selected. Each room is prorated once by its occupied days, regardless of boarder count.',
                )
              else
                ...RentBillingMode.values.map(
                  (value) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ModeTile(
                      mode: value,
                      selected: value == mode,
                      onTap: () {
                        _mode = value;
                        _invalidate();
                      },
                    ),
                  ),
                ),
              if (missingRates.isNotEmpty) ...[
                const SizedBox(height: 8),
                _Notice(
                  isError: true,
                  message:
                      'Set a monthly rent for ${missingRates.map((room) => room.roomName).join(', ')} before calculating.',
                ),
              ],
              if (widget.returnTo == null) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Adjustments',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('add-rent-adjustment-button'),
                      onPressed: () => _addAdjustment(
                        boarders: boarders,
                        occupancies: occupancies,
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                Text(
                  'Corrections remain separate from occupancy and room rates.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                if (_adjustments.isEmpty)
                  const _Notice(
                    isError: false,
                    message: 'No charges or credits added.',
                  )
                else
                  ..._adjustments.asMap().entries.map(
                    (entry) => Card(
                      child: ListTile(
                        title: Text(
                          entry.value.reason,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${formatBusinessDate(entry.value.adjustmentDate)} - ${entry.value.type == BillingAdjustmentType.charge ? 'Charge' : 'Credit'}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove adjustment',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () {
                            setState(() {
                              _adjustments.removeAt(entry.key);
                              _result = null;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('review-rent-button'),
                onPressed: missingRates.isEmpty
                    ? () => _calculate(
                        settings: settings,
                        rooms: rooms,
                        boarders: boarders,
                        occupancies: occupancies,
                      )
                    : null,
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('Review calculation'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _Notice(isError: true, message: _error!),
              ],
              if (_result != null) ...[
                const SizedBox(height: 28),
                _Preview(result: _result!),
                const SizedBox(height: 18),
                FilledButton.icon(
                  key: const Key('save-rent-record-button'),
                  onPressed: _saving ? null : () => _save(ownerId),
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_outline_rounded),
                  label: Text(_saving ? 'Saving...' : 'Save record'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });
  final RentBillingMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? colors.primaryContainer.withValues(alpha: 0.45)
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatRentMode(mode),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(describeRentMode(mode)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.result});
  final RentCalculationResult result;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Review',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _ValueRow(
                  label: 'Billable days',
                  value: '${result.periodDays}',
                ),
                _ValueRow(
                  label: 'Rent',
                  value: formatPeso(result.totalRentCentavos),
                ),
                _ValueRow(
                  label: 'Adjustments',
                  value: _signedPeso(result.totalAdjustmentCentavos),
                ),
                const Divider(height: 24),
                _ValueRow(
                  label: 'Total',
                  value: formatPeso(result.grandTotalCentavos),
                  emphasized: true,
                ),
              ],
            ),
          ),
        ),
        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...result.warnings.map(
            (message) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Notice(isError: false, message: message),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Boarder charges',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (result.boarderCharges.isEmpty)
          const _Notice(
            isError: false,
            message: 'No boarder charges for this period.',
          )
        else
          ...result.boarderCharges.map(
            (charge) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      charge.boarderName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${charge.occupancyDays} occupancy ${charge.occupancyDays == 1 ? 'day' : 'days'}',
                    ),
                    const SizedBox(height: 8),
                    _ValueRow(
                      label: 'Rent',
                      value: formatPeso(charge.rentCentavos),
                    ),
                    if (charge.adjustmentCentavos != 0)
                      _ValueRow(
                        label: 'Adjustments',
                        value: _signedPeso(charge.adjustmentCentavos),
                      ),
                    _ValueRow(
                      label: 'Total',
                      value: formatPeso(charge.totalCentavos),
                      emphasized: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AdjustmentDialog extends StatefulWidget {
  const _AdjustmentDialog({
    required this.boarders,
    required this.startDate,
    required this.endDateExclusive,
  });
  final List<Boarder> boarders;
  final BusinessDate startDate;
  final BusinessDate endDateExclusive;

  @override
  State<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<_AdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  late String _boarderId = widget.boarders.first.boarderId;
  BillingAdjustmentType _type = BillingAdjustmentType.charge;
  late BusinessDate _date = widget.endDateExclusive.addDays(-1);

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      BillingAdjustment(
        adjustmentId: 'adjustment-${DateTime.now().microsecondsSinceEpoch}',
        boarderId: _boarderId,
        type: _type,
        amountCentavos: parsePesoToCentavos(_amountController.text)!,
        reason: _reasonController.text.trim(),
        adjustmentDate: _date,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add adjustment'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _boarderId,
                  decoration: const InputDecoration(labelText: 'Boarder'),
                  items: widget.boarders
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.boarderId,
                          child: Text(item.fullName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _boarderId = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<BillingAdjustmentType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(
                      value: BillingAdjustmentType.charge,
                      child: Text('Charge'),
                    ),
                    DropdownMenuItem(
                      value: BillingAdjustmentType.credit,
                      child: Text('Credit'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _type = value!),
                ),
                const SizedBox(height: 12),
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
                    prefixText: 'PHP ',
                  ),
                  validator: (value) {
                    try {
                      final amount = parsePesoToCentavos(value ?? '');
                      if (amount == null || amount <= 0) {
                        return 'Enter an amount greater than zero.';
                      }
                    } on FormatException catch (error) {
                      return error.message;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reasonController,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  validator: (value) {
                    final length = value?.trim().length ?? 0;
                    return length < 3
                        ? 'Explain the adjustment in at least 3 characters.'
                        : null;
                  },
                ),
                const SizedBox(height: 8),
                _PeriodDateField(
                  label: 'Adjustment date',
                  value: _date,
                  firstDate: widget.startDate,
                  lastDate: widget.endDateExclusive.addDays(-1),
                  onChanged: (value) => setState(() => _date = value),
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
    final valueWidget = Text(
      value,
      textAlign: TextAlign.end,
      style: TextStyle(
        fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 440 ||
              MediaQuery.textScalerOf(context).scale(16) > 20) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label),
                const SizedBox(height: 3),
                Align(alignment: Alignment.centerRight, child: valueWidget),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label)),
              const SizedBox(width: 16),
              Flexible(child: valueWidget),
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

String _signedPeso(int centavos) {
  if (centavos == 0) return formatPeso(0);
  return '${centavos > 0 ? '+' : '-'}${formatPeso(centavos.abs())}';
}
