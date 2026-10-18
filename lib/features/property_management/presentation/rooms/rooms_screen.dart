import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../authentication/application/auth_providers.dart';
import '../../application/property_providers.dart';
import '../../domain/boarder.dart';
import '../../domain/property_repository.dart';
import '../../domain/room.dart';
import '../widgets/property_formatters.dart';
import '../widgets/property_ui.dart';
import '../../../../shared/widgets/app_components.dart';

class RoomsScreen extends ConsumerStatefulWidget {
  const RoomsScreen({super.key});

  @override
  ConsumerState<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends ConsumerState<RoomsScreen> {
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
    final rooms = ref.watch(roomsProvider(ownerId));
    final boarders = ref.watch(boardersProvider(ownerId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rooms'),
        actions: [
          IconButton(
            tooltip: 'Refresh rooms',
            onPressed: () {
              ref.invalidate(roomsProvider(ownerId));
              ref.invalidate(boardersProvider(ownerId));
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-room',
        onPressed: () => _openRoomForm(context, ref, ownerId: ownerId),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add room'),
      ),
      body: SafeArea(
        child: rooms.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AdaptivePageBody(
            child: PropertyStatePanel(
              icon: Icons.cloud_off_outlined,
              title: 'Rooms could not be loaded',
              message: propertyErrorMessage(error),
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(roomsProvider(ownerId)),
            ),
          ),
          data: (roomItems) {
            final sortedRooms =
                roomItems
                    .where((r) => r.roomName.toLowerCase().contains(_query))
                    .toList()
                  ..sort((a, b) {
                    if (a.status != b.status) return a.isActive ? -1 : 1;
                    return a.roomName.toLowerCase().compareTo(
                      b.roomName.toLowerCase(),
                    );
                  });
            final boarderItems = boarders.asData?.value ?? const <Boarder>[];
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(roomsProvider(ownerId));
                ref.invalidate(boardersProvider(ownerId));
                await ref.read(roomsProvider(ownerId).future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  AdaptivePageBody(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const PageIntro(
                          title: 'A place for everyone',
                          subtitle: 'Room availability, monthly rent and current boarders.',
                          icon: Icons.meeting_room_outlined,
                        ),
                        const SizedBox(height: 24),
                        RecordSearchField(
                          key: const Key('room-search'),
                          label: 'Search rooms',
                          onChanged: (value) => setState(
                            () => _query = value.trim().toLowerCase(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'See each room, its default rent, and everyone currently assigned.',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                        if (boarders.hasError) ...[
                          const SizedBox(height: 16),
                          _InlineWarning(
                            message: 'Current boarder names are temporarily unavailable.',
                            onRetry: () =>
                                ref.invalidate(boardersProvider(ownerId)),
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (sortedRooms.isEmpty && roomItems.isNotEmpty)
                          const PropertyStatePanel(
                            icon: Icons.search_off_outlined,
                            title: 'No matching rooms',
                            message: 'Try a different room name or number.',
                          )
                        else if (sortedRooms.isEmpty)
                          PropertyStatePanel(
                            icon: Icons.meeting_room_outlined,
                            title: 'No rooms yet',
                            message: 'Add the first room before registering a boarder.',
                            actionLabel: 'Add a room',
                            onAction: () =>
                                _openRoomForm(context, ref, ownerId: ownerId),
                          )
                        else
                          ...sortedRooms.map((room) {
                            final currentBoarders = boarderItems
                                .where(
                                  (boarder) =>
                                      boarder.status == BoarderStatus.active &&
                                      boarder.currentRoomId == room.roomId,
                                )
                                .toList();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _RoomCard(
                                room: room,
                                currentBoarders: currentBoarders,
                                onEdit: () => _openRoomForm(
                                  context,
                                  ref,
                                  ownerId: ownerId,
                                  room: room,
                                ),
                                onStatusChange: () => _changeRoomStatus(
                                  context,
                                  ref,
                                  ownerId: ownerId,
                                  room: room,
                                ),
                              ),
                            );
                          }),
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

  Future<void> _openRoomForm(
    BuildContext context,
    WidgetRef ref, {
    required String ownerId,
    Room? room,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => RoomFormSheet(ownerId: ownerId, room: room),
    );
    if (saved == true && context.mounted) {
      showPropertyMessage(
        context,
        room == null ? 'Room added.' : 'Room details updated.',
      );
    }
  }

  Future<void> _changeRoomStatus(
    BuildContext context,
    WidgetRef ref, {
    required String ownerId,
    required Room room,
  }) async {
    if (room.isActive && room.activeOccupancyCount > 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.people_outline_rounded),
          title: const Text('Room still has boarders'),
          content: const Text(
            'Transfer or move out every current boarder before deactivating this room.',
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

    final activate = !room.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(activate ? Icons.restore_rounded : Icons.archive_outlined),
        title: Text(activate ? 'Reactivate room?' : 'Deactivate room?'),
        content: Text(
          activate
              ? '${room.roomName} will become available for new assignments.'
              : '${room.roomName} will no longer accept assignments. Its occupancy history will stay available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(activate ? 'Reactivate' : 'Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final repository = ref.read(propertyRepositoryProvider);
      if (activate) {
        await repository.reactivateRoom(ownerId: ownerId, roomId: room.roomId);
      } else {
        await repository.deactivateRoom(ownerId: ownerId, roomId: room.roomId);
      }
      if (context.mounted) {
        showPropertyMessage(
          context,
          activate ? 'Room reactivated.' : 'Room deactivated.',
        );
      }
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

enum _RoomAction { edit, changeStatus }

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.currentBoarders,
    required this.onEdit,
    required this.onStatusChange,
  });

  final Room room;
  final List<Boarder> currentBoarders;
  final VoidCallback onEdit;
  final VoidCallback onStatusChange;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final names = currentBoarders.map((boarder) => boarder.fullName).join(', ');
    final count = room.activeOccupancyCount;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                        ),
                        onPressed: () => context.push('/rooms/${room.roomId}'),
                        child: Text(
                          room.roomName,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (room.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          room.description,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<_RoomAction>(
                  tooltip: 'Room actions for ${room.roomName}',
                  onSelected: (action) {
                    switch (action) {
                      case _RoomAction.edit:
                        onEdit();
                      case _RoomAction.changeStatus:
                        onStatusChange();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: _RoomAction.edit,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit room'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _RoomAction.changeStatus,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          room.isActive
                              ? Icons.archive_outlined
                              : Icons.restore_rounded,
                        ),
                        title: Text(
                          room.isActive ? 'Deactivate' : 'Reactivate',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill(
                  label: room.isActive ? 'Active' : 'Inactive',
                  icon: room.isActive
                      ? Icons.check_circle_outline_rounded
                      : Icons.pause_circle_outline_rounded,
                  background: room.isActive
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  foreground: room.isActive
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
                StatusPill(
                  label: '$count ${count == 1 ? 'boarder' : 'boarders'}',
                  icon: Icons.people_outline_rounded,
                  background: colors.secondaryContainer,
                  foreground: colors.onSecondaryContainer,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _RoomFact(
              icon: Icons.payments_outlined,
              label: room.defaultMonthlyRentCentavos == null
                  ? 'Default rent not set'
                  : '${formatPeso(room.defaultMonthlyRentCentavos)} / month',
            ),
            const SizedBox(height: 10),
            _RoomFact(
              icon: Icons.person_outline_rounded,
              label: names.isEmpty ? 'No current boarders' : names,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomFact extends StatelessWidget {
  const _RoomFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 20, color: color)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}

class _InlineWarning extends StatelessWidget {
  const _InlineWarning({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class RoomFormSheet extends ConsumerStatefulWidget {
  const RoomFormSheet({required this.ownerId, this.room, super.key});

  final String ownerId;
  final Room? room;

  @override
  ConsumerState<RoomFormSheet> createState() => _RoomFormSheetState();
}

class _RoomFormSheetState extends ConsumerState<RoomFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _rentController;
  bool _submitting = false;
  String? _submitError;

  bool get _isEditing => widget.room != null;

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    _nameController = TextEditingController(text: room?.roomName ?? '');
    _descriptionController = TextEditingController(
      text: room?.description ?? '',
    );
    _rentController = TextEditingController(
      text: centavosToInput(room?.defaultMonthlyRentCentavos),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _rentController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final clean = value?.trim() ?? '';
    if (clean.isEmpty) return 'Room name is required.';
    if (clean.length > PropertyValidation.roomNameMaxLength) {
      return 'Use ${PropertyValidation.roomNameMaxLength} characters or fewer.';
    }
    return null;
  }

  String? _validateRent(String? value) {
    try {
      parsePesoToCentavos(value ?? '');
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  Future<void> _submit() async {
    setState(() => _submitError = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final rent = parsePesoToCentavos(_rentController.text);
      final repository = ref.read(propertyRepositoryProvider);
      if (_isEditing) {
        await repository.updateRoom(
          ownerId: widget.ownerId,
          roomId: widget.room!.roomId,
          roomName: _nameController.text,
          description: _descriptionController.text,
          defaultMonthlyRentCentavos: rent,
        );
      } else {
        await repository.createRoom(
          ownerId: widget.ownerId,
          roomName: _nameController.text,
          description: _descriptionController.text,
          defaultMonthlyRentCentavos: rent,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _submitError = propertyErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isEditing ? 'Edit room' : 'Add a room',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: _submitting
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Default rent is stored exactly in Philippine centavos and can be changed later.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: const Key('room-name-field'),
                    controller: _nameController,
                    enabled: !_submitting,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    maxLength: PropertyValidation.roomNameMaxLength,
                    decoration: const InputDecoration(
                      labelText: 'Room name',
                      hintText: 'Example: Room 1A',
                      prefixIcon: Icon(Icons.meeting_room_outlined),
                    ),
                    validator: _validateName,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('room-description-field'),
                    controller: _descriptionController,
                    enabled: !_submitting,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: PropertyValidation.roomDescriptionMaxLength,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      hintText: 'Floor, bed count, or distinguishing details',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('room-rent-field'),
                    controller: _rentController,
                    enabled: !_submitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Default monthly rent (optional)',
                      hintText: '3500.00',
                      prefixText: '₱ ',
                      helperText: 'Use up to two decimal places.',
                    ),
                    validator: _validateRent,
                    onFieldSubmitted: (_) => _submitting ? null : _submit(),
                  ),
                  if (_submitError != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _submitError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('room-save-button'),
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _submitting
                          ? 'Saving…'
                          : _isEditing
                          ? 'Save changes'
                          : 'Add room',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
