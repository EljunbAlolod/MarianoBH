import 'package:flutter/material.dart';

import '../../property_management/presentation/widgets/property_formatters.dart';
import '../domain/water_selection.dart';
import '../domain/water_models.dart';
import '../../../shared/widgets/app_components.dart';

class WaterSelectionPanel extends StatelessWidget {
  const WaterSelectionPanel({
    super.key,
    required this.decisions,
    this.onChanged,
    this.preview,
    this.validationMessage,
  });
  final List<WaterBoarderDecision> decisions;
  final ValueChanged<WaterBoarderDecision>? onChanged;
  final WaterCalculationResult? preview;
  final String? validationMessage;

  @override
  Widget build(BuildContext context) {
    final included = decisions
        .where((d) => d.inclusion == WaterInclusion.included)
        .length;
    final excluded = decisions
        .where((d) => d.inclusion == WaterInclusion.excluded)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: const Icon(Icons.check_circle_outline, size: 18),
              label: Text('Included: $included'),
            ),
            Chip(
              avatar: const Icon(Icons.remove_circle_outline, size: 18),
              label: Text('Excluded: $excluded'),
            ),
            Chip(
              avatar: const Icon(Icons.pending_outlined, size: 18),
              label: Text(
                'Needs review: ${decisions.length - included - excluded}',
              ),
            ),
          ],
        ),
        if (preview != null) ...[
          const SizedBox(height: 12),
          Text(
            'Total water allocated',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          FinancialAmount(preview!.totalAllocatedCentavos),
          const SizedBox(height: 8),
        ],
        const Text(
          'Equal shares per included boarder. Occupied days are information only, never a charge multiplier.',
        ),
        if (decisions.isEmpty)
          const Text('No boarders overlap these statement dates.'),
        for (final d in decisions)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    d.boarderName,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    d.occupancies.map((o) => o.roomName).toSet().join(' → '),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${d.fullPeriod ? "Full-period occupant" : "Partial-period occupant — review required"} · ${d.occupiedDays} occupied days${d.transferred ? " · Transferred" : ""}',
                  ),
                  ExpansionTile(
                    key: PageStorageKey('water-evidence-${d.boarderId}'),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 12),
                    initiallyExpanded: !d.fullPeriod || d.transferred,
                    title: const Text('Occupancy details'),
                    children: [
                      for (final o in d.occupancies)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${o.roomName}: move-in ${o.moveIn} · move-out ${o.moveOut ?? "Still assigned"}\n${o.overlapStart} to ${o.overlapEnd} (end exclusive): ${o.days} days',
                          ),
                        ),
                    ],
                  ),
                  if (onChanged != null) ...[
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          key: ValueKey('include-${d.boarderId}'),
                          label: const Text('Include'),
                          tooltip:
                              'Include ${d.boarderName} in equal water sharing',
                          selected: d.inclusion == WaterInclusion.included,
                          onSelected: (_) => onChanged!(
                            d.decide(inclusion: WaterInclusion.included),
                          ),
                        ),
                        ChoiceChip(
                          key: ValueKey('exclude-${d.boarderId}'),
                          label: const Text('Exclude'),
                          tooltip:
                              'Exclude ${d.boarderName}; a reason is required',
                          selected: d.inclusion == WaterInclusion.excluded,
                          onSelected: (_) => onChanged!(
                            d.decide(inclusion: WaterInclusion.excluded),
                          ),
                        ),
                      ],
                    ),
                    if (d.inclusion == WaterInclusion.excluded)
                      TextFormField(
                        key: ValueKey('exclude-reason-${d.boarderId}'),
                        initialValue: d.exclusionReason,
                        decoration: const InputDecoration(
                          labelText: 'Exclusion reason (required)',
                        ),
                        maxLength: 500,
                        onChanged: (value) =>
                            onChanged!(d.decide(exclusionReason: value)),
                      ),
                    if (d.inclusion == WaterInclusion.included &&
                        d.transferred) ...[
                      DropdownButtonFormField<String>(
                        key: ValueKey('billing-room-${d.boarderId}'),
                        initialValue: d.billingRoomId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Assign whole share to room (required)',
                        ),
                        items: d.roomIds
                            .map(
                              (id) => DropdownMenuItem(
                                value: id,
                                child: Text(
                                  d.occupancies
                                      .firstWhere((o) => o.roomId == id)
                                      .roomName,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            onChanged!(d.decide(billingRoomId: value)),
                      ),
                      TextFormField(
                        key: ValueKey('room-reason-${d.boarderId}'),
                        initialValue: d.roomReason,
                        decoration: const InputDecoration(
                          labelText: 'Room allocation explanation (required)',
                        ),
                        maxLength: 500,
                        onChanged: (value) =>
                            onChanged!(d.decide(roomReason: value)),
                      ),
                    ],
                  ] else ...[
                    Text('Decision: ${d.inclusion.name}'),
                    if (d.inclusion == WaterInclusion.excluded)
                      Text('Reason: ${d.exclusionReason}'),
                    if (d.inclusion == WaterInclusion.included &&
                        d.billingRoomId != null)
                      Text(
                        'Billing room: ${d.occupancies.firstWhere((o) => o.roomId == d.billingRoomId).roomName}',
                      ),
                    if (d.transferred && d.inclusion == WaterInclusion.included)
                      Text('Room decision: ${d.roomReason}'),
                  ],
                  if (preview != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Share: ${formatPeso(preview!.boarderShares.where((s) => s.boarderId == d.boarderId).firstOrNull?.amountCentavos ?? 0)}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (validationMessage != null)
          Semantics(
            liveRegion: true,
            child: Text(
              validationMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (preview != null) ...[
          const Text(
            'Live room totals',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          for (final room in preview!.roomAllocations)
            Text('${room.roomName}: ${formatPeso(room.roomChargeCentavos)}'),
          const Text(
            'Any remainder centavos go to included boarders in ascending boarder-ID order.',
          ),
        ],
      ],
    );
  }
}
