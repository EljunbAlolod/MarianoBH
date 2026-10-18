import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/application/auth_providers.dart';
import '../../property_management/presentation/widgets/property_formatters.dart';
import '../../property_management/presentation/widgets/property_ui.dart';
import '../application/rent_providers.dart';
import '../domain/rent_models.dart';
import 'rent_formatters.dart';

class RentRecordDetailScreen extends ConsumerWidget {
  const RentRecordDetailScreen({required this.recordId, super.key});

  final String recordId;

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
    final records = ref.watch(rentBillingRecordsProvider(ownerId));
    return records.when(
      loading: () => const Scaffold(
        appBar: _RecordAppBar(),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: const _RecordAppBar(),
        body: AdaptivePageBody(
          child: PropertyStatePanel(
            icon: Icons.cloud_off_outlined,
            title: 'Rent record could not be loaded',
            message: propertyErrorMessage(error),
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(rentBillingRecordsProvider(ownerId)),
          ),
        ),
      ),
      data: (items) {
        final record = items
            .where((item) => item.rentRecordId == recordId)
            .firstOrNull;
        if (record == null) {
          return const Scaffold(
            appBar: _RecordAppBar(),
            body: AdaptivePageBody(
              child: PropertyStatePanel(
                icon: Icons.receipt_long_outlined,
                title: 'Rent record not found',
                message: 'This record is unavailable or does not belong to this boarding house.',
              ),
            ),
          );
        }
        return _RecordDetails(record: record);
      },
    );
  }
}

class _RecordAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _RecordAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) =>
      AppBar(title: const Text('Rent record'));
}

class _RecordDetails extends StatelessWidget {
  const _RecordDetails({required this.record});
  final RentBillingRecord record;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const _RecordAppBar(),
      body: SafeArea(
        child: ListView(
          children: [
            AdaptivePageBody(
              maxWidth: 900,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StatusPill(
                            label: 'Read-only historical record',
                            icon: Icons.lock_outline_rounded,
                            background: colors.primaryContainer,
                            foreground: colors.onPrimaryContainer,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            formatRentPeriod(
                              record.startDate,
                              record.endDateExclusive,
                            ),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Saved ${_timestamp(record.recordedAt)}. Later changes to rooms or occupancies do not alter this snapshot.',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Summary(record: record),
                  if (record.warnings.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _Heading('Calculation notes'),
                    const SizedBox(height: 10),
                    ...record.warnings.map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _Notice(warning),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _Heading('Boarder charges'),
                  const SizedBox(height: 10),
                  if (record.boarderCharges.isEmpty)
                    const PropertyStatePanel(
                      icon: Icons.people_outline_rounded,
                      title: 'No boarder charges',
                      message: 'This record contains no occupied boarders.',
                    )
                  else
                    ...record.boarderCharges.map((item) => _BoarderCard(item)),
                  if (record.roomAllocations.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _Heading('Room breakdown'),
                    const SizedBox(height: 10),
                    ...record.roomAllocations.map((item) => _RoomCard(item)),
                  ],
                  if (record.adjustments.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _Heading('Adjustments'),
                    const SizedBox(height: 10),
                    ...record.adjustments.map((item) {
                      final boarder = record.boarderCharges
                          .where((charge) => charge.boarderId == item.boarderId)
                          .firstOrNull;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.reason,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${boarder?.boarderName ?? 'Boarder'} - ${formatBusinessDate(item.adjustmentDate)}',
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  _signedPeso(item.signedCentavos),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color:
                                        item.type ==
                                            BillingAdjustmentType.credit
                                        ? colors.primary
                                        : colors.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.record});
  final RentBillingRecord record;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _ValueRow(label: 'Policy', value: formatRentMode(record.mode)),
            _ValueRow(label: 'Billable days', value: '${record.periodDays}'),
            _ValueRow(
              label: 'Rent',
              value: formatPeso(record.totalRentCentavos),
            ),
            _ValueRow(
              label: 'Adjustments',
              value: _signedPeso(record.totalAdjustmentCentavos),
            ),
            const Divider(height: 24),
            _ValueRow(
              label: 'Total',
              value: formatPeso(record.grandTotalCentavos),
              emphasized: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _BoarderCard extends StatelessWidget {
  const _BoarderCard(this.item);
  final BoarderRentCharge item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item.boarderName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${item.occupancyDays} occupancy ${item.occupancyDays == 1 ? 'day' : 'days'} across ${item.roomIds.length} ${item.roomIds.length == 1 ? 'room' : 'rooms'}',
            ),
            const SizedBox(height: 8),
            _ValueRow(label: 'Rent', value: formatPeso(item.rentCentavos)),
            if (item.adjustmentCentavos != 0)
              _ValueRow(
                label: 'Adjustments',
                value: _signedPeso(item.adjustmentCentavos),
              ),
            _ValueRow(
              label: 'Total',
              value: formatPeso(item.totalCentavos),
              emphasized: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard(this.item);
  final RoomRentAllocation item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item.roomName,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _ValueRow(
              label: 'Monthly rate',
              value: formatPeso(item.monthlyRentCentavos),
            ),
            _ValueRow(label: 'Occupied days', value: '${item.occupiedDays}'),
            _ValueRow(label: 'Person-days', value: '${item.personDays}'),
            _ValueRow(
              label: 'Room rent',
              value: formatPeso(item.rentCentavos),
              emphasized: true,
            ),
            if (item.boarderShares.isNotEmpty) ...[
              const Divider(height: 24),
              ...item.boarderShares.map(
                (share) => _ValueRow(
                  label:
                      '${share.boarderName} - ${share.occupancyDays} ${share.occupancyDays == 1 ? 'day' : 'days'}',
                  value: formatPeso(share.rentCentavos),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.w700),
  );
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
  const _Notice(this.message);
  final String message;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
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
    );
  }
}

String _signedPeso(int centavos) {
  if (centavos == 0) return formatPeso(0);
  return '${centavos > 0 ? '+' : '-'}${formatPeso(centavos.abs())}';
}

String _timestamp(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour == 0
      ? 12
      : local.hour > 12
      ? local.hour - 12
      : local.hour;
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}/${local.day}/${local.year} at $hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}';
}
