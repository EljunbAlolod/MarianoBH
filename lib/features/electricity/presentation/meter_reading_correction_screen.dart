import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/application/property_providers.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/electricity_providers.dart';
import '../domain/electricity_models.dart';
import '../domain/electricity_repository.dart';
import '../domain/electricity_values.dart';
import 'electricity_formatters.dart';

class MeterReadingCorrectionScreen extends ConsumerStatefulWidget {
  const MeterReadingCorrectionScreen({
    required this.roomId,
    required this.readingId,
    super.key,
  });

  final String roomId;
  final String readingId;

  @override
  ConsumerState<MeterReadingCorrectionScreen> createState() =>
      _MeterReadingCorrectionScreenState();
}

class _MeterReadingCorrectionScreenState
    extends ConsumerState<MeterReadingCorrectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _readingController = TextEditingController();
  final _reasonController = TextEditingController();
  BusinessDate? _correctedDate;
  String? _loadedRevision;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _readingController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _initialize(MeterReading reading) {
    final revision = '${reading.readingId}:${reading.correctionCount}';
    if (_loadedRevision == revision) return;
    _loadedRevision = revision;
    _correctedDate = reading.readingDate;
    _readingController.text = ElectricityValues.formatWattHoursAsKilowattHours(
      reading.readingWh,
    );
  }

  String? _validateReading(String? value, MeterReading reading) {
    try {
      final parsed = ElectricityValues.parseKilowattHoursToWattHours(
        value ?? '',
      );
      final minimum = reading.previousReadingWh;
      if (minimum != null && parsed < minimum) {
        return 'Must be at least ${formatElectricityReading(minimum)}.';
      }
      return null;
    } on ElectricityValidationException catch (error) {
      return error.message;
    }
  }

  String? _validateReason(String? value) {
    final clean = value?.trim() ?? '';
    if (clean.length < 3) return 'Enter at least 3 characters.';
    if (clean.length > 500) return 'Use 500 characters or fewer.';
    return null;
  }

  Future<void> _submit({
    required String ownerId,
    required String roomName,
    required MeterReading reading,
  }) async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final correctedDate = _correctedDate!;
    final correctedWh = ElectricityValues.parseKilowattHoursToWattHours(
      _readingController.text,
    );
    if (correctedDate == reading.readingDate &&
        correctedWh == reading.readingWh) {
      setState(() {
        _error = 'Change the reading date, meter value, or both.';
      });
      return;
    }
    final previousWh = reading.previousReadingWh;
    final correctedConsumption = previousWh == null
        ? 0
        : correctedWh - previousWh;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _CorrectionReviewDialog(
        roomName: roomName,
        reading: reading,
        correctedDate: correctedDate,
        correctedWh: correctedWh,
        correctedConsumption: correctedConsumption,
        reason: _reasonController.text.trim(),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(electricityRepositoryProvider)
          .correctLatestReading(
            ownerId: ownerId,
            roomId: widget.roomId,
            readingId: reading.readingId,
            expectedReadingDate: reading.readingDate,
            expectedReadingWh: reading.readingWh,
            expectedCorrectionCount: reading.correctionCount,
            correctedReadingDate: correctedDate,
            correctedReadingWh: correctedWh,
            reason: _reasonController.text,
          );
      if (mounted) context.pop(true);
    } on ElectricityRepositoryException catch (error) {
      if (!mounted) return;
      if (error.isConflict) {
        ref.invalidate(meterReadingsProvider(ownerId));
        ref.invalidate(electricityMetersProvider(ownerId));
        ref.invalidate(electricityBillingRecordsProvider(ownerId));
        ref.invalidate(meterReadingCorrectionsProvider(ownerId));
        showPropertyMessage(context, error.message);
        context.pop(false);
      } else {
        setState(() => _error = error.message);
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
    final states = ref.watch(roomMeterStatesProvider(ownerId));
    final meters = ref.watch(electricityMetersProvider(ownerId));
    final readings = ref.watch(meterReadingsProvider(ownerId));
    final sources = [rooms, states, meters, readings];
    final errorSource = sources.where((source) => source.hasError).firstOrNull;
    final loading = sources.any((source) => source.isLoading);

    Widget body;
    if (errorSource != null) {
      body = AdaptivePageBody(
        child: PropertyStatePanel(
          icon: Icons.cloud_off_outlined,
          title: 'Reading could not be loaded',
          message: propertyErrorMessage(errorSource.error!),
          actionLabel: 'Try again',
          onAction: () {
            ref.invalidate(roomsProvider(ownerId));
            ref.invalidate(roomMeterStatesProvider(ownerId));
            ref.invalidate(electricityMetersProvider(ownerId));
            ref.invalidate(meterReadingsProvider(ownerId));
          },
        ),
      );
    } else if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final room = rooms.requireValue
          .where((item) => item.roomId == widget.roomId)
          .firstOrNull;
      final reading = readings.requireValue
          .where((item) => item.readingId == widget.readingId)
          .firstOrNull;
      final state = states.requireValue
          .where((item) => item.roomId == widget.roomId)
          .firstOrNull;
      final activeMeter = state == null
          ? null
          : meters.requireValue
                .where((item) => item.meterId == state.currentMeterId)
                .firstOrNull;
      if (room == null || reading == null) {
        body = const AdaptivePageBody(
          child: PropertyStatePanel(
            icon: Icons.search_off_rounded,
            title: 'Reading not found',
            message: 'Return to reading history and refresh the latest values.',
          ),
        );
      } else {
        final eligibility = meterReadingCorrectionEligibility(
          reading: reading,
          activeMeter: activeMeter,
        );
        if (eligibility != MeterReadingCorrectionEligibility.eligible) {
          body = AdaptivePageBody(
            child: PropertyStatePanel(
              icon: Icons.lock_outline_rounded,
              title: 'Reading is read-only',
              message: 'This reading is no longer eligible for correction. Return to history to see the current reason.',
              actionLabel: 'Back to history',
              onAction: () => context.pop(),
            ),
          );
        } else {
          _initialize(reading);
          body = _CorrectionForm(
            formKey: _formKey,
            roomName: room.roomName,
            reading: reading,
            correctedDate: _correctedDate!,
            readingController: _readingController,
            reasonController: _reasonController,
            saving: _saving,
            error: _error,
            validateReading: (value) => _validateReading(value, reading),
            validateReason: _validateReason,
            onDateChanged: (value) => setState(() => _correctedDate = value),
            onSubmit: () => _submit(
              ownerId: ownerId,
              roomName: room.roomName,
              reading: reading,
            ),
          );
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Correct reading')),
      body: SafeArea(child: body),
    );
  }
}

class _CorrectionForm extends StatelessWidget {
  const _CorrectionForm({
    required this.formKey,
    required this.roomName,
    required this.reading,
    required this.correctedDate,
    required this.readingController,
    required this.reasonController,
    required this.saving,
    required this.error,
    required this.validateReading,
    required this.validateReason,
    required this.onDateChanged,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final String roomName;
  final MeterReading reading;
  final BusinessDate correctedDate;
  final TextEditingController readingController;
  final TextEditingController reasonController;
  final bool saving;
  final String? error;
  final FormFieldValidator<String> validateReading;
  final FormFieldValidator<String> validateReason;
  final ValueChanged<BusinessDate> onDateChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        AdaptivePageBody(
          maxWidth: 680,
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  roomName,
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Correct the latest unbilled reading. Its identity, purpose, predecessor, and original creation time remain unchanged.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                _CurrentReadingPanel(reading: reading),
                const SizedBox(height: 20),
                _CorrectionDateField(
                  value: correctedDate,
                  firstDate: reading.previousReadingDate?.addDays(1),
                  enabled: !saving,
                  onChanged: onDateChanged,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('corrected-reading-value'),
                  controller: readingController,
                  enabled: !saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Corrected meter reading',
                    suffixText: 'kWh',
                    helperText: 'Use up to three decimal places.',
                    prefixIcon: Icon(Icons.speed_outlined),
                  ),
                  validator: validateReading,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('correction-reason'),
                  controller: reasonController,
                  enabled: !saving,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Correction reason',
                    helperText:
                        'Required. This becomes part of the audit history.',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.edit_note_rounded),
                  ),
                  validator: validateReason,
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
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
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('review-reading-correction'),
                  onPressed: saving ? null : onSubmit,
                  icon: saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fact_check_outlined),
                  label: Text(saving ? 'Saving...' : 'Review correction'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CurrentReadingPanel extends StatelessWidget {
  const _CurrentReadingPanel({required this.reading});

  final MeterReading reading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Currently saved',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '${formatBusinessDate(reading.readingDate)} - ${formatElectricityReading(reading.readingWh)}',
            ),
            const SizedBox(height: 4),
            Text(
              'Derived consumption: ${formatElectricityReading(reading.consumptionWh)}',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _CorrectionDateField extends StatelessWidget {
  const _CorrectionDateField({
    required this.value,
    required this.firstDate,
    required this.enabled,
    required this.onChanged,
  });

  final BusinessDate value;
  final BusinessDate? firstDate;
  final bool enabled;
  final ValueChanged<BusinessDate> onChanged;

  Future<void> _pick(BuildContext context) async {
    final today = BusinessDate.todayInManila();
    final first = firstDate ?? BusinessDate(2000, 1, 1);
    final selected = await showDatePicker(
      context: context,
      helpText: 'Corrected reading date',
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
      label: 'Corrected reading date, ${formatBusinessDate(value)}',
      child: InkWell(
        onTap: enabled ? () => _pick(context) : null,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Corrected reading date',
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

class _CorrectionReviewDialog extends StatelessWidget {
  const _CorrectionReviewDialog({
    required this.roomName,
    required this.reading,
    required this.correctedDate,
    required this.correctedWh,
    required this.correctedConsumption,
    required this.reason,
  });

  final String roomName;
  final MeterReading reading;
  final BusinessDate correctedDate;
  final int correctedWh;
  final int correctedConsumption;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final consumptionDifference = correctedConsumption - reading.consumptionWh;
    final formattedDifference = consumptionDifference == 0
        ? formatElectricityReading(0)
        : consumptionDifference < 0
        ? '-${formatElectricityReading(-consumptionDifference)}'
        : '+${formatElectricityReading(consumptionDifference)}';
    final affectedPeriod = reading.previousReadingDate == null
        ? 'Opening baseline begins ${formatBusinessDate(correctedDate)}. No consumption is charged by the baseline itself.'
        : '${formatBusinessDate(reading.previousReadingDate!)} to ${formatBusinessDate(correctedDate)}';
    return AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.warning_amber_rounded),
      title: const Text('Correct this meter reading?'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'This changes the saved date or meter value and may affect future electricity calculations. Existing billing records will not change. The previous values and reason will be permanently recorded.',
          ),
          const SizedBox(height: 16),
          _ReviewFact(label: 'Room', value: roomName),
          _ReviewFact(
            label: 'Before',
            value:
                '${formatBusinessDate(reading.readingDate)} - ${formatElectricityReading(reading.readingWh)}',
          ),
          _ReviewFact(
            label: 'After',
            value:
                '${formatBusinessDate(correctedDate)} - ${formatElectricityReading(correctedWh)}',
          ),
          _ReviewFact(
            label: 'Consumption difference',
            value: formattedDifference,
          ),
          _ReviewFact(label: 'Affected period', value: affectedPeriod),
          _ReviewFact(label: 'Reason', value: reason),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Go back'),
        ),
        FilledButton(
          key: const Key('confirm-reading-correction'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirm correction'),
        ),
      ],
    );
  }
}

class _ReviewFact extends StatelessWidget {
  const _ReviewFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w700),
          children: [
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}
