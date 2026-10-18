import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/property_providers.dart';
import '../../domain/boarder.dart';
import '../../domain/business_date.dart';
import '../../domain/property_repository.dart';
import '../../domain/room.dart';
import '../widgets/property_formatters.dart';
import '../widgets/property_ui.dart';

class BoarderFormSheet extends ConsumerStatefulWidget {
  const BoarderFormSheet({
    required this.ownerId,
    required this.activeRooms,
    this.boarder,
    super.key,
  });

  final String ownerId;
  final List<Room> activeRooms;
  final Boarder? boarder;

  @override
  ConsumerState<BoarderFormSheet> createState() => _BoarderFormSheetState();
}

class _BoarderFormSheetState extends ConsumerState<BoarderFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _contactController;
  late final TextEditingController _notesController;
  String? _roomId;
  BusinessDate? _moveInDate;
  bool _submitting = false;
  String? _submitError;

  bool get _isEditing => widget.boarder != null;

  @override
  void initState() {
    super.initState();
    final boarder = widget.boarder;
    _nameController = TextEditingController(text: boarder?.fullName ?? '');
    _contactController = TextEditingController(text: boarder?.contact ?? '');
    _notesController = TextEditingController(text: boarder?.notes ?? '');
    if (!_isEditing && widget.activeRooms.isNotEmpty) {
      _roomId = widget.activeRooms.first.roomId;
      _moveInDate = BusinessDate.todayInManila();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final clean = value?.trim() ?? '';
    if (clean.isEmpty) return 'Full name is required.';
    if (clean.length > PropertyValidation.boarderNameMaxLength) {
      return 'Use ${PropertyValidation.boarderNameMaxLength} characters or fewer.';
    }
    return null;
  }

  Future<void> _pickMoveInDate() async {
    final businessToday = BusinessDate.todayInManila();
    final today = businessToday.value;
    final initial = _moveInDate?.value ?? today;
    final selected = await showDatePicker(
      context: context,
      helpText: 'Select move-in date',
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year, today.month, today.day),
    );
    if (selected != null && mounted) {
      setState(() => _moveInDate = BusinessDate.fromDateTime(selected));
    }
  }

  Future<void> _submit() async {
    setState(() => _submitError = null);
    if (!_formKey.currentState!.validate()) return;
    if (!_isEditing && (_roomId == null || _moveInDate == null)) {
      setState(() => _submitError = 'Choose a room and move-in date.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final repository = ref.read(propertyRepositoryProvider);
      late final String boarderId;
      if (_isEditing) {
        boarderId = widget.boarder!.boarderId;
        await repository.updateBoarder(
          ownerId: widget.ownerId,
          boarderId: boarderId,
          fullName: _nameController.text,
          contact: _contactController.text,
          notes: _notesController.text,
        );
      } else {
        boarderId = await repository.createBoarder(
          ownerId: widget.ownerId,
          fullName: _nameController.text,
          contact: _contactController.text,
          notes: _notesController.text,
          roomId: _roomId!,
          moveInDate: _moveInDate!,
        );
      }
      if (mounted) Navigator.pop(context, boarderId);
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                          _isEditing ? 'Edit boarder' : 'Add a boarder',
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
                    _isEditing
                        ? 'Room changes are recorded separately so occupancy history stays accurate.'
                        : 'A new boarder is assigned to one room immediately. More boarders may share that room.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: const Key('boarder-name-field'),
                    controller: _nameController,
                    enabled: !_submitting,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    maxLength: PropertyValidation.boarderNameMaxLength,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: _validateName,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('boarder-contact-field'),
                    controller: _contactController,
                    enabled: !_submitting,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    maxLength: PropertyValidation.contactMaxLength,
                    decoration: const InputDecoration(
                      labelText: 'Contact (optional)',
                      hintText: 'Phone number or email',
                      prefixIcon: Icon(Icons.contact_phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('boarder-notes-field'),
                    controller: _notesController,
                    enabled: !_submitting,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: PropertyValidation.notesMaxLength,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (!_isEditing) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const Key('boarder-room-field'),
                      initialValue: _roomId,
                      decoration: const InputDecoration(
                        labelText: 'Room',
                        prefixIcon: Icon(Icons.meeting_room_outlined),
                      ),
                      items: widget.activeRooms
                          .map(
                            (room) => DropdownMenuItem(
                              value: room.roomId,
                              child: Text(
                                room.roomName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _roomId = value),
                      validator: (value) =>
                          value == null ? 'Choose a room.' : null,
                    ),
                    const SizedBox(height: 12),
                    _DateField(
                      label: 'Move-in date',
                      value: _moveInDate,
                      enabled: !_submitting,
                      onTap: _pickMoveInDate,
                    ),
                  ],
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
                    key: const Key('boarder-save-button'),
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
                          : 'Add boarder',
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

enum OccupancyAction { moveIn, transfer }

class OccupancyActionSheet extends ConsumerStatefulWidget {
  const OccupancyActionSheet({
    required this.ownerId,
    required this.boarder,
    required this.availableRooms,
    required this.action,
    super.key,
  });

  final String ownerId;
  final Boarder boarder;
  final List<Room> availableRooms;
  final OccupancyAction action;

  @override
  ConsumerState<OccupancyActionSheet> createState() =>
      _OccupancyActionSheetState();
}

class _OccupancyActionSheetState extends ConsumerState<OccupancyActionSheet> {
  final _formKey = GlobalKey<FormState>();
  String? _roomId;
  late BusinessDate _date;
  bool _submitting = false;
  String? _submitError;

  bool get _isTransfer => widget.action == OccupancyAction.transfer;

  BusinessDate get _today => BusinessDate.todayInManila();

  BusinessDate get _firstDate {
    if (_isTransfer) {
      return _nextDate(widget.boarder.currentMoveInDate!);
    }
    return widget.boarder.lastMoveOutDate ?? BusinessDate(2000, 1, 1);
  }

  @override
  void initState() {
    super.initState();
    if (widget.availableRooms.isNotEmpty) {
      _roomId = widget.availableRooms.first.roomId;
    }
    final earliest = _firstDate;
    _date = _today.isBefore(earliest) ? earliest : _today;
  }

  Future<void> _pickDate() async {
    final first = _firstDate.value;
    final last = _today.value;
    if (first.isAfter(last)) {
      setState(() {
        _submitError = _isTransfer
            ? 'A transfer must be after move-in, so it cannot be recorded until the next day.'
            : 'This move-in date is not available yet.';
      });
      return;
    }
    final selected = await showDatePicker(
      context: context,
      helpText: _isTransfer ? 'Select transfer date' : 'Select move-in date',
      initialDate: _date.value,
      firstDate: first,
      lastDate: last,
    );
    if (selected != null && mounted) {
      setState(() => _date = BusinessDate.fromDateTime(selected));
    }
  }

  Future<void> _submit() async {
    setState(() => _submitError = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final repository = ref.read(propertyRepositoryProvider);
      if (_isTransfer) {
        await repository.transfer(
          ownerId: widget.ownerId,
          boarderId: widget.boarder.boarderId,
          toRoomId: _roomId!,
          transferDate: _date,
        );
      } else {
        await repository.moveIn(
          ownerId: widget.ownerId,
          boarderId: widget.boarder.boarderId,
          roomId: _roomId!,
          moveInDate: _date,
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
    final title = _isTransfer ? 'Transfer boarder' : 'Move boarder in';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                          title,
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
                    _isTransfer
                        ? 'The transfer date closes the old assignment and starts the new one. That date is billable only in the new room.'
                        : 'Move-in is billable. It cannot be earlier than the last move-out date.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    key: const Key('occupancy-room-field'),
                    initialValue: _roomId,
                    decoration: const InputDecoration(
                      labelText: 'New room',
                      prefixIcon: Icon(Icons.meeting_room_outlined),
                    ),
                    items: widget.availableRooms
                        .map(
                          (room) => DropdownMenuItem(
                            value: room.roomId,
                            child: Text(
                              room.roomName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _roomId = value),
                    validator: (value) =>
                        value == null ? 'Choose an active room.' : null,
                  ),
                  const SizedBox(height: 12),
                  _DateField(
                    label: _isTransfer ? 'Transfer date' : 'Move-in date',
                    value: _date,
                    enabled: !_submitting,
                    onTap: _pickDate,
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
                    onPressed: _submitting || widget.availableRooms.isEmpty
                        ? null
                        : _submit,
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _isTransfer
                                ? Icons.swap_horiz_rounded
                                : Icons.login_rounded,
                          ),
                    label: Text(_submitting ? 'Saving…' : title),
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

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final BusinessDate? value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: value == null
          ? '$label, not selected'
          : '$label, ${formatBusinessDate(value!)}',
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.calendar_today_outlined),
            suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
            enabled: enabled,
          ),
          child: Text(
            value == null ? 'Choose a date' : formatBusinessDate(value!),
          ),
        ),
      ),
    );
  }
}

BusinessDate _nextDate(BusinessDate date) {
  return BusinessDate.fromUtcDateTime(
    date.asUtcDateTime.add(const Duration(days: 1)),
  );
}
