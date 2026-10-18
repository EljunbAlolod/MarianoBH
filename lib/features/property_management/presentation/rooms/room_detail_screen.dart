import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/app_components.dart';
import '../../../authentication/application/auth_providers.dart';
import '../../application/property_providers.dart';
import '../../domain/boarder.dart';
import '../widgets/property_ui.dart';
import 'rooms_screen.dart';

class RoomDetailScreen extends ConsumerWidget {
  const RoomDetailScreen({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(appSessionProvider).state.workspace?.ownerUid;
    if (owner == null) {
      return const Scaffold(
        body: Center(child: Text('Owner workspace unavailable')),
      );
    }
    final rooms = ref.watch(roomsProvider(owner));
    final boarders = ref.watch(boardersProvider(owner));
    return Scaffold(
      appBar: AppBar(title: const Text('Room details')),
      body: SafeArea(
        child: rooms.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: [
              AdaptivePageBody(
                child: PropertyStatePanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Room could not be loaded',
                  message: propertyErrorMessage(error),
                  actionLabel: 'Try again',
                  onAction: () => ref.invalidate(roomsProvider(owner)),
                ),
              ),
            ],
          ),
          data: (items) {
            final room = items.where((r) => r.roomId == roomId).firstOrNull;
            if (room == null) {
              return const Center(child: Text('Room not found'));
            }
            return ListView(
              children: [
                AdaptivePageBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PageIntro(
                        title: room.roomName,
                        subtitle: room.description.isEmpty
                            ? 'Room overview and current assignments.'
                            : room.description,
                        eyebrow: room.isActive
                            ? 'ACTIVE ROOM'
                            : 'INACTIVE ROOM',
                        icon: Icons.meeting_room_outlined,
                      ),
                      const SectionHeader('Monthly rent'),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (room.defaultMonthlyRentCentavos != null)
                                FinancialAmount(
                                  room.defaultMonthlyRentCentavos!,
                                )
                              else
                                const Text('Default rent not set'),
                              const SizedBox(height: 8),
                              const Text(
                                'Default monthly amount for this room',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => showModalBottomSheet<bool>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) =>
                              RoomFormSheet(ownerId: owner, room: room),
                        ),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit room'),
                      ),
                      const SectionHeader('Current boarders'),
                      boarders.when(
                        loading: () => const LinearProgressIndicator(
                          semanticsLabel: 'Loading boarders',
                        ),
                        error: (error, _) => PropertyStatePanel(
                          icon: Icons.cloud_off_outlined,
                          title: 'Boarders could not be loaded',
                          message: propertyErrorMessage(error),
                          actionLabel: 'Try again',
                          onAction: () =>
                              ref.invalidate(boardersProvider(owner)),
                        ),
                        data: (people) {
                          final current = people
                              .where(
                                (b) =>
                                    b.currentRoomId == roomId &&
                                    b.status == BoarderStatus.active,
                              )
                              .toList();
                          if (current.isEmpty) {
                            return const PropertyStatePanel(
                              icon: Icons.people_outline,
                              title: 'No current boarders',
                              message:
                                  'Manage assignments from the Boarders tab.',
                            );
                          }
                          return Column(
                            children: [
                              for (final person in current)
                                ActionListItem(
                                  title: person.fullName,
                                  icon: Icons.person_outline,
                                  subtitle:
                                      'View profile and occupancy history',
                                  onTap: () => context.push(
                                    '/boarders/${person.boarderId}',
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SectionHeader('Room records'),
                      ActionListItem(
                        title: 'Meter reading history',
                        subtitle: 'Readings, corrections and meter changes',
                        icon: Icons.electric_meter_outlined,
                        onTap: () => context.push(
                          '/billing/electricity/rooms/$roomId/readings',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
