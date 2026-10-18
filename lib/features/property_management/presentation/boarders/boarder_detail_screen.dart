import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../authentication/application/auth_providers.dart';
import '../../application/property_providers.dart';
import '../../domain/boarder.dart';
import '../../domain/business_date.dart';
import '../../domain/occupancy.dart';
import '../../domain/room.dart';
import '../widgets/property_formatters.dart';
import '../widgets/property_ui.dart';
import 'boarder_forms.dart';
import '../../../../shared/widgets/app_components.dart';

class BoarderDetailScreen extends ConsumerWidget {
  const BoarderDetailScreen({required this.boarderId, super.key});

  final String boarderId;

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
    final boarders = ref.watch(boardersProvider(ownerId));
    final rooms = ref.watch(roomsProvider(ownerId));

    return boarders.when(
      loading: () => const Scaffold(
        appBar: _DetailLoadingAppBar(),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Boarder details')),
        body: AdaptivePageBody(
          child: PropertyStatePanel(
            icon: Icons.cloud_off_outlined,
            title: 'Boarder could not be loaded',
            message: propertyErrorMessage(error),
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(boardersProvider(ownerId)),
          ),
        ),
      ),
      data: (items) {
        final boarder = _findBoarder(items, boarderId);
        if (boarder == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Boarder details')),
            body: const AdaptivePageBody(
              child: PropertyStatePanel(
                icon: Icons.person_off_outlined,
                title: 'Boarder not found',
                message: 'This record is unavailable or does not belong to this boarding house.',
              ),
            ),
          );
        }
        final roomItems = rooms.asData?.value ?? const <Room>[];
        return _BoarderDetails(
          ownerId: ownerId,
          boarder: boarder,
          rooms: roomItems,
          roomsHaveError: rooms.hasError,
        );
      },
    );
  }
}

class _DetailLoadingAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _DetailLoadingAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(title: const Text('Boarder details'));
  }
}

class _BoarderDetails extends ConsumerWidget {
  const _BoarderDetails({
    required this.ownerId,
    required this.boarder,
    required this.rooms,
    required this.roomsHaveError,
  });

  final String ownerId;
  final Boarder boarder;
  final List<Room> rooms;
  final bool roomsHaveError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomById = {for (final room in rooms) room.roomId: room};
    final currentRoom = boarder.currentRoomId == null
        ? null
        : roomById[boarder.currentRoomId];
    final occupancies = ref.watch(
      occupanciesProvider(
        OccupanciesQuery(ownerId: ownerId, boarderId: boarder.boarderId),
      ),
    );
    final activeRooms = rooms
        .where((room) => room.isActive)
        .toList(growable: false);
    final transferRooms = activeRooms
        .where((room) => room.roomId != boarder.currentRoomId)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Boarder details'),
        actions: [
          IconButton(
            tooltip: 'Edit boarder details',
            onPressed: () => _editBoarder(context, boarder, activeRooms),
            icon: const Icon(Icons.edit_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(boardersProvider(ownerId));
            ref.invalidate(roomsProvider(ownerId));
            ref.invalidate(
              occupanciesProvider(
                OccupanciesQuery(
                  ownerId: ownerId,
                  boarderId: boarder.boarderId,
                ),
              ),
            );
            await ref.read(boardersProvider(ownerId).future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              AdaptivePageBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _IdentityCard(boarder: boarder, currentRoom: currentRoom),
                    const SizedBox(height: 16),
                    if (roomsHaveError)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          'Room names are temporarily unavailable. Pull to refresh.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SectionHeader(
                      'Manage occupancy',
                      subtitle: 'Record a transfer, move-in or move-out.',
                    ),
                    _ActionPanel(
                      boarder: boarder,
                      canTransfer: transferRooms.isNotEmpty,
                      canMoveIn: activeRooms.isNotEmpty,
                      onTransfer: () => _openOccupancyAction(
                        context,
                        boarder,
                        transferRooms,
                        OccupancyAction.transfer,
                      ),
                      onMoveOut: () => _moveOut(context, ref, boarder),
                      onMoveIn: () => _openOccupancyAction(
                        context,
                        boarder,
                        activeRooms,
                        OccupancyAction.moveIn,
                      ),
                      onDeactivate: () => _deactivate(context, ref, boarder),
                    ),
                    const SectionHeader(
                      'Occupancy history',
                      subtitle: 'Move-in is billable. Move-out is the first non-billable date.',
                    ),
                    occupancies.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (error, _) => PropertyStatePanel(
                        icon: Icons.history_toggle_off_outlined,
                        title: 'History could not be loaded',
                        message: propertyErrorMessage(error),
                        actionLabel: 'Try again',
                        onAction: () => ref.invalidate(
                          occupanciesProvider(
                            OccupanciesQuery(
                              ownerId: ownerId,
                              boarderId: boarder.boarderId,
                            ),
                          ),
                        ),
                      ),
                      data: (items) => _OccupancyHistory(
                        occupancies: items,
                        roomsById: roomById,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editBoarder(
    BuildContext context,
    Boarder boarder,
    List<Room> activeRooms,
  ) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => BoarderFormSheet(
        ownerId: ownerId,
        boarder: boarder,
        activeRooms: activeRooms,
      ),
    );
    if (result != null && context.mounted) {
      showPropertyMessage(context, 'Boarder details updated.');
    }
  }

  Future<void> _openOccupancyAction(
    BuildContext context,
    Boarder boarder,
    List<Room> availableRooms,
    OccupancyAction action,
  ) async {
    if (availableRooms.isEmpty) {
      showPropertyMessage(
        context,
        action == OccupancyAction.transfer
            ? 'Add or reactivate another room before transferring.'
            : 'Add or reactivate a room before moving this boarder in.',
        isError: true,
      );
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => OccupancyActionSheet(
        ownerId: ownerId,
        boarder: boarder,
        availableRooms: availableRooms,
        action: action,
      ),
    );
    if (saved == true && context.mounted) {
      showPropertyMessage(
        context,
        action == OccupancyAction.transfer
            ? 'Transfer recorded.'
            : 'Move-in recorded.',
      );
    }
  }

  Future<void> _moveOut(
    BuildContext context,
    WidgetRef ref,
    Boarder boarder,
  ) async {
    final moveIn = boarder.currentMoveInDate;
    if (moveIn == null) return;
    final first = _nextBusinessDate(moveIn);
    final today = BusinessDate.todayInManila();
    if (first.isAfter(today)) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.event_busy_outlined),
          title: const Text('Move-out is not available yet'),
          content: const Text(
            'A boarder must have at least one billable day. Try again tomorrow.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      return;
    }
    final selected = await showDatePicker(
      context: context,
      helpText: 'Select first non-billable date',
      initialDate: today.value,
      firstDate: first.value,
      lastDate: today.value,
    );
    if (selected == null || !context.mounted) return;
    final date = BusinessDate.fromDateTime(selected);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.logout_rounded),
        title: const Text('Record move-out?'),
        content: Text(
          '${formatBusinessDate(date)} will be the first non-billable day. The occupancy record will remain in history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Record move-out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(propertyRepositoryProvider)
          .moveOut(
            ownerId: ownerId,
            boarderId: boarder.boarderId,
            moveOutDate: date,
          );
      if (context.mounted) showPropertyMessage(context, 'Move-out recorded.');
    } catch (error) {
      if (context.mounted) {
        showPropertyMessage(
          context,
          propertyErrorMessage(error),
          isError: true,
        );
      }
    }
  }

  Future<void> _deactivate(
    BuildContext context,
    WidgetRef ref,
    Boarder boarder,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.person_off_outlined),
        title: const Text('Deactivate boarder?'),
        content: const Text(
          'This hides the record from current operations. Occupancy and future financial history are never deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(propertyRepositoryProvider)
          .deactivateBoarder(ownerId: ownerId, boarderId: boarder.boarderId);
      if (context.mounted) showPropertyMessage(context, 'Boarder deactivated.');
    } catch (error) {
      if (context.mounted) {
        showPropertyMessage(
          context,
          propertyErrorMessage(error),
          isError: true,
        );
      }
    }
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.boarder, required this.currentRoom});

  final Boarder boarder;
  final Room? currentRoom;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (
      statusLabel,
      statusIcon,
      background,
      foreground,
    ) = switch (boarder.status) {
      BoarderStatus.active => (
        'Current boarder',
        Icons.check_circle_outline_rounded,
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      BoarderStatus.movedOut => (
        'Moved out',
        Icons.logout_rounded,
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      BoarderStatus.inactive => (
        'Inactive record',
        Icons.pause_circle_outline_rounded,
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: colors.secondaryContainer,
                  foregroundColor: colors.onSecondaryContainer,
                  child: Text(
                    boarder.fullName[0].toUpperCase(),
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        boarder.fullName,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      StatusPill(
                        label: statusLabel,
                        icon: statusIcon,
                        background: background,
                        foreground: foreground,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _DetailRow(
              icon: Icons.meeting_room_outlined,
              label: boarder.status == BoarderStatus.active
                  ? currentRoom?.roomName ?? 'Assigned room unavailable'
                  : 'No current room',
            ),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.contact_phone_outlined,
              label: boarder.contact ?? 'No contact added',
            ),
            if (boarder.notes case final notes?) ...[
              const SizedBox(height: 10),
              _DetailRow(icon: Icons.notes_outlined, label: notes),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 20, color: color)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.boarder,
    required this.canTransfer,
    required this.canMoveIn,
    required this.onTransfer,
    required this.onMoveOut,
    required this.onMoveIn,
    required this.onDeactivate,
  });

  final Boarder boarder;
  final bool canTransfer;
  final bool canMoveIn;
  final VoidCallback onTransfer;
  final VoidCallback onMoveOut;
  final VoidCallback onMoveIn;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Actions',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (boarder.status == BoarderStatus.active) ...[
              FilledButton.tonalIcon(
                onPressed: canTransfer ? onTransfer : null,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: Text(
                  canTransfer ? 'Transfer room' : 'No other active room',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onMoveOut,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Record move-out'),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: canMoveIn ? onMoveIn : null,
                icon: const Icon(Icons.login_rounded),
                label: Text(
                  canMoveIn ? 'Move in again' : 'No active room available',
                ),
              ),
              if (boarder.status == BoarderStatus.movedOut) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onDeactivate,
                  icon: const Icon(Icons.person_off_outlined),
                  label: const Text('Deactivate record'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _OccupancyHistory extends StatelessWidget {
  const _OccupancyHistory({required this.occupancies, required this.roomsById});

  final List<Occupancy> occupancies;
  final Map<String, Room> roomsById;

  @override
  Widget build(BuildContext context) {
    if (occupancies.isEmpty) {
      return const PropertyStatePanel(
        icon: Icons.history_outlined,
        title: 'No occupancy history',
        message: 'Assignments will appear here after the first move-in.',
      );
    }
    return Card(
      child: Column(
        children: [
          for (var index = 0; index < occupancies.length; index++) ...[
            _OccupancyTile(
              occupancy: occupancies[index],
              roomName:
                  roomsById[occupancies[index].roomId]?.roomName ??
                  'Unavailable room',
            ),
            if (index != occupancies.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _OccupancyTile extends StatelessWidget {
  const _OccupancyTile({required this.occupancy, required this.roomName});

  final Occupancy occupancy;
  final String roomName;

  @override
  Widget build(BuildContext context) {
    final end = occupancy.moveOutDate;
    return ListTile(
      leading: Icon(
        occupancy.isCurrent ? Icons.home_rounded : Icons.history_rounded,
      ),
      title: Text(roomName),
      subtitle: Text(
        end == null
            ? '${formatBusinessDate(occupancy.moveInDate)} – Current'
            : '${formatBusinessDate(occupancy.moveInDate)} – ${formatBusinessDate(end)}',
      ),
      trailing: occupancy.isCurrent
          ? const Icon(Icons.check_circle_rounded)
          : null,
    );
  }
}

Boarder? _findBoarder(List<Boarder> items, String boarderId) {
  for (final boarder in items) {
    if (boarder.boarderId == boarderId) return boarder;
  }
  return null;
}

BusinessDate _nextBusinessDate(BusinessDate date) {
  return BusinessDate.fromUtcDateTime(
    date.asUtcDateTime.add(const Duration(days: 1)),
  );
}
