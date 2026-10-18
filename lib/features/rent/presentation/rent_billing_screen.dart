import 'package:flutter/material.dart';

import '../../../shared/widgets/app_components.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/application/property_providers.dart';
import '../../property_management/domain/business_date.dart';
import '../../property_management/domain/boarder.dart';
import '../../property_management/domain/occupancy.dart';
import '../../property_management/domain/room.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/rent_providers.dart';
import '../domain/rent_cycle_models.dart';
import '../domain/rent_cycle_service.dart';
import '../domain/rent_models.dart';
import 'rent_formatters.dart';

class RentBillingScreen extends ConsumerWidget {
  const RentBillingScreen({super.key});

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
    final values = <AsyncValue<Object>>[
      ref.watch(rentAgreementsProvider(ownerId)),
      ref.watch(rentCyclesProvider(ownerId)),
      ref.watch(rentCycleControlsProvider(ownerId)),
      ref.watch(rentExtraStayResolutionsProvider(ownerId)),
      ref.watch(rentBillingRecordsProvider(ownerId)),
      ref.watch(roomsProvider(ownerId)),
      ref.watch(boardersProvider(ownerId)),
      ref.watch(allOccupanciesProvider(ownerId)),
    ];
    final error = values.where((value) => value.hasError).firstOrNull?.error;
    final loading = values.any((value) => value.isLoading);
    return Scaffold(
      appBar: AppBar(title: const Text('Rent cycles')),
      body: SafeArea(
        child: error != null
            ? AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Rent data could not be loaded',
                  message: propertyErrorMessage(error),
                  actionLabel: 'Try again',
                  onAction: () => _invalidate(ref, ownerId),
                ),
              )
            : loading
            ? const Center(child: CircularProgressIndicator())
            : _RentDashboard(
                ownerId: ownerId,
                agreements: ref
                    .read(rentAgreementsProvider(ownerId))
                    .requireValue,
                cycles: ref.read(rentCyclesProvider(ownerId)).requireValue,
                controls: ref
                    .read(rentCycleControlsProvider(ownerId))
                    .requireValue,
                resolutions: ref
                    .read(rentExtraStayResolutionsProvider(ownerId))
                    .requireValue,
                legacyRecords: ref
                    .read(rentBillingRecordsProvider(ownerId))
                    .requireValue,
                rooms: ref.read(roomsProvider(ownerId)).requireValue,
                boarders: ref.read(boardersProvider(ownerId)).requireValue,
                occupancies: ref
                    .read(allOccupanciesProvider(ownerId))
                    .requireValue,
              ),
      ),
    );
  }

  static void _invalidate(WidgetRef ref, String ownerId) {
    ref.invalidate(rentAgreementsProvider(ownerId));
    ref.invalidate(rentCyclesProvider(ownerId));
    ref.invalidate(rentCycleControlsProvider(ownerId));
    ref.invalidate(rentExtraStayResolutionsProvider(ownerId));
    ref.invalidate(rentBillingRecordsProvider(ownerId));
    ref.invalidate(roomsProvider(ownerId));
    ref.invalidate(boardersProvider(ownerId));
    ref.invalidate(allOccupanciesProvider(ownerId));
  }
}

class _RentDashboard extends ConsumerStatefulWidget {
  const _RentDashboard({
    required this.ownerId,
    required this.agreements,
    required this.cycles,
    required this.controls,
    required this.resolutions,
    required this.legacyRecords,
    required this.rooms,
    required this.boarders,
    required this.occupancies,
  });

  final String ownerId;
  final List<RentAgreement> agreements;
  final List<RentCycle> cycles;
  final List<RentCycleControl> controls;
  final List<RentExtraStayResolution> resolutions;
  final List<RentBillingRecord> legacyRecords;
  final List<Room> rooms;
  final List<Boarder> boarders;
  final List<Occupancy> occupancies;

  @override
  ConsumerState<_RentDashboard> createState() => _RentDashboardState();
}

class _RentDashboardState extends ConsumerState<_RentDashboard> {
  bool _busy = false;

  void _refresh() => RentBillingScreen._invalidate(ref, widget.ownerId);

  Future<void> _updateDueRent() async {
    setState(() => _busy = true);
    var created = 0;
    try {
      final occupancyById = {
        for (final value in widget.occupancies) value.occupancyId: value,
      };
      final today = BusinessDate.todayInManila();
      for (final agreement in widget.agreements) {
        final moveOut = occupancyById[agreement.occupancyId]?.moveOutDate;
        final through = moveOut != null && moveOut.isBefore(today)
            ? moveOut
            : today;
        created += await ref
            .read(rentRepositoryProvider)
            .createDueCycles(
              ownerId: widget.ownerId,
              agreement: agreement,
              throughDate: through,
            );
      }
      _refresh();
      if (mounted) {
        showPropertyMessage(
          context,
          created == 0
              ? 'Rent schedule is already up to date.'
              : '$created due rent ${created == 1 ? 'cycle' : 'cycles'} added.',
        );
      }
    } catch (error) {
      if (mounted) {
        showPropertyMessage(
          context,
          propertyErrorMessage(error),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agreementOccupancies = widget.agreements
        .map((e) => e.occupancyId)
        .toSet();
    final missing = widget.occupancies
        .where((value) => !agreementOccupancies.contains(value.occupancyId))
        .toList();
    final controls = {
      for (final value in widget.controls) value.cycleId: value,
    };
    final resolutions = widget.resolutions.map((e) => e.occupancyId).toSet();
    final agreements = {
      for (final value in widget.agreements) value.occupancyId: value,
    };
    final pending = widget.occupancies.where((occupancy) {
      final agreement = agreements[occupancy.occupancyId];
      final moveOut = occupancy.moveOutDate;
      if (agreement == null ||
          moveOut == null ||
          resolutions.contains(occupancy.occupancyId)) {
        return false;
      }
      final boundary = const RentCycleService().latestCompletedBoundary(
        agreement,
        throughDate: moveOut,
      );
      return moveOut.isAfter(boundary);
    }).toList();
    final occupancyById = {
      for (final value in widget.occupancies) value.occupancyId: value,
    };
    final storedCycleIds = widget.cycles.map((e) => e.cycleId).toSet();
    final today = BusinessDate.todayInManila();
    final accruing = widget.agreements
        .map((agreement) {
          final occupancy = occupancyById[agreement.occupancyId];
          if (occupancy == null ||
              (occupancy.moveOutDate != null &&
                  !today.isBefore(occupancy.moveOutDate!))) {
            return null;
          }
          final cycle = const RentCycleService().currentCycle(
            agreement,
            onDate: today,
          );
          return storedCycleIds.contains(cycle.cycleId) ? null : cycle;
        })
        .whereType<RentCycle>()
        .toList();

    return ListView(
      children: [
        AdaptivePageBody(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageIntro(
                title: 'Fixed monthly rent',
                subtitle: 'Each boarder owes the full agreed rent after their monthly coverage period ends. Rent stays separate from electricity and water bills.',
                icon: Icons.payments_outlined,
              ),
              const SizedBox(height: 14),
              const _ArrearsNotice(),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    key: const Key('update-due-rent-button'),
                    onPressed: _busy || widget.agreements.isEmpty
                        ? null
                        : _updateDueRent,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: const Text('Update due rent'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('create-rent-agreement-button'),
                    onPressed: missing.isEmpty
                        ? null
                        : () => _showAgreementSheet(missing),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: Text(
                      missing.isEmpty
                          ? 'All agreements set'
                          : 'Set up agreement',
                    ),
                  ),
                ],
              ),
              if (missing.isNotEmpty) ...[
                const SizedBox(height: 12),
                _InfoStrip(
                  icon: Icons.info_outline_rounded,
                  text:
                      '${missing.length} ${missing.length == 1 ? 'occupancy needs' : 'occupancies need'} a fixed-rent agreement.',
                ),
              ],
              if (pending.isNotEmpty) ...[
                const SizedBox(height: 28),
                _SectionTitle(
                  title: 'Move-out decisions',
                  count: pending.length,
                ),
                const SizedBox(height: 6),
                Text(
                  'These boarders stayed beyond the last completed rental boundary. Record a decision; no charge is added automatically.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                ...pending.map((occupancy) {
                  final agreement = agreements[occupancy.occupancyId]!;
                  final boundary = const RentCycleService()
                      .latestCompletedBoundary(
                        agreement,
                        throughDate: occupancy.moveOutDate!,
                      );
                  return _DecisionCard(
                    agreement: agreement,
                    extraStart: boundary,
                    moveOutDate: occupancy.moveOutDate!,
                    onResolve: () =>
                        _showResolutionSheet(agreement, occupancy.moveOutDate!),
                  );
                }),
              ],
              if (accruing.isNotEmpty) ...[
                const SizedBox(height: 28),
                _SectionTitle(
                  title: 'Current coverage',
                  count: accruing.length,
                ),
                const SizedBox(height: 6),
                Text(
                  'These periods are still in progress. Their full rent becomes due on the anniversary date.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                ...accruing.map((cycle) => _AccruingCard(cycle: cycle)),
              ],
              const SizedBox(height: 28),
              _SectionTitle(title: 'Rent cycles', count: widget.cycles.length),
              const SizedBox(height: 6),
              Text(
                'Coverage ends the day before the due date. Partial payments remain visible until the balance reaches zero.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (widget.cycles.isEmpty)
                const PropertyStatePanel(
                  icon: Icons.event_repeat_outlined,
                  title: 'No due rent cycles yet',
                  message: 'Set up an agreement, then update due rent after its first coverage period ends.',
                )
              else
                ...widget.cycles.map((cycle) {
                  final control =
                      controls[cycle.cycleId] ??
                      RentCycleControl(
                        cycleId: cycle.cycleId,
                        totalPaidCentavos: 0,
                        lastPaymentId: null,
                        updatedAt: cycle.createdAt,
                      );
                  return _CycleCard(
                    cycle: cycle,
                    control: control,
                    onPayment: control.totalPaidCentavos < cycle.amountCentavos
                        ? () => _showPaymentSheet(cycle, control)
                        : null,
                  );
                }),
              if (widget.resolutions.isNotEmpty) ...[
                const SizedBox(height: 28),
                _SectionTitle(
                  title: 'Move-out history',
                  count: widget.resolutions.length,
                ),
                const SizedBox(height: 12),
                ...widget.resolutions.map(
                  (value) => _ResolutionCard(value: value),
                ),
              ],
              const SizedBox(height: 28),
              _SectionTitle(
                title: 'Legacy rent archive',
                count: widget.legacyRecords.length,
              ),
              const SizedBox(height: 6),
              Text(
                'Earlier prorated calculations are preserved as read-only accounting records. They are not converted into fixed cycles.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (widget.legacyRecords.isEmpty)
                const Text('No legacy rent records.')
              else
                ...widget.legacyRecords.map(
                  (record) => Card(
                    child: ListTile(
                      minVerticalPadding: 14,
                      title: Text(
                        formatRentPeriod(
                          record.startDate,
                          record.endDateExclusive,
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${formatRentMode(record.mode)} · ${formatPeso(record.grandTotalCentavos)}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push(
                        '/billing/rent/${Uri.encodeComponent(record.rentRecordId)}',
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showAgreementSheet(List<Occupancy> missing) async {
    final result = await showModalBottomSheet<_AgreementInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _AgreementSheet(
        occupancies: missing,
        rooms: widget.rooms,
        boarders: widget.boarders,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(rentRepositoryProvider)
          .createAgreement(
            ownerId: widget.ownerId,
            occupancyId: result.occupancyId,
            monthlyRentCentavos: result.amountCentavos,
          );
      _refresh();
      if (mounted) {
        showPropertyMessage(context, 'Fixed-rent agreement created.');
      }
    } catch (error) {
      if (mounted) {
        showPropertyMessage(
          context,
          propertyErrorMessage(error),
          isError: true,
        );
      }
    }
  }

  Future<void> _showPaymentSheet(
    RentCycle cycle,
    RentCycleControl control,
  ) async {
    final input = await showModalBottomSheet<_PaymentInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PaymentSheet(cycle: cycle, control: control),
    );
    if (input == null || !mounted) return;
    try {
      await ref
          .read(rentRepositoryProvider)
          .recordPayment(
            ownerId: widget.ownerId,
            cycleId: cycle.cycleId,
            expectedPaidCentavos: control.totalPaidCentavos,
            amountCentavos: input.amountCentavos,
            receivedOn: input.receivedOn,
            note: input.note,
          );
      _refresh();
      if (mounted) {
        showPropertyMessage(context, 'Rent payment recorded.');
      }
    } catch (error) {
      if (mounted) {
        showPropertyMessage(
          context,
          propertyErrorMessage(error),
          isError: true,
        );
      }
    }
  }

  Future<void> _showResolutionSheet(
    RentAgreement agreement,
    BusinessDate moveOutDate,
  ) async {
    final input = await showModalBottomSheet<_ResolutionInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ResolutionSheet(agreement: agreement),
    );
    if (input == null || !mounted) return;
    try {
      await ref
          .read(rentRepositoryProvider)
          .resolveExtraStay(
            ownerId: widget.ownerId,
            agreement: agreement,
            moveOutDate: moveOutDate,
            decision: input.decision,
            amountCentavos: input.amountCentavos,
            note: input.note,
          );
      _refresh();
      if (mounted) {
        showPropertyMessage(context, 'Move-out decision recorded.');
      }
    } catch (error) {
      if (mounted) {
        showPropertyMessage(
          context,
          propertyErrorMessage(error),
          isError: true,
        );
      }
    }
  }
}

class _ArrearsNotice extends StatelessWidget {
  const _ArrearsNotice();

  @override
  Widget build(BuildContext context) => _InfoStrip(
    icon: Icons.calendar_month_outlined,
    text: 'Example: June 10–July 9 is due on July 10. A shorter February clamps the date, then the original anniversary day returns in March.',
    emphasized: true,
  );
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({
    required this.icon,
    required this.text,
    this.emphasized = false,
  });
  final IconData icon;
  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: emphasized
            ? colors.tertiaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: emphasized
                ? colors.onTertiaryContainer
                : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: emphasized
                    ? colors.onTertiaryContainer
                    : colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      Badge(label: Text('$count')),
    ],
  );
}

class _CycleCard extends StatelessWidget {
  const _CycleCard({
    required this.cycle,
    required this.control,
    required this.onPayment,
  });
  final RentCycle cycle;
  final RentCycleControl control;
  final VoidCallback? onPayment;

  @override
  Widget build(BuildContext context) {
    final status = control.statusFor(
      cycle,
      today: BusinessDate.todayInManila(),
    );
    final outstanding = control.outstandingFor(cycle);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 8,
              children: [
                Text(
                  '${cycle.boarderName} · ${cycle.roomName}',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Coverage: ${formatRentPeriod(cycle.coverageStart, cycle.coverageEndExclusive)}',
            ),
            const SizedBox(height: 4),
            Text('Due: ${formatBusinessDate(cycle.dueDate)}'),
            const SizedBox(height: 10),
            Text(
              '${formatPeso(control.totalPaidCentavos)} paid of ${formatPeso(cycle.amountCentavos)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (outstanding > 0) ...[
              const SizedBox(height: 4),
              Text('Balance: ${formatPeso(outstanding)}'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onPayment,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Record payment'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccruingCard extends StatelessWidget {
  const _AccruingCard({required this.cycle});
  final RentCycle cycle;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 8,
            children: [
              Text(
                '${cycle.boarderName} · ${cycle.roomName}',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const _StatusChip(status: RentCyclePaymentStatus.accruing),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Coverage: ${formatRentPeriod(cycle.coverageStart, cycle.coverageEndExclusive)}',
          ),
          const SizedBox(height: 4),
          Text(
            'Due ${formatBusinessDate(cycle.dueDate)} · ${formatPeso(cycle.amountCentavos)}',
          ),
        ],
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final RentCyclePaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (status) {
      RentCyclePaymentStatus.accruing => ('Accruing', Icons.schedule_outlined),
      RentCyclePaymentStatus.due => ('Unpaid', Icons.error_outline_rounded),
      RentCyclePaymentStatus.partiallyPaid => (
        'Partially paid',
        Icons.timelapse_rounded,
      ),
      RentCyclePaymentStatus.paid => (
        'Paid',
        Icons.check_circle_outline_rounded,
      ),
    };
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({
    required this.agreement,
    required this.extraStart,
    required this.moveOutDate,
    required this.onResolve,
  });
  final RentAgreement agreement;
  final BusinessDate extraStart;
  final BusinessDate moveOutDate;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${agreement.boarderName} · ${agreement.roomName}',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text('Extra stay: ${formatRentPeriod(extraStart, moveOutDate)}'),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onResolve,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Resolve extra stay'),
          ),
        ],
      ),
    ),
  );
}

class _ResolutionCard extends StatelessWidget {
  const _ResolutionCard({required this.value});
  final RentExtraStayResolution value;

  @override
  Widget build(BuildContext context) {
    final label = switch (value.decision) {
      ExtraStayDecision.waived => 'Waived',
      ExtraStayDecision.manualCharge => 'Manual charge',
      ExtraStayDecision.fullCycle => 'Full cycle charged',
    };
    return Card(
      child: ListTile(
        minVerticalPadding: 14,
        leading: const Icon(Icons.history_rounded),
        title: Text('$label · ${formatPeso(value.amountCentavos)}'),
        subtitle: Text(
          '${formatRentPeriod(value.extraStayStart, value.moveOutDate)}\n${value.note}',
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _AgreementInput {
  const _AgreementInput(this.occupancyId, this.amountCentavos);
  final String occupancyId;
  final int amountCentavos;
}

class _AgreementSheet extends StatefulWidget {
  const _AgreementSheet({
    required this.occupancies,
    required this.rooms,
    required this.boarders,
  });
  final List<Occupancy> occupancies;
  final List<Room> rooms;
  final List<Boarder> boarders;

  @override
  State<_AgreementSheet> createState() => _AgreementSheetState();
}

class _AgreementSheetState extends State<_AgreementSheet> {
  late String _occupancyId = widget.occupancies.first.occupancyId;
  final _amount = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _fillDefault();
  }

  void _fillDefault() {
    final occupancy = widget.occupancies.firstWhere(
      (e) => e.occupancyId == _occupancyId,
    );
    final room = widget.rooms
        .where((e) => e.roomId == occupancy.roomId)
        .firstOrNull;
    _amount.text = centavosToInput(room?.defaultMonthlyRentCentavos);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = parsePesoToCentavos(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter the agreed monthly rent.');
      return;
    }
    Navigator.pop(context, _AgreementInput(_occupancyId, amount));
  }

  @override
  Widget build(BuildContext context) => _SheetFrame(
    title: 'Set up fixed rent',
    children: [
      DropdownButtonFormField<String>(
        initialValue: _occupancyId,
        decoration: const InputDecoration(labelText: 'Occupancy'),
        items: widget.occupancies.map((occupancy) {
          final room = widget.rooms
              .where((e) => e.roomId == occupancy.roomId)
              .firstOrNull;
          final boarder = widget.boarders
              .where((e) => e.boarderId == occupancy.boarderId)
              .firstOrNull;
          return DropdownMenuItem(
            value: occupancy.occupancyId,
            child: Text(
              '${boarder?.fullName ?? 'Boarder'} · ${room?.roomName ?? 'Room'}',
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            _occupancyId = value;
            _error = null;
            _fillDefault();
          });
        },
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(
          labelText: 'Agreed monthly rent',
          prefixText: '₱ ',
          errorText: _error,
          helperText: 'Full amount due after each anniversary period.',
        ),
      ),
      const SizedBox(height: 18),
      FilledButton(onPressed: _submit, child: const Text('Create agreement')),
    ],
  );
}

class _PaymentInput {
  const _PaymentInput(this.amountCentavos, this.receivedOn, this.note);
  final int amountCentavos;
  final BusinessDate receivedOn;
  final String? note;
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.cycle, required this.control});
  final RentCycle cycle;
  final RentCycleControl control;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late final _amount = TextEditingController(
    text: centavosToInput(widget.control.outstandingFor(widget.cycle)),
  );
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = parsePesoToCentavos(_amount.text);
    final outstanding = widget.control.outstandingFor(widget.cycle);
    if (amount == null || amount <= 0 || amount > outstanding) {
      setState(
        () => _error =
            'Enter an amount from ₱0.01 to ${formatPeso(outstanding)}.',
      );
      return;
    }
    Navigator.pop(
      context,
      _PaymentInput(amount, BusinessDate.todayInManila(), _note.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) => _SheetFrame(
    title: 'Record rent payment',
    children: [
      Text(
        '${widget.cycle.boarderName} · ${formatRentPeriod(widget.cycle.coverageStart, widget.cycle.coverageEndExclusive)}',
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Amount received',
          prefixText: '₱ ',
          errorText: _error,
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _note,
        maxLength: 500,
        decoration: const InputDecoration(labelText: 'Note (optional)'),
      ),
      const SizedBox(height: 10),
      FilledButton(onPressed: _submit, child: const Text('Save payment')),
    ],
  );
}

class _ResolutionInput {
  const _ResolutionInput(this.decision, this.amountCentavos, this.note);
  final ExtraStayDecision decision;
  final int amountCentavos;
  final String note;
}

class _ResolutionSheet extends StatefulWidget {
  const _ResolutionSheet({required this.agreement});
  final RentAgreement agreement;

  @override
  State<_ResolutionSheet> createState() => _ResolutionSheetState();
}

class _ResolutionSheetState extends State<_ResolutionSheet> {
  ExtraStayDecision _decision = ExtraStayDecision.waived;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final note = _note.text.trim();
    final amount = _decision == ExtraStayDecision.manualCharge
        ? parsePesoToCentavos(_amount.text)
        : _decision == ExtraStayDecision.fullCycle
        ? widget.agreement.monthlyRentCentavos
        : 0;
    if (note.length < 3 ||
        amount == null ||
        amount < 0 ||
        (_decision == ExtraStayDecision.manualCharge && amount == 0)) {
      setState(
        () => _error =
            'Choose a valid amount and enter a note of at least 3 characters.',
      );
      return;
    }
    Navigator.pop(context, _ResolutionInput(_decision, amount, note));
  }

  @override
  Widget build(BuildContext context) => _SheetFrame(
    title: 'Resolve extra stay',
    children: [
      const Text('No charge is added until you record one of these decisions.'),
      const SizedBox(height: 12),
      SegmentedButton<ExtraStayDecision>(
        segments: const [
          ButtonSegment(
            value: ExtraStayDecision.waived,
            icon: Icon(Icons.volunteer_activism_outlined),
            label: Text('Waive'),
          ),
          ButtonSegment(
            value: ExtraStayDecision.manualCharge,
            icon: Icon(Icons.edit_note_rounded),
            label: Text('Manual'),
          ),
          ButtonSegment(
            value: ExtraStayDecision.fullCycle,
            icon: Icon(Icons.event_repeat_outlined),
            label: Text('Full cycle'),
          ),
        ],
        selected: {_decision},
        showSelectedIcon: false,
        onSelectionChanged: (values) => setState(() {
          _decision = values.single;
          _error = null;
        }),
      ),
      const SizedBox(height: 8),
      Text(switch (_decision) {
        ExtraStayDecision.waived => 'No extra charge will be added.',
        ExtraStayDecision.manualCharge =>
          'Enter the amount you decided to charge.',
        ExtraStayDecision.fullCycle =>
          'Charge ${formatPeso(widget.agreement.monthlyRentCentavos)} for the next full cycle.',
      }),
      if (_decision == ExtraStayDecision.manualCharge) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Manual charge',
            prefixText: '₱ ',
          ),
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _note,
        minLines: 2,
        maxLines: 4,
        maxLength: 500,
        decoration: InputDecoration(
          labelText: 'Required decision note',
          helperText: 'Example: Allowed five extra days without charge.',
          errorText: _error,
        ),
      ),
      const SizedBox(height: 10),
      FilledButton(onPressed: _submit, child: const Text('Record decision')),
    ],
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );
}
