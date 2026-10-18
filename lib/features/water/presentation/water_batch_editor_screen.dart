import 'package:flutter/material.dart';

import '../../../shared/widgets/app_components.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../electricity/application/electricity_providers.dart';
import '../../electricity/domain/electricity_batch_models.dart';
import '../../electricity/presentation/electricity_formatters.dart';
import '../../property_management/application/property_providers.dart';
import '../../property_management/domain/boarder.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/domain/occupancy.dart';
import '../../property_management/domain/room.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/water_providers.dart';
import '../domain/water_batch_models.dart';
import '../domain/water_calculator.dart';
import '../domain/water_models.dart';
import '../domain/water_repository.dart';
import '../domain/water_values.dart';
import 'water_formatters.dart';
import '../domain/water_selection.dart';
import 'water_selection_panel.dart';

import 'dart:convert';

class WaterBatchEditorScreen extends ConsumerStatefulWidget {
  const WaterBatchEditorScreen({this.batchId, super.key});

  final String? batchId;

  @override
  ConsumerState<WaterBatchEditorScreen> createState() =>
      _WaterBatchEditorScreenState();
}

class _WaterBatchEditorScreenState
    extends ConsumerState<WaterBatchEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _explanationController = TextEditingController();
  final _notesController = TextEditingController();
  late BusinessDate _startDate;
  late BusinessDate _endDateExclusive;
  late BusinessDate _receiptDate;
  WaterBillingMethod _method = WaterBillingMethod.selectedBoarders;
  List<WaterBoarderDecision> _decisions = [];
  String? _evidenceKey;
  SummerElectricityBasis _basis = SummerElectricityBasis.roomElectricityCharge;
  String? _electricityBatchId;
  bool _mismatchConfirmed = false;
  WaterCalculationResult? _result;
  String? _error;
  bool _busy = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    final today = BusinessDate.todayInManila();
    _receiptDate = today;
    _endDateExclusive = today;
    _startDate = BusinessDate(today.year, today.month, 1);
    if (!_startDate.isBefore(_endDateExclusive)) {
      _startDate = today.addDays(-1);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _explanationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _initialize(WaterBillingBatch? batch, WaterSettings settings) {
    if (_initialized) return;
    _initialized = true;
    if (batch != null) {
      _startDate = batch.startDate;
      _endDateExclusive = batch.endDateExclusive;
      _receiptDate = batch.receiptDate;
      _method = batch.method;
      _basis = batch.summerBasis;
      _electricityBatchId = batch.electricityBatchId;
      _mismatchConfirmed = batch.referencePeriodMismatchConfirmed;
      _amountController.text = _centavosInput(batch.waterBillCentavos);
      _explanationController.text = batch.referenceExplanation ?? '';
      _notesController.text = batch.notes ?? '';
      _result = batch;
      _decisions = batch.decisions;
      if (batch.method == WaterBillingMethod.selectedBoarders) _result = null;
    } else {
      final recommended = settings.methodFor(_startDate);
      _method = recommended == WaterBillingMethod.electricityPercentage
          ? recommended
          : WaterBillingMethod.selectedBoarders;
      _basis = settings.summerBasis;
    }
  }

  void _invalidate() {
    setState(() {
      _result = null;
      _error = null;
    });
  }

  ElectricityReadingBatch? _selectedBatch(
    List<ElectricityReadingBatch> batches,
  ) => batches
      .where((batch) => batch.batchId == _electricityBatchId)
      .firstOrNull;

  bool _periodMismatch(ElectricityReadingBatch? batch) =>
      batch != null &&
      waterAndElectricityPeriodsDiffer(
        waterStart: _startDate,
        waterEndExclusive: _endDateExclusive,
        electricityBatch: batch,
      );

  void _calculate({
    required List<ElectricityReadingBatch> electricityBatches,
    required List<Room> rooms,
    required List<Boarder> boarders,
    required List<Occupancy> occupancies,
  }) {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final source = _selectedBatch(electricityBatches);
    if (_method == WaterBillingMethod.electricityPercentage && source == null) {
      setState(() => _error = 'Select a finalized electricity batch.');
      return;
    }
    if (_periodMismatch(source) && !_mismatchConfirmed) {
      setState(
        () => _error = 'Confirm that the different electricity and water periods are intentional.',
      );
      return;
    }
    try {
      final result = const WaterCalculator().calculate(
        WaterCalculationInput(
          startDate: _startDate,
          endDateExclusive: _endDateExclusive,
          waterBillCentavos: WaterValues.parsePesosToCentavos(
            _amountController.text,
          ),
          method: _method,
          decisions: _decisions,
          summerBasis: _basis,
          rooms: rooms,
          boarders: boarders,
          occupancies: occupancies,
          electricityRecord: source == null
              ? null
              : electricityAllocationRecordFromBatch(
                  batch: source,
                  waterStart: _startDate,
                  waterEndExclusive: _endDateExclusive,
                ),
        ),
      );
      setState(() => _result = result);
    } catch (error) {
      setState(() => _error = propertyErrorMessage(error));
    }
  }

  Future<void> _save({required bool finalize}) async {
    final workspace = ref.read(appSessionProvider).state.workspace;
    final result = _result;
    if (workspace == null || result == null) return;
    final ownerId = workspace.ownerUid;
    final batches = ref
        .read(electricityReadingBatchesProvider(ownerId))
        .asData
        ?.value;
    final selected = batches == null ? null : _selectedBatch(batches);
    if (_method == WaterBillingMethod.electricityPercentage &&
        selected == null) {
      setState(() => _error = 'The selected electricity batch is unavailable.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(waterRepositoryProvider);
      final waterBatches = ref
          .read(waterBillingBatchesProvider(ownerId))
          .asData
          ?.value;
      final existing = widget.batchId == null || waterBatches == null
          ? null
          : waterBatches
                .where((batch) => batch.batchId == widget.batchId)
                .firstOrNull;
      var batchId = existing?.batchId;
      if (batchId == null) {
        batchId = await repository.createBillingBatchDraft(
          ownerId: ownerId,
          receiptDate: _receiptDate,
          result: result,
          electricityBatchId: selected?.batchId,
          referencePeriodMismatchConfirmed: _mismatchConfirmed,
          referenceExplanation: _explanationController.text,
          notes: _notesController.text,
        );
      } else {
        await repository.updateBillingBatchDraft(
          ownerId: ownerId,
          batchId: batchId,
          expectedVersion: existing!.version,
          receiptDate: _receiptDate,
          result: result,
          electricityBatchId: selected?.batchId,
          referencePeriodMismatchConfirmed: _mismatchConfirmed,
          referenceExplanation: _explanationController.text,
          notes: _notesController.text,
        );
      }
      if (finalize) {
        await repository.finalizeBillingBatch(
          ownerId: ownerId,
          batchId: batchId,
          expectedVersion: existing == null ? 1 : existing.version + 1,
        );
      }
      if (!mounted) return;
      ref.invalidate(waterBillingBatchesProvider(ownerId));
      context.go('/billing/water/batches/$batchId');
      showPropertyMessage(
        context,
        finalize ? 'Water batch finalized.' : 'Water batch saved as draft.',
      );
    } on WaterRepositoryException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = propertyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final settings = ref.watch(waterSettingsProvider(ownerId));
    final waterBatches = ref.watch(waterBillingBatchesProvider(ownerId));
    final electricityBatches = ref.watch(
      electricityReadingBatchesProvider(ownerId),
    );
    final rooms = ref.watch(roomsProvider(ownerId));
    final boarders = ref.watch(boardersProvider(ownerId));
    final occupancies = ref.watch(allOccupanciesProvider(ownerId));
    final sources = [
      settings,
      waterBatches,
      electricityBatches,
      rooms,
      boarders,
      occupancies,
    ];
    final error = sources.where((source) => source.hasError).firstOrNull;
    final loading = sources.any((source) => source.isLoading);
    WaterBillingBatch? existing;
    if (!loading && error == null && widget.batchId != null) {
      existing = waterBatches.requireValue
          .where((batch) => batch.batchId == widget.batchId)
          .firstOrNull;
    }
    if (!loading && error == null) {
      _initialize(existing, settings.requireValue);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.batchId == null ? 'New water batch' : 'Edit water batch',
        ),
      ),
      body: SafeArea(
        child: error != null
            ? ListView(
                children: [
                  AdaptivePageBody(
                    child: PropertyStatePanel(
                      icon: Icons.cloud_off_outlined,
                      title: 'Water batch data could not be loaded',
                      message: propertyErrorMessage(error.error!),
                    ),
                  ),
                ],
              )
            : loading
            ? const Center(child: CircularProgressIndicator())
            : widget.batchId != null && existing == null
            ? ListView(
                children: const [
                  AdaptivePageBody(
                    child: PropertyStatePanel(
                      icon: Icons.search_off_outlined,
                      title: 'Water batch not found',
                      message: 'It may no longer be available.',
                    ),
                  ),
                ],
              )
            : existing != null && !existing.canEdit
            ? ListView(
                children: [
                  AdaptivePageBody(
                    child: PropertyStatePanel(
                      icon: Icons.lock_outline,
                      title: 'This water batch is read-only',
                      message: 'Finalized, used, and voided batches cannot be edited.',
                      actionLabel: 'View batch',
                      onAction: () => context.go(
                        '/billing/water/batches/${existing!.batchId}',
                      ),
                    ),
                  ),
                ],
              )
            : _buildForm(
                electricityBatches: electricityBatches.requireValue
                    .where(
                      (batch) =>
                          batch.status ==
                              ElectricityReadingBatchStatus.finalized ||
                          batch.status ==
                              ElectricityReadingBatchStatus.usedInBilling,
                    )
                    .toList(),
                rooms: rooms.requireValue,
                boarders: boarders.requireValue,
                occupancies: occupancies.requireValue,
              ),
      ),
    );
  }

  Widget _buildForm({
    required List<ElectricityReadingBatch> electricityBatches,
    required List<Room> rooms,
    required List<Boarder> boarders,
    required List<Occupancy> occupancies,
  }) {
    String? selectionError;
    WaterCalculationResult? preview;
    if (_method == WaterBillingMethod.selectedBoarders) {
      try {
        final candidates = waterCandidates(
          start: _startDate,
          end: _endDateExclusive,
          rooms: rooms,
          boarders: boarders,
          occupancies: occupancies,
        );
        final key = jsonEncode(candidates.map((d) => d.toMap()).toList());
        if (key != _evidenceKey) {
          final old = {for (final d in _decisions) d.boarderId: d};
          _decisions = candidates.map((d) {
            final prior = old[d.boarderId];
            return prior != null &&
                    prior.boarderName == d.boarderName &&
                    prior.fullPeriod == d.fullPeriod &&
                    jsonEncode(
                          prior.occupancies.map((o) => o.toMap()).toList(),
                        ) ==
                        jsonEncode(d.occupancies.map((o) => o.toMap()).toList())
                ? prior
                : d;
          }).toList();
          _evidenceKey = key;
          _result = null;
        }
        preview = calculateSelectedWater(
          start: _startDate,
          end: _endDateExclusive,
          amount: WaterValues.parsePesosToCentavos(_amountController.text),
          decisions: _decisions,
        );
      } catch (error) {
        selectionError = error is WaterValidationException
            ? error.message
            : propertyErrorMessage(error);
        _result = null;
      }
    }
    final colors = Theme.of(context).colorScheme;
    final selected = _selectedBatch(electricityBatches);
    final mismatch = _periodMismatch(selected);
    final result = _result;
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
                  result == null
                      ? 'Water statement'
                      : 'Review water allocation',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  result == null
                      ? 'Step 1 of 2 · Enter the provider’s statement dates and choose how this bill should be allocated.'
                      : 'Step 2 of 2 · Confirm the source periods and exact allocations before finalizing.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                WorkflowProgress(
                  steps: const ['Statement', 'Review'],
                  current: result == null ? 0 : 1,
                ),
                if (result == null) ...[
                  _DateFields(
                    start: _startDate,
                    end: _endDateExclusive,
                    receipt: _receiptDate,
                    onStart: (value) {
                      _startDate = value;
                      _mismatchConfirmed = false;
                      _invalidate();
                    },
                    onEnd: (value) {
                      _endDateExclusive = value;
                      _mismatchConfirmed = false;
                      _invalidate();
                    },
                    onReceipt: (value) {
                      _receiptDate = value;
                      _invalidate();
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const Key('water-batch-amount'),
                    controller: _amountController,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Water bill total',
                      prefixIcon: Icon(Icons.water_drop_outlined),
                      prefixText: '₱ ',
                      helperText:
                          'Enter the exact amount on the provider statement.',
                    ),
                    validator: (value) {
                      try {
                        WaterValues.parsePesosToCentavos(value ?? '');
                        return null;
                      } on WaterValidationException catch (error) {
                        return error.message;
                      }
                    },
                    onChanged: (_) => _invalidate(),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Allocation method',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<WaterBillingMethod>(
                    segments: [
                      const ButtonSegment(
                        value: WaterBillingMethod.selectedBoarders,
                        label: Text('Normal'),
                        icon: Icon(Icons.people_outline),
                      ),
                      if (_method == WaterBillingMethod.personDays)
                        ButtonSegment(
                          value: WaterBillingMethod.personDays,
                          label: Text('Legacy person-days'),
                          icon: Icon(Icons.people_outline),
                        ),
                      ButtonSegment(
                        value: WaterBillingMethod.electricityPercentage,
                        label: Text('Electricity %'),
                        icon: Icon(Icons.bolt_outlined),
                      ),
                    ],
                    selected: {_method},
                    onSelectionChanged: _busy
                        ? null
                        : (value) {
                            setState(() {
                              _method = value.single;
                              _electricityBatchId = null;
                              _mismatchConfirmed = false;
                              _result = null;
                              _error = null;
                            });
                          },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _method == WaterBillingMethod.selectedBoarders
                        ? 'Choose who pays an equal share. Review partial occupants and transfer room decisions.'
                        : _method == WaterBillingMethod.personDays
                        ? 'Normal billing uses each boarder’s actual occupied days in the water statement period.'
                        : 'Summer billing uses room percentages from one explicitly selected finalized electricity batch.',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  if (_method == WaterBillingMethod.selectedBoarders)
                    WaterSelectionPanel(
                      key: ValueKey(_evidenceKey),
                      decisions: _decisions,
                      preview: preview,
                      validationMessage: selectionError,
                      onChanged: _busy
                          ? null
                          : (decision) => setState(() {
                              _decisions = _decisions
                                  .map(
                                    (d) => d.boarderId == decision.boarderId
                                        ? decision
                                        : d,
                                  )
                                  .toList();
                              _result = null;
                            }),
                    ),
                  if (_method == WaterBillingMethod.electricityPercentage) ...[
                    const SizedBox(height: 22),
                    DropdownButtonFormField<SummerElectricityBasis>(
                      initialValue: _basis,
                      decoration: const InputDecoration(
                        labelText: 'Electricity basis',
                      ),
                      items: SummerElectricityBasis.values
                          .map(
                            (basis) => DropdownMenuItem(
                              value: basis,
                              child: Text(formatSummerBasis(basis)),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (value) {
                              if (value != null) {
                                _basis = value;
                                _invalidate();
                              }
                            },
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Electricity reference',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select deliberately. A matching month is never chosen automatically.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    if (electricityBatches.isEmpty)
                      const PropertyStatePanel(
                        icon: Icons.electric_meter_outlined,
                        title: 'No finalized electricity batch',
                        message: 'Finalize an electricity reading batch first, or use normal selected-boarder billing.',
                      )
                    else
                      ...electricityBatches.map(
                        (batch) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ElectricityReferenceCard(
                            batch: batch,
                            selected: batch.batchId == _electricityBatchId,
                            onTap: _busy
                                ? null
                                : () => setState(() {
                                    _electricityBatchId = batch.batchId;
                                    _mismatchConfirmed = false;
                                    _result = null;
                                    _error = null;
                                  }),
                          ),
                        ),
                      ),
                    if (selected != null && mismatch) ...[
                      const SizedBox(height: 4),
                      Material(
                        color: colors.tertiaryContainer,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Different source periods',
                                style: TextStyle(
                                  color: colors.onTertiaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Water: ${formatWaterPeriod(_startDate, _endDateExclusive)}\nElectricity reading boundaries: ${formatBusinessDate(electricityBatchMeasurementStart(selected))} – ${formatBusinessDate(selected.effectiveDate)}',
                                style: TextStyle(
                                  color: colors.onTertiaryContainer,
                                ),
                              ),
                              CheckboxListTile(
                                key: const Key(
                                  'confirm-water-electricity-mismatch',
                                ),
                                contentPadding: EdgeInsets.zero,
                                value: _mismatchConfirmed,
                                onChanged: _busy
                                    ? null
                                    : (value) => setState(() {
                                        _mismatchConfirmed = value ?? false;
                                        _result = null;
                                      }),
                                title: const Text(
                                  'I confirm this reference is intentional',
                                ),
                              ),
                              TextFormField(
                                controller: _explanationController,
                                maxLength: 500,
                                decoration: const InputDecoration(
                                  labelText:
                                      'Association explanation (optional)',
                                ),
                                onChanged: (_) => _invalidate(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _notesController,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'Water batch notes (optional)',
                    ),
                    onChanged: (_) => _invalidate(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _ErrorPanel(message: _error!),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('review-water-batch'),
                    onPressed:
                        _busy ||
                            (_method == WaterBillingMethod.selectedBoarders &&
                                preview == null)
                        ? null
                        : () => _calculate(
                            electricityBatches: electricityBatches,
                            rooms: rooms,
                            boarders: boarders,
                            occupancies: occupancies,
                          ),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Review allocation'),
                  ),
                ] else ...[
                  _ReviewSummary(
                    result: result,
                    receiptDate: _receiptDate,
                    selected: selected,
                  ),
                  if (result.method == WaterBillingMethod.selectedBoarders)
                    WaterSelectionPanel(
                      decisions: result.decisions,
                      preview: result,
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _ErrorPanel(message: _error!),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    'Room allocation',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  ...result.roomAllocations.map(
                    (room) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              room.roomName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${formatPeso(room.roomChargeCentavos)} · ${room.occupancyDays} occupancy-days',
                            ),
                            if (room.unallocatedCentavos > 0)
                              Text(
                                '${formatPeso(room.unallocatedCentavos)} remains landlady-paid',
                                style: TextStyle(color: colors.error),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (result.warnings.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...result.warnings.map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ErrorPanel(message: warning, warning: true),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Material(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        'Finalizing preserves this allocation as an immutable source for future bills. It does not bill electricity again.',
                        style: TextStyle(color: colors.onErrorContainer),
                      ),
                    ),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    key: const Key('finalize-water-batch'),
                    onPressed: _busy ? null : () => _save(finalize: true),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Finalize water batch'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('save-water-batch-draft'),
                    onPressed: _busy ? null : () => _save(finalize: false),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save draft'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _result = null),
                    child: const Text('Back to edit'),
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

class _DateFields extends StatelessWidget {
  const _DateFields({
    required this.start,
    required this.end,
    required this.receipt,
    required this.onStart,
    required this.onEnd,
    required this.onReceipt,
  });
  final BusinessDate start;
  final BusinessDate end;
  final BusinessDate receipt;
  final ValueChanged<BusinessDate> onStart;
  final ValueChanged<BusinessDate> onEnd;
  final ValueChanged<BusinessDate> onReceipt;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fields = [
          _DateField(
            label: 'Statement start',
            value: start,
            lastDate: end.addDays(-1),
            onChanged: onStart,
          ),
          _DateField(
            label: 'Statement end (exclusive)',
            value: end,
            firstDate: start.addDays(1),
            onChanged: onEnd,
          ),
          _DateField(
            label: 'Bill receipt date',
            value: receipt,
            onChanged: onReceipt,
          ),
        ];
        if (constraints.maxWidth < 700 ||
            MediaQuery.textScalerOf(context).scale(16) > 20) {
          return Column(
            children: [
              fields[0],
              const SizedBox(height: 12),
              fields[1],
              const SizedBox(height: 12),
              fields[2],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: fields[0]),
            const SizedBox(width: 10),
            Expanded(child: fields[1]),
            const SizedBox(width: 10),
            Expanded(child: fields[2]),
          ],
        );
      },
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
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

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$label, ${formatBusinessDate(value)}',
    child: InkWell(
      onTap: () async {
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
      },
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(formatBusinessDate(value)),
      ),
    ),
  );
}

class _ElectricityReferenceCard extends StatelessWidget {
  const _ElectricityReferenceCard({
    required this.batch,
    required this.selected,
    required this.onTap,
  });
  final ElectricityReadingBatch batch;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${batch.batchReference}, ${formatBusinessDate(batch.effectiveDate)}, ${formatPeso(batch.totalChargeCentavos)}',
      child: Card(
        color: selected ? colors.primaryContainer : null,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.batchReference,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Read ${formatBusinessDate(batch.effectiveDate)} · ${formatElectricityReading(batch.totalConsumptionWh)} · ${formatPeso(batch.totalChargeCentavos)}',
                      ),
                      Text(
                        'Measured from ${formatBusinessDate(electricityBatchMeasurementStart(batch))}',
                        style: TextStyle(
                          color: selected
                              ? colors.onPrimaryContainer
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({
    required this.result,
    required this.receiptDate,
    required this.selected,
  });
  final WaterCalculationResult result;
  final BusinessDate receiptDate;
  final ElectricityReadingBatch? selected;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            formatWaterPeriod(result.startDate, result.endDateExclusive),
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Received ${formatBusinessDate(receiptDate)} · ${formatWaterMethod(result.method)}',
          ),
          if (selected != null)
            Text(
              'Electricity reference: ${selected!.batchReference} (${formatBusinessDate(electricityBatchMeasurementStart(selected!))} – ${formatBusinessDate(selected!.effectiveDate)})',
            ),
          const Divider(height: 24),
          Text(
            formatPeso(result.waterBillCentavos),
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${formatPeso(result.totalAllocatedCentavos)} allocated · ${formatPeso(result.totalUnallocatedCentavos)} landlady-paid',
          ),
        ],
      ),
    ),
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, this.warning = false});
  final String message;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = warning
        ? colors.tertiaryContainer
        : colors.errorContainer;
    final foreground = warning
        ? colors.onTertiaryContainer
        : colors.onErrorContainer;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              warning ? Icons.info_outline : Icons.error_outline,
              color: foreground,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: TextStyle(color: foreground)),
            ),
          ],
        ),
      ),
    );
  }
}

String _centavosInput(int centavos) {
  final whole = centavos ~/ 100;
  final fraction = (centavos % 100).toString().padLeft(2, '0');
  return fraction == '00' ? '$whole' : '$whole.$fraction';
}
