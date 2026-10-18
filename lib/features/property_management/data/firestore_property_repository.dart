import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/boarder.dart';
import '../domain/business_date.dart';
import '../domain/occupancy.dart';
import '../domain/property_repository.dart';
import '../domain/room.dart';

class FirestorePropertyRepository implements PropertyRepository {
  FirestorePropertyRepository(this._firestore);

  static const primaryHouseId = 'primary';

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _house(String ownerId) {
    return _firestore
        .collection('owners')
        .doc(ownerId)
        .collection('boardingHouses')
        .doc(primaryHouseId);
  }

  CollectionReference<Map<String, dynamic>> _rooms(String ownerId) =>
      _house(ownerId).collection('rooms');

  CollectionReference<Map<String, dynamic>> _boarders(String ownerId) =>
      _house(ownerId).collection('boarders');

  CollectionReference<Map<String, dynamic>> _occupancies(String ownerId) =>
      _house(ownerId).collection('occupancies');

  @override
  Stream<List<Room>> watchRooms(String ownerId) {
    _validateId(ownerId, 'Owner');
    final stream = _rooms(ownerId).snapshots().map((snapshot) {
      final rooms = snapshot.docs.map(_roomFromDocument).toList();
      rooms.sort((a, b) {
        final byName = a.roomName.toLowerCase().compareTo(
          b.roomName.toLowerCase(),
        );
        return byName != 0 ? byName : a.roomId.compareTo(b.roomId);
      });
      return rooms;
    });
    return _withMappedErrors(stream);
  }

  @override
  Stream<List<Boarder>> watchBoarders(String ownerId) {
    _validateId(ownerId, 'Owner');
    final stream = _boarders(ownerId).snapshots().map((snapshot) {
      final boarders = snapshot.docs.map(_boarderFromDocument).toList();
      boarders.sort((a, b) {
        final byName = a.fullName.toLowerCase().compareTo(
          b.fullName.toLowerCase(),
        );
        return byName != 0 ? byName : a.boarderId.compareTo(b.boarderId);
      });
      return boarders;
    });
    return _withMappedErrors(stream);
  }

  @override
  Stream<List<Occupancy>> watchOccupancies(String ownerId, String boarderId) {
    _validateId(ownerId, 'Owner');
    _validateId(boarderId, 'Boarder');
    final stream = _occupancies(ownerId)
        .where('boarderId', isEqualTo: boarderId)
        .snapshots()
        .map((snapshot) {
          final occupancies = snapshot.docs
              .map(_occupancyFromDocument)
              .toList();
          occupancies.sort((a, b) {
            final byDate = b.moveInDate.compareTo(a.moveInDate);
            return byDate != 0
                ? byDate
                : b.occupancyId.compareTo(a.occupancyId);
          });
          return occupancies;
        });
    return _withMappedErrors(stream);
  }

  @override
  Stream<List<Occupancy>> watchAllOccupancies(String ownerId) {
    _validateId(ownerId, 'Owner');
    final stream = _occupancies(ownerId).snapshots().map((snapshot) {
      final occupancies = snapshot.docs.map(_occupancyFromDocument).toList();
      occupancies.sort((a, b) {
        final byDate = a.moveInDate.compareTo(b.moveInDate);
        return byDate != 0 ? byDate : a.occupancyId.compareTo(b.occupancyId);
      });
      return occupancies;
    });
    return _withMappedErrors(stream);
  }

  @override
  Future<String> createRoom({
    required String ownerId,
    required String roomName,
    String description = '',
    int? defaultMonthlyRentCentavos,
  }) async {
    _validateId(ownerId, 'Owner');
    final cleanName = PropertyValidation.requiredText(
      roomName,
      label: 'Room name',
      maxLength: PropertyValidation.roomNameMaxLength,
    );
    final cleanDescription = PropertyValidation.limitedText(
      description,
      label: 'Description',
      maxLength: PropertyValidation.roomDescriptionMaxLength,
    );
    final rent = PropertyValidation.rentCentavos(defaultMonthlyRentCentavos);
    final roomRef = _rooms(ownerId).doc();

    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final house = await transaction.get(_house(ownerId));
        if (!house.exists) {
          throw _notFound('The boarding house could not be found.');
        }
        final timestamp = FieldValue.serverTimestamp();
        transaction.set(roomRef, {
          'roomId': roomRef.id,
          'roomName': cleanName,
          'description': cleanDescription,
          'status': RoomStatus.active.name,
          'defaultMonthlyRentCentavos': rent,
          'activeOccupancyCount': 0,
          'lastOccupancyMutationId': null,
          'createdAt': timestamp,
          'updatedAt': timestamp,
        });
      });
    });
    return roomRef.id;
  }

  @override
  Future<void> updateRoom({
    required String ownerId,
    required String roomId,
    required String roomName,
    String description = '',
    int? defaultMonthlyRentCentavos,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(roomId, 'Room');
    final cleanName = PropertyValidation.requiredText(
      roomName,
      label: 'Room name',
      maxLength: PropertyValidation.roomNameMaxLength,
    );
    final cleanDescription = PropertyValidation.limitedText(
      description,
      label: 'Description',
      maxLength: PropertyValidation.roomDescriptionMaxLength,
    );
    final rent = PropertyValidation.rentCentavos(defaultMonthlyRentCentavos);
    final roomRef = _rooms(ownerId).doc(roomId);

    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final room = await transaction.get(roomRef);
        if (!room.exists) throw _notFound('That room no longer exists.');
        transaction.update(roomRef, {
          'roomName': cleanName,
          'description': cleanDescription,
          'defaultMonthlyRentCentavos': rent,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    });
  }

  @override
  Future<void> deactivateRoom({
    required String ownerId,
    required String roomId,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(roomId, 'Room');
    final roomRef = _rooms(ownerId).doc(roomId);

    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final room = await transaction.get(roomRef);
        if (!room.exists) throw _notFound('That room no longer exists.');
        final data = room.data()!;
        final count = _activeOccupancyCount(data);
        if (count != 0) {
          throw const PropertyRepositoryException(
            'Move all current boarders out before deactivating this room.',
            code: 'room-occupied',
            isConflict: true,
          );
        }
        if (data['status'] == RoomStatus.inactive.name) return;
        transaction.update(roomRef, {
          'status': RoomStatus.inactive.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    });
  }

  @override
  Future<void> reactivateRoom({
    required String ownerId,
    required String roomId,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(roomId, 'Room');
    final roomRef = _rooms(ownerId).doc(roomId);

    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final room = await transaction.get(roomRef);
        if (!room.exists) throw _notFound('That room no longer exists.');
        final data = room.data()!;
        _activeOccupancyCount(data);
        if (data['status'] == RoomStatus.active.name) return;
        transaction.update(roomRef, {
          'status': RoomStatus.active.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    });
  }

  @override
  Future<String> createBoarder({
    required String ownerId,
    required String fullName,
    String? contact,
    String? notes,
    required String roomId,
    required BusinessDate moveInDate,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(roomId, 'Room');
    PropertyValidation.recordedDate(moveInDate, label: 'Move-in date');
    final cleanName = _boarderName(fullName);
    final cleanContact = _contact(contact);
    final cleanNotes = _notes(notes);
    final boarderRef = _boarders(ownerId).doc();
    final occupancyRef = _occupancies(ownerId).doc();
    final roomRef = _rooms(ownerId).doc(roomId);

    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final room = await transaction.get(roomRef);
        final roomData = _activeRoomData(room);
        final count = _activeOccupancyCount(roomData);
        final timestamp = FieldValue.serverTimestamp();

        transaction.set(boarderRef, {
          'boarderId': boarderRef.id,
          'fullName': cleanName,
          'contact': cleanContact,
          'notes': cleanNotes,
          'status': BoarderStatus.active.name,
          'currentOccupancyId': occupancyRef.id,
          'currentRoomId': roomId,
          'currentMoveInDate': _timestamp(moveInDate),
          'lastMoveOutDate': null,
          'createdAt': timestamp,
          'updatedAt': timestamp,
        });
        transaction.set(occupancyRef, {
          'occupancyId': occupancyRef.id,
          'boarderId': boarderRef.id,
          'roomId': roomId,
          'moveInDate': _timestamp(moveInDate),
          'moveOutDate': null,
          'createdAt': timestamp,
          'updatedAt': timestamp,
        });
        transaction.update(roomRef, {
          'activeOccupancyCount': count + 1,
          'lastOccupancyMutationId': occupancyRef.id,
          'updatedAt': timestamp,
        });
      });
    });
    return boarderRef.id;
  }

  @override
  Future<void> updateBoarder({
    required String ownerId,
    required String boarderId,
    required String fullName,
    String? contact,
    String? notes,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(boarderId, 'Boarder');
    final cleanName = _boarderName(fullName);
    final cleanContact = _contact(contact);
    final cleanNotes = _notes(notes);
    final boarderRef = _boarders(ownerId).doc(boarderId);

    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final boarder = await transaction.get(boarderRef);
        if (!boarder.exists) {
          throw _notFound('That boarder no longer exists.');
        }
        transaction.update(boarderRef, {
          'fullName': cleanName,
          'contact': cleanContact,
          'notes': cleanNotes,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    });
  }

  @override
  Future<void> deactivateBoarder({
    required String ownerId,
    required String boarderId,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(boarderId, 'Boarder');
    final boarderRef = _boarders(ownerId).doc(boarderId);

    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final boarder = await transaction.get(boarderRef);
        if (!boarder.exists) {
          throw _notFound('That boarder no longer exists.');
        }
        final data = boarder.data()!;
        _ensureNoPartialAssignment(data);
        if (data['currentOccupancyId'] != null) {
          throw const PropertyRepositoryException(
            'Move this boarder out before deactivating their record.',
            code: 'boarder-occupying-room',
            isConflict: true,
          );
        }
        if (data['status'] == BoarderStatus.inactive.name) return;
        transaction.update(boarderRef, {
          'status': BoarderStatus.inactive.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    });
  }

  @override
  Future<void> moveOut({
    required String ownerId,
    required String boarderId,
    required BusinessDate moveOutDate,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(boarderId, 'Boarder');
    PropertyValidation.recordedDate(moveOutDate, label: 'Move-out date');
    final boarderRef = _boarders(ownerId).doc(boarderId);

    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final boarder = await transaction.get(boarderRef);
        if (!boarder.exists) {
          throw _notFound('That boarder no longer exists.');
        }
        final boarderData = boarder.data()!;
        final assignment = _currentAssignment(boarderData);
        final occupancyRef = _occupancies(ownerId).doc(assignment.occupancyId);
        final roomRef = _rooms(ownerId).doc(assignment.roomId);
        final occupancy = await transaction.get(occupancyRef);
        final room = await transaction.get(roomRef);

        final occupancyData = _currentOccupancyData(
          occupancy,
          boarderId: boarderId,
          roomId: assignment.roomId,
        );
        final moveInDate = _businessDate(
          occupancyData['moveInDate'],
          'moveInDate',
        );
        if (!moveOutDate.isAfter(moveInDate)) {
          throw const PropertyRepositoryException(
            'Move-out must be after the current move-in date.',
            code: 'invalid-occupancy-dates',
          );
        }
        if (!room.exists) {
          throw _integrity('The boarder\'s current room is missing.');
        }
        final count = _activeOccupancyCount(room.data()!);
        if (count < 1) {
          throw _integrity('The room occupancy count is inconsistent.');
        }
        final timestamp = FieldValue.serverTimestamp();
        transaction.update(occupancyRef, {
          'moveOutDate': _timestamp(moveOutDate),
          'updatedAt': timestamp,
        });
        transaction.update(boarderRef, {
          'status': BoarderStatus.movedOut.name,
          'currentOccupancyId': null,
          'currentRoomId': null,
          'currentMoveInDate': null,
          'lastMoveOutDate': _timestamp(moveOutDate),
          'updatedAt': timestamp,
        });
        transaction.update(roomRef, {
          'activeOccupancyCount': count - 1,
          'lastOccupancyMutationId': assignment.occupancyId,
          'updatedAt': timestamp,
        });
      });
    });
  }

  @override
  Future<void> moveIn({
    required String ownerId,
    required String boarderId,
    required String roomId,
    required BusinessDate moveInDate,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(boarderId, 'Boarder');
    _validateId(roomId, 'Room');
    PropertyValidation.recordedDate(moveInDate, label: 'Move-in date');
    final boarderRef = _boarders(ownerId).doc(boarderId);
    final roomRef = _rooms(ownerId).doc(roomId);
    final occupancyRef = _occupancies(ownerId).doc();

    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final boarder = await transaction.get(boarderRef);
        final room = await transaction.get(roomRef);
        if (!boarder.exists) {
          throw _notFound('That boarder no longer exists.');
        }
        final boarderData = boarder.data()!;
        _ensureNoPartialAssignment(boarderData);
        if (boarderData['currentOccupancyId'] != null ||
            boarderData['status'] == BoarderStatus.active.name) {
          throw const PropertyRepositoryException(
            'This boarder is already assigned to a room.',
            code: 'boarder-already-assigned',
            isConflict: true,
          );
        }
        final lastMoveOut = _optionalBusinessDate(
          boarderData['lastMoveOutDate'],
          'lastMoveOutDate',
        );
        if (lastMoveOut != null && moveInDate.isBefore(lastMoveOut)) {
          throw PropertyRepositoryException(
            'Move-in cannot be before the last move-out date ($lastMoveOut).',
            code: 'overlapping-occupancy',
            isConflict: true,
          );
        }
        final roomData = _activeRoomData(room);
        final count = _activeOccupancyCount(roomData);
        final timestamp = FieldValue.serverTimestamp();
        transaction.set(occupancyRef, {
          'occupancyId': occupancyRef.id,
          'boarderId': boarderId,
          'roomId': roomId,
          'moveInDate': _timestamp(moveInDate),
          'moveOutDate': null,
          'createdAt': timestamp,
          'updatedAt': timestamp,
        });
        transaction.update(boarderRef, {
          'status': BoarderStatus.active.name,
          'currentOccupancyId': occupancyRef.id,
          'currentRoomId': roomId,
          'currentMoveInDate': _timestamp(moveInDate),
          'updatedAt': timestamp,
        });
        transaction.update(roomRef, {
          'activeOccupancyCount': count + 1,
          'lastOccupancyMutationId': occupancyRef.id,
          'updatedAt': timestamp,
        });
      });
    });
  }

  @override
  Future<void> transfer({
    required String ownerId,
    required String boarderId,
    required String toRoomId,
    required BusinessDate transferDate,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(boarderId, 'Boarder');
    _validateId(toRoomId, 'Room');
    PropertyValidation.recordedDate(transferDate, label: 'Transfer date');
    final boarderRef = _boarders(ownerId).doc(boarderId);
    final newOccupancyRef = _occupancies(ownerId).doc();

    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final boarder = await transaction.get(boarderRef);
        if (!boarder.exists) {
          throw _notFound('That boarder no longer exists.');
        }
        final boarderData = boarder.data()!;
        final assignment = _currentAssignment(boarderData);
        if (assignment.roomId == toRoomId) {
          throw const PropertyRepositoryException(
            'Choose a different room for the transfer.',
            code: 'same-room-transfer',
          );
        }
        final currentOccupancyRef = _occupancies(ownerId)
            .doc(assignment.occupancyId);
        final fromRoomRef = _rooms(ownerId).doc(assignment.roomId);
        final toRoomRef = _rooms(ownerId).doc(toRoomId);
        final currentOccupancy = await transaction.get(currentOccupancyRef);
        final fromRoom = await transaction.get(fromRoomRef);
        final toRoom = await transaction.get(toRoomRef);

        final occupancyData = _currentOccupancyData(
          currentOccupancy,
          boarderId: boarderId,
          roomId: assignment.roomId,
        );
        final currentMoveIn = _businessDate(
          occupancyData['moveInDate'],
          'moveInDate',
        );
        if (!transferDate.isAfter(currentMoveIn)) {
          throw const PropertyRepositoryException(
            'Transfer date must be after the current move-in date.',
            code: 'invalid-occupancy-dates',
          );
        }
        if (!fromRoom.exists) {
          throw _integrity('The boarder\'s current room is missing.');
        }
        final fromCount = _activeOccupancyCount(fromRoom.data()!);
        if (fromCount < 1) {
          throw _integrity('The current room occupancy count is inconsistent.');
        }
        final toRoomData = _activeRoomData(toRoom);
        final toCount = _activeOccupancyCount(toRoomData);
        final timestamp = FieldValue.serverTimestamp();

        transaction.update(currentOccupancyRef, {
          'moveOutDate': _timestamp(transferDate),
          'updatedAt': timestamp,
        });
        transaction.set(newOccupancyRef, {
          'occupancyId': newOccupancyRef.id,
          'boarderId': boarderId,
          'roomId': toRoomId,
          'moveInDate': _timestamp(transferDate),
          'moveOutDate': null,
          'createdAt': timestamp,
          'updatedAt': timestamp,
        });
        transaction.update(boarderRef, {
          'status': BoarderStatus.active.name,
          'currentOccupancyId': newOccupancyRef.id,
          'currentRoomId': toRoomId,
          'currentMoveInDate': _timestamp(transferDate),
          'lastMoveOutDate': _timestamp(transferDate),
          'updatedAt': timestamp,
        });
        transaction.update(fromRoomRef, {
          'activeOccupancyCount': fromCount - 1,
          'lastOccupancyMutationId': assignment.occupancyId,
          'updatedAt': timestamp,
        });
        transaction.update(toRoomRef, {
          'activeOccupancyCount': toCount + 1,
          'lastOccupancyMutationId': newOccupancyRef.id,
          'updatedAt': timestamp,
        });
      });
    });
  }

  Room _roomFromDocument(QueryDocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();
    final status = switch (data['status']) {
      'active' => RoomStatus.active,
      'inactive' => RoomStatus.inactive,
      _ => throw _schema('A room has an invalid status.'),
    };
    final rent = data['defaultMonthlyRentCentavos'];
    if (rent != null && (rent is! int || rent < 0)) {
      throw _schema('A room has an invalid monthly rent.');
    }
    final roomId = _requiredString(data['roomId'], 'roomId');
    if (roomId != document.id) {
      throw _schema('A room identifier is inconsistent.');
    }
    return Room(
      roomId: roomId,
      roomName: _requiredString(data['roomName'], 'roomName'),
      description: _string(data['description'], 'description'),
      status: status,
      defaultMonthlyRentCentavos: rent as int?,
      activeOccupancyCount: _activeOccupancyCount(data),
      createdAt: _dateTime(data['createdAt'], 'createdAt'),
      updatedAt: _dateTime(data['updatedAt'], 'updatedAt'),
    );
  }

  Boarder _boarderFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    _ensureNoPartialAssignment(data);
    final status = switch (data['status']) {
      'active' => BoarderStatus.active,
      'movedOut' => BoarderStatus.movedOut,
      'inactive' => BoarderStatus.inactive,
      _ => throw _schema('A boarder has an invalid status.'),
    };
    final boarderId = _requiredString(data['boarderId'], 'boarderId');
    if (boarderId != document.id) {
      throw _schema('A boarder identifier is inconsistent.');
    }
    final currentOccupancyId = _optionalString(
      data['currentOccupancyId'],
      'currentOccupancyId',
    );
    final currentRoomId = _optionalString(
      data['currentRoomId'],
      'currentRoomId',
    );
    final currentMoveInDate = _optionalBusinessDate(
      data['currentMoveInDate'],
      'currentMoveInDate',
    );
    final assigned = currentOccupancyId != null;
    if (assigned != (currentMoveInDate != null) ||
        assigned != (status == BoarderStatus.active)) {
      throw _schema('A boarder assignment is inconsistent.');
    }
    return Boarder(
      boarderId: boarderId,
      fullName: _requiredString(data['fullName'], 'fullName'),
      contact: _optionalString(data['contact'], 'contact'),
      notes: _optionalString(data['notes'], 'notes'),
      status: status,
      currentOccupancyId: currentOccupancyId,
      currentRoomId: currentRoomId,
      currentMoveInDate: currentMoveInDate,
      lastMoveOutDate: _optionalBusinessDate(
        data['lastMoveOutDate'],
        'lastMoveOutDate',
      ),
      createdAt: _dateTime(data['createdAt'], 'createdAt'),
      updatedAt: _dateTime(data['updatedAt'], 'updatedAt'),
    );
  }

  Occupancy _occupancyFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final occupancyId = _requiredString(data['occupancyId'], 'occupancyId');
    if (occupancyId != document.id) {
      throw _schema('An occupancy identifier is inconsistent.');
    }
    final moveIn = _businessDate(data['moveInDate'], 'moveInDate');
    final moveOut = _optionalBusinessDate(data['moveOutDate'], 'moveOutDate');
    if (moveOut != null && !moveOut.isAfter(moveIn)) {
      throw _schema('An occupancy has an invalid date range.');
    }
    return Occupancy(
      occupancyId: occupancyId,
      boarderId: _requiredString(data['boarderId'], 'boarderId'),
      roomId: _requiredString(data['roomId'], 'roomId'),
      moveInDate: moveIn,
      moveOutDate: moveOut,
      createdAt: _dateTime(data['createdAt'], 'createdAt'),
      updatedAt: _dateTime(data['updatedAt'], 'updatedAt'),
    );
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on PropertyRepositoryException {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapFirestoreException(error);
    }
  }

  Stream<T> _withMappedErrors<T>(Stream<T> source) {
    return source.transform(
      StreamTransformer<T, T>.fromHandlers(
        handleError: (Object error, StackTrace stackTrace, EventSink<T> sink) {
          if (error is FirebaseException) {
            sink.addError(_mapFirestoreException(error), stackTrace);
          } else {
            sink.addError(error, stackTrace);
          }
        },
      ),
    );
  }

  PropertyRepositoryException _mapFirestoreException(FirebaseException error) {
    final isOffline =
        error.code == 'unavailable' ||
        error.code == 'network-request-failed' ||
        error.code == 'deadline-exceeded';
    final isConflict =
        error.code == 'aborted' ||
        error.code == 'already-exists' ||
        error.code == 'failed-precondition';
    final message = switch ((isOffline, isConflict, error.code)) {
      (true, _, _) => 'This change could not be confirmed while offline. Reconnect and try again.',
      (_, true, _) =>
        'Another change happened at the same time. Refresh and try again.',
      (_, _, 'permission-denied') =>
        'You do not have permission to change this boarding house.',
      _ => 'The property record could not be saved. Please try again.',
    };
    return PropertyRepositoryException(
      message,
      code: error.code,
      isOffline: isOffline,
      isConflict: isConflict,
    );
  }

  Map<String, dynamic> _activeRoomData(
    DocumentSnapshot<Map<String, dynamic>> room,
  ) {
    if (!room.exists) throw _notFound('The selected room no longer exists.');
    final data = room.data()!;
    if (data['status'] != RoomStatus.active.name) {
      throw const PropertyRepositoryException(
        'The selected room is inactive. Reactivate it or choose another room.',
        code: 'inactive-room',
        isConflict: true,
      );
    }
    return data;
  }

  Map<String, dynamic> _currentOccupancyData(
    DocumentSnapshot<Map<String, dynamic>> occupancy, {
    required String boarderId,
    required String roomId,
  }) {
    if (!occupancy.exists) {
      throw _integrity('The boarder\'s current occupancy is missing.');
    }
    final data = occupancy.data()!;
    if (data['boarderId'] != boarderId ||
        data['roomId'] != roomId ||
        data['moveOutDate'] != null) {
      throw _integrity('The boarder\'s current occupancy is inconsistent.');
    }
    return data;
  }

  ({String occupancyId, String roomId}) _currentAssignment(
    Map<String, dynamic> boarder,
  ) {
    _ensureNoPartialAssignment(boarder);
    final occupancyId = boarder['currentOccupancyId'];
    final roomId = boarder['currentRoomId'];
    if (occupancyId is! String ||
        occupancyId.isEmpty ||
        roomId is! String ||
        roomId.isEmpty ||
        boarder['status'] != BoarderStatus.active.name) {
      throw const PropertyRepositoryException(
        'This boarder is not currently assigned to a room.',
        code: 'boarder-not-assigned',
        isConflict: true,
      );
    }
    return (occupancyId: occupancyId, roomId: roomId);
  }

  void _ensureNoPartialAssignment(Map<String, dynamic> boarder) {
    final hasOccupancy = boarder['currentOccupancyId'] != null;
    final hasRoom = boarder['currentRoomId'] != null;
    if (hasOccupancy != hasRoom) {
      throw _integrity('A boarder assignment is incomplete.');
    }
  }

  int _activeOccupancyCount(Map<String, dynamic> room) {
    final count = room['activeOccupancyCount'];
    if (count is! int || count < 0) {
      throw _integrity('A room occupancy count is invalid.');
    }
    return count;
  }

  String _boarderName(String value) => PropertyValidation.requiredText(
    value,
    label: 'Full name',
    maxLength: PropertyValidation.boarderNameMaxLength,
  );

  String? _contact(String? value) => PropertyValidation.optionalText(
    value,
    label: 'Contact',
    maxLength: PropertyValidation.contactMaxLength,
  );

  String? _notes(String? value) => PropertyValidation.optionalText(
    value,
    label: 'Notes',
    maxLength: PropertyValidation.notesMaxLength,
  );

  void _validateId(String value, String label) {
    if (value.trim().isEmpty || value.contains('/')) {
      throw PropertyRepositoryException(
        '$label identifier is invalid.',
        code: 'invalid-argument',
      );
    }
  }

  String _requiredString(Object? value, String field) {
    final result = _string(value, field);
    if (result.isEmpty) throw _schema('$field is missing.');
    return result;
  }

  String _string(Object? value, String field) {
    if (value is! String) throw _schema('$field is invalid.');
    return value;
  }

  String? _optionalString(Object? value, String field) {
    if (value == null) return null;
    return _string(value, field);
  }

  DateTime _dateTime(Object? value, String field) {
    if (value is! Timestamp) throw _schema('$field is invalid.');
    return value.toDate().toUtc();
  }

  BusinessDate _businessDate(Object? value, String field) {
    if (value is! Timestamp) throw _schema('$field is invalid.');
    try {
      return BusinessDate.fromUtcDateTime(value.toDate());
    } on FormatException {
      throw _schema('$field is not a date-only value.');
    }
  }

  BusinessDate? _optionalBusinessDate(Object? value, String field) {
    if (value == null) return null;
    return _businessDate(value, field);
  }

  Timestamp _timestamp(BusinessDate date) {
    return Timestamp.fromDate(date.asUtcDateTime);
  }

  PropertyRepositoryException _notFound(String message) {
    return PropertyRepositoryException(message, code: 'not-found');
  }

  PropertyRepositoryException _integrity(String message) {
    return PropertyRepositoryException(
      '$message Please contact support before making more changes.',
      code: 'data-integrity',
      isConflict: true,
    );
  }

  PropertyRepositoryException _schema(String message) {
    return PropertyRepositoryException(
      '$message Refresh the app. If it continues, contact support.',
      code: 'invalid-data',
    );
  }
}
