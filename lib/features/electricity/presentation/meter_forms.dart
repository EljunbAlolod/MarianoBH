import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../property_management/domain/business_date.dart';
import '../../property_management/domain/room.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/electricity_providers.dart';
import '../domain/electricity_models.dart';
import '../domain/electricity_values.dart';
import 'electricity_formatters.dart';

Future<bool?> showInitializeMeterSheet(
  BuildContext context, {
  required String ownerId,
  required Room room,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _InitializeMeterSheet(ownerId: ownerId, room: room),
  );
}

Future<bool?> showRecordReadingSheet(
  BuildContext context, {
  required String ownerId,
  required Room room,
  required ElectricityMeter meter,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _RecordReadingSheet(ownerId: ownerId, room: room, meter: meter),
  );
}

Future<bool?> showTransitionMeterSheet(
  BuildContext context, {
  required String ownerId,
  required Room room,
  required ElectricityMeter meter,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _TransitionMeterSheet(ownerId: ownerId, room: room, meter: meter),
  );
}

class _InitializeMeterSheet extends ConsumerStatefulWidget {
  const _InitializeMeterSheet({required this.ownerId, required this.room});

  final String ownerId;
  final Room room;

  @override
  ConsumerState<_InitializeMeterSheet> createState() =>
      _InitializeMeterSheetState();
}

class _InitializeMeterSheetState extends ConsumerState<_InitializeMeterSheet> {
  final _formKey = GlobalKey<FormState>();
  final _readingController = TextEditingController();
  final _noteController = TextEditingController();
  BusinessDate _date = BusinessDate.todayInManila();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _readingController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(electricityRepositoryProvider)
          .initializeMeter(
            ownerId: widget.ownerId,
            roomId: widget.room.roomId,
            openingDate: _date,
            openingReadingWh: ElectricityValues.parseKilowattHoursToWattHours(
              _readingController.text,
            ),
            note: _noteController.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = propertyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _MeterFormFrame(
      title: 'Set up ${widget.room.roomName} meter',
      description: 'Enter the existing meter value as a baseline. No electricity charge is created from this opening reading.',
      submitting: _submitting,
      error: _error,
      submitLabel: 'Save opening reading',
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BusinessDateField(
              label: 'Opening reading date',
              value: _date,
              enabled: !_submitting,
              onChanged: (value) => setState(() => _date = value),
            ),
            const SizedBox(height: 16),
            _KwhField(
              key: const Key('meter-opening-reading'),
              controller: _readingController,
              label: 'Opening meter reading',
              enabled: !_submitting,
            ),
            const SizedBox(height: 16),
            _NoteField(
              controller: _noteController,
              label: 'Setup note (optional)',
              enabled: !_submitting,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordReadingSheet extends ConsumerStatefulWidget {
  const _RecordReadingSheet({
    required this.ownerId,
    required this.room,
    required this.meter,
  });

  final String ownerId;
  final Room room;
  final ElectricityMeter meter;

  @override
  ConsumerState<_RecordReadingSheet> createState() =>
      _RecordReadingSheetState();
}

class _RecordReadingSheetState extends ConsumerState<_RecordReadingSheet> {
  final _formKey = GlobalKey<FormState>();
  final _readingController = TextEditingController();
  final _noteController = TextEditingController();
  late BusinessDate _date;
  MeterReadingKind _kind = MeterReadingKind.regular;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = BusinessDate.todayInManila();
  }

  @override
  void dispose() {
    _readingController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String? _validateReading(String? value) {
    try {
      final parsed = ElectricityValues.parseKilowattHoursToWattHours(
        value ?? '',
      );
      if (parsed < widget.meter.lastReadingWh) {
        return 'Must be at least ${formatElectricityReading(widget.meter.lastReadingWh)}.';
      }
      return null;
    } on ElectricityValidationException catch (error) {
      return error.message;
    }
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(electricityRepositoryProvider)
          .recordReading(
            ownerId: widget.ownerId,
            roomId: widget.room.roomId,
            readingDate: _date,
            readingWh: ElectricityValues.parseKilowattHoursToWattHours(
              _readingController.text,
            ),
            kind: _kind,
            note: _noteController.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = propertyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _MeterFormFrame(
      title: 'Record ${widget.room.roomName} reading',
      description:
          'Previous: ${formatElectricityReading(widget.meter.lastReadingWh)} on ${formatBusinessDate(widget.meter.lastReadingDate)}.',
      submitting: _submitting,
      error: _error,
      submitLabel: 'Save meter reading',
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<MeterReadingKind>(
              initialValue: _kind,
              decoration: const InputDecoration(
                labelText: 'Reading purpose',
                prefixIcon: Icon(Icons.electric_meter_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: MeterReadingKind.regular,
                  child: Text('Period boundary reading'),
                ),
                DropdownMenuItem(
                  value: MeterReadingKind.intermediate,
                  child: Text('Intermediate reading'),
                ),
              ],
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _kind = value!),
            ),
            const SizedBox(height: 8),
            Text(
              'Intermediate readings can improve allocations around occupancy changes. Enter every reading in date order; saved readings cannot be backfilled.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            _BusinessDateField(
              label: 'Reading date',
              value: _date,
              firstDate: widget.meter.lastReadingDate.addDays(1),
              enabled: !_submitting,
              onChanged: (value) => setState(() => _date = value),
            ),
            const SizedBox(height: 16),
            _KwhField(
              key: const Key('meter-current-reading'),
              controller: _readingController,
              label: 'Current meter reading',
              enabled: !_submitting,
              validator: _validateReading,
            ),
            const SizedBox(height: 16),
            _NoteField(
              controller: _noteController,
              label: 'Reading note (optional)',
              enabled: !_submitting,
            ),
          ],
        ),
      ),
    );
  }
}

class _TransitionMeterSheet extends ConsumerStatefulWidget {
  const _TransitionMeterSheet({
    required this.ownerId,
    required this.room,
    required this.meter,
  });

  final String ownerId;
  final Room room;
  final ElectricityMeter meter;

  @override
  ConsumerState<_TransitionMeterSheet> createState() =>
      _TransitionMeterSheetState();
}

class _TransitionMeterSheetState extends ConsumerState<_TransitionMeterSheet> {
  final _formKey = GlobalKey<FormState>();
  final _closingController = TextEditingController();
  final _openingController = TextEditingController();
  final _reasonController = TextEditingController();
  late BusinessDate _date;
  ElectricityMeterStartKind _kind = ElectricityMeterStartKind.reset;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = BusinessDate.todayInManila();
    _closingController.text = ElectricityValues.formatWattHoursAsKilowattHours(
      widget.meter.lastReadingWh,
    );
  }

  @override
  void dispose() {
    _closingController.dispose();
    _openingController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  String? _validateClosing(String? value) {
    try {
      final parsed = ElectricityValues.parseKilowattHoursToWattHours(
        value ?? '',
      );
      if (parsed < widget.meter.lastReadingWh) {
        return 'Must be at least ${formatElectricityReading(widget.meter.lastReadingWh)}.';
      }
      return null;
    } on ElectricityValidationException catch (error) {
      return error.message;
    }
  }

  String? _validateReason(String? value) {
    final clean = value?.trim() ?? '';
    if (clean.isEmpty) return 'A reason is required.';
    if (clean.length > 500) return 'Use 500 characters or fewer.';
    return null;
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.history_rounded),
        title: const Text('Start a new meter sequence?'),
        content: const Text(
          'The current sequence will become read-only. Its readings remain in history and will not be overwritten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Start new sequence'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      await ref
          .read(electricityRepositoryProvider)
          .transitionMeter(
            ownerId: widget.ownerId,
            roomId: widget.room.roomId,
            transitionDate: _date,
            closingReadingWh: ElectricityValues.parseKilowattHoursToWattHours(
              _closingController.text,
            ),
            newOpeningReadingWh:
                ElectricityValues.parseKilowattHoursToWattHours(
                  _openingController.text,
                ),
            startKind: _kind,
            reason: _reasonController.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = propertyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _MeterFormFrame(
      title: 'Reset, replace, or start clean',
      description: 'Close the current sequence, then record a new opening value. Use Start clean sequence when values can no longer be compared. Past readings stay unchanged.',
      submitting: _submitting,
      error: _error,
      submitLabel: 'Review sequence change',
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<ElectricityMeterStartKind>(
              initialValue: _kind,
              decoration: const InputDecoration(
                labelText: 'Change type',
                prefixIcon: Icon(Icons.swap_horiz_rounded),
              ),
              items: const [
                DropdownMenuItem(
                  value: ElectricityMeterStartKind.reset,
                  child: Text('Meter reset'),
                ),
                DropdownMenuItem(
                  value: ElectricityMeterStartKind.replacement,
                  child: Text('Meter replacement'),
                ),
                DropdownMenuItem(
                  value: ElectricityMeterStartKind.correction,
                  child: Text('Start clean sequence'),
                ),
              ],
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _kind = value!),
            ),
            const SizedBox(height: 16),
            _BusinessDateField(
              label: 'Change date',
              value: _date,
              firstDate: widget.meter.lastReadingDate.addDays(1),
              enabled: !_submitting,
              onChanged: (value) => setState(() => _date = value),
            ),
            const SizedBox(height: 16),
            _KwhField(
              controller: _closingController,
              label: 'Old meter closing reading',
              enabled: !_submitting,
              validator: _validateClosing,
            ),
            const SizedBox(height: 16),
            _KwhField(
              controller: _openingController,
              label: 'New sequence opening reading',
              enabled: !_submitting,
            ),
            const SizedBox(height: 16),
            _NoteField(
              controller: _reasonController,
              label: 'Reason',
              enabled: !_submitting,
              validator: _validateReason,
              maxLength: 500,
            ),
          ],
        ),
      ),
    );
  }
}

class _MeterFormFrame extends StatelessWidget {
  const _MeterFormFrame({
    required this.title,
    required this.description,
    required this.submitting,
    required this.error,
    required this.submitLabel,
    required this.onSubmit,
    required this.child,
  });

  final String title;
  final String description;
  final bool submitting;
  final String? error;
  final String submitLabel;
  final VoidCallback onSubmit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: submitting
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                child,
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: submitting ? null : onSubmit,
                  icon: submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(submitting ? 'Saving…' : submitLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BusinessDateField extends StatelessWidget {
  const _BusinessDateField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.firstDate,
  });

  final String label;
  final BusinessDate value;
  final bool enabled;
  final ValueChanged<BusinessDate> onChanged;
  final BusinessDate? firstDate;

  Future<void> _pick(BuildContext context) async {
    final today = BusinessDate.todayInManila();
    final first = firstDate ?? BusinessDate(2000, 1, 1);
    final selected = await showDatePicker(
      context: context,
      helpText: label,
      initialDate: DateTime(value.year, value.month, value.day),
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: DateTime(today.year, today.month, today.day),
    );
    if (selected != null) onChanged(BusinessDate.fromDateTime(selected));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, ${formatBusinessDate(value)}',
      child: InkWell(
        onTap: enabled ? () => _pick(context) : null,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.calendar_today_outlined),
            suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
            enabled: enabled,
          ),
          child: Text(formatBusinessDate(value)),
        ),
      ),
    );
  }
}

class _KwhField extends StatelessWidget {
  const _KwhField({
    required this.controller,
    required this.label,
    required this.enabled,
    this.validator,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final FormFieldValidator<String>? validator;

  String? _defaultValidator(String? value) {
    try {
      ElectricityValues.parseKilowattHoursToWattHours(value ?? '');
      return null;
    } on ElectricityValidationException catch (error) {
      return error.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: key,
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'kWh',
        helperText: 'Use up to three decimal places.',
        prefixIcon: const Icon(Icons.speed_outlined),
      ),
      validator: validator ?? _defaultValidator,
    );
  }
}

class _NoteField extends StatelessWidget {
  const _NoteField({
    required this.controller,
    required this.label,
    required this.enabled,
    this.validator,
    this.maxLength = 500,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final FormFieldValidator<String>? validator;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      minLines: 2,
      maxLines: 4,
      maxLength: maxLength,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
      validator: validator,
    );
  }
}
