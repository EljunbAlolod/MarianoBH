import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../authentication/application/auth_providers.dart';
import '../../application/property_providers.dart';
import '../../domain/boarder.dart';
import '../../domain/room.dart';
import '../widgets/property_ui.dart';
import 'boarder_forms.dart';
import '../../../../shared/widgets/app_components.dart';

enum _BoarderFilter { all, current, movedOut, inactive }

class BoardersScreen extends ConsumerStatefulWidget {
  const BoardersScreen({super.key});

  @override
  ConsumerState<BoardersScreen> createState() => _BoardersScreenState();
}

class _BoardersScreenState extends ConsumerState<BoardersScreen> {
  _BoarderFilter _filter = _BoarderFilter.all;
  String _query = '';

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
    final boarders = ref.watch(boardersProvider(ownerId));
    final rooms = ref.watch(roomsProvider(ownerId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Boarders'),
        actions: [
          IconButton(
            tooltip: 'Refresh boarders',
            onPressed: () {
              ref.invalidate(boardersProvider(ownerId));
              ref.invalidate(roomsProvider(ownerId));
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-boarder',
        onPressed: () => _addBoarder(context, ownerId, rooms),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add boarder'),
      ),
      body: SafeArea(
        child: boarders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AdaptivePageBody(
            child: PropertyStatePanel(
              icon: Icons.cloud_off_outlined,
              title: 'Boarders could not be loaded',
              message: propertyErrorMessage(error),
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(boardersProvider(ownerId)),
            ),
          ),
          data: (items) {
            final roomItems = rooms.asData?.value ?? const <Room>[];
            final roomsById = {for (final room in roomItems) room.roomId: room};
            final visible =
                items
                    .where(
                      (b) =>
                          _matchesFilter(b) &&
                          ('${b.fullName} ${roomsById[b.currentRoomId]?.roomName ?? ''}')
                              .toLowerCase()
                              .contains(_query),
                    )
                    .toList()
                  ..sort(_compareBoarders);
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(boardersProvider(ownerId));
                ref.invalidate(roomsProvider(ownerId));
                await ref.read(boardersProvider(ownerId).future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  AdaptivePageBody(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const PageIntro(
                          title: 'People behind every room',
                          subtitle: 'Find a boarder, manage assignments and review their history.',
                          icon: Icons.people_outline_rounded,
                        ),
                        const SizedBox(height: 24),
                        RecordSearchField(
                          key: const Key('boarder-search'),
                          label: 'Search name or room',
                          onChanged: (value) => setState(
                            () => _query = value.trim().toLowerCase(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Manage contact details, current room assignments, transfers, and move-out history.',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _FilterChips(
                          selected: _filter,
                          counts: {
                            _BoarderFilter.all: items.length,
                            _BoarderFilter.current: items
                                .where(
                                  (item) => item.status == BoarderStatus.active,
                                )
                                .length,
                            _BoarderFilter.movedOut: items
                                .where(
                                  (item) =>
                                      item.status == BoarderStatus.movedOut,
                                )
                                .length,
                            _BoarderFilter.inactive: items
                                .where(
                                  (item) =>
                                      item.status == BoarderStatus.inactive,
                                )
                                .length,
                          },
                          onSelected: (value) =>
                              setState(() => _filter = value),
                        ),
                        if (rooms.hasError) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Room names are temporarily unavailable. Pull to refresh.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (items.isEmpty)
                          PropertyStatePanel(
                            icon: Icons.people_outline_rounded,
                            title: 'No boarders yet',
                            message: 'Add a boarder and choose their first room and move-in date.',
                            actionLabel: 'Add a boarder',
                            onAction: () =>
                                _addBoarder(context, ownerId, rooms),
                          )
                        else if (visible.isEmpty)
                          const PropertyStatePanel(
                            icon: Icons.filter_alt_off_outlined,
                            title: 'No matching boarders',
                            message:
                                'Try another name, room, or status filter.',
                          )
                        else
                          ...visible.map(
                            (boarder) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _BoarderCard(
                                boarder: boarder,
                                room: boarder.currentRoomId == null
                                    ? null
                                    : roomsById[boarder.currentRoomId],
                                onTap: () => context.push(
                                  '/boarders/${boarder.boarderId}',
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  bool _matchesFilter(Boarder boarder) {
    return switch (_filter) {
      _BoarderFilter.all => true,
      _BoarderFilter.current => boarder.status == BoarderStatus.active,
      _BoarderFilter.movedOut => boarder.status == BoarderStatus.movedOut,
      _BoarderFilter.inactive => boarder.status == BoarderStatus.inactive,
    };
  }

  int _compareBoarders(Boarder first, Boarder second) {
    int rank(BoarderStatus status) => switch (status) {
      BoarderStatus.active => 0,
      BoarderStatus.movedOut => 1,
      BoarderStatus.inactive => 2,
    };
    final status = rank(first.status).compareTo(rank(second.status));
    if (status != 0) return status;
    return first.fullName.toLowerCase().compareTo(
      second.fullName.toLowerCase(),
    );
  }

  Future<void> _addBoarder(
    BuildContext context,
    String ownerId,
    AsyncValue<List<Room>> rooms,
  ) async {
    final activeRooms =
        rooms.asData?.value
            .where((room) => room.status == RoomStatus.active)
            .toList() ??
        const <Room>[];
    if (activeRooms.isEmpty) {
      final goToRooms = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.meeting_room_outlined),
          title: const Text('Add an active room first'),
          content: const Text(
            'Every new boarder needs a room assignment and move-in date.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Go to rooms'),
            ),
          ],
        ),
      );
      if (goToRooms == true && context.mounted) context.go('/rooms');
      return;
    }

    final boarderId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          BoarderFormSheet(ownerId: ownerId, activeRooms: activeRooms),
    );
    if (boarderId != null && context.mounted) {
      showPropertyMessage(context, 'Boarder added and assigned to a room.');
      context.go('/boarders/$boarderId');
    }
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final _BoarderFilter selected;
  final Map<_BoarderFilter, int> counts;
  final ValueChanged<_BoarderFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = {
      _BoarderFilter.all: 'All',
      _BoarderFilter.current: 'Current',
      _BoarderFilter.movedOut: 'Moved out',
      _BoarderFilter.inactive: 'Inactive',
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _BoarderFilter.values
          .map(
            (filter) => ChoiceChip(
              label: Text('${labels[filter]} (${counts[filter] ?? 0})'),
              selected: selected == filter,
              onSelected: (_) => onSelected(filter),
            ),
          )
          .toList(),
    );
  }
}

class _BoarderCard extends StatelessWidget {
  const _BoarderCard({
    required this.boarder,
    required this.room,
    required this.onTap,
  });

  final Boarder boarder;
  final Room? room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (label, icon, background, foreground) = switch (boarder.status) {
      BoarderStatus.active => (
        'Current',
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
        'Inactive',
        Icons.pause_circle_outline_rounded,
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: colors.secondaryContainer,
                foregroundColor: colors.onSecondaryContainer,
                child: Text(
                  boarder.fullName.trim().isEmpty
                      ? '?'
                      : boarder.fullName.trim()[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      boarder.fullName,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    StatusPill(
                      label: label,
                      icon: icon,
                      background: background,
                      foreground: foreground,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      boarder.status == BoarderStatus.active
                          ? room?.roomName ?? 'Assigned room unavailable'
                          : 'No current room',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    if (boarder.contact case final contact?) ...[
                      const SizedBox(height: 4),
                      Text(
                        contact,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
