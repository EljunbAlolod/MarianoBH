import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../property_management/domain/business_date.dart';
import '../domain/electricity_models.dart';
import '../domain/electricity_repository.dart';
import '../domain/electricity_values.dart';
import '../domain/electricity_batch_models.dart';

class FirestoreElectricityRepository implements ElectricityRepository {
  FirestoreElectricityRepository(this._firestore);

  static const primaryHouseId = 'primary';
  static const _maximumNoteLength = 500;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _house(String ownerId) => _firestore
      .collection('owners')
      .doc(ownerId)
      .collection('boardingHouses')
      .doc(primaryHouseId);

  CollectionReference<Map<String, dynamic>> _rooms(String ownerId) =>
      _house(ownerId).collection('rooms');

  CollectionReference<Map<String, dynamic>> _states(String ownerId) =>
      _house(ownerId).collection('roomMeterStates');

  CollectionReference<Map<String, dynamic>> _meters(String ownerId) =>
      _house(ownerId).collection('electricityMeters');

  CollectionReference<Map<String, dynamic>> _readings(String ownerId) =>
      _house(ownerId).collection('meterReadings');

  CollectionReference<Map<String, dynamic>> _records(String ownerId) =>
      _house(ownerId).collection('electricityBillingRecords');

  CollectionReference<Map<String, dynamic>> _corrections(String ownerId) =>
      _house(ownerId).collection('meterReadingCorrections');

  CollectionReference<Map<String, dynamic>> _insertions(String ownerId) =>
      _house(ownerId).collection('meterReadingInsertions');

  CollectionReference<Map<String, dynamic>> _batches(String ownerId) =>
      _house(ownerId).collection('electricityReadingBatches');

  CollectionReference<Map<String, dynamic>> _batchLinks(String ownerId) =>
      _house(ownerId).collection('electricityBatchReadingLinks');

  CollectionReference<Map<String, dynamic>> _batchVoids(String ownerId) =>
      _house(ownerId).collection('electricityBatchVoids');

  @override
  Stream<List<ElectricityReadingBatch>> watchReadingBatches(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mappedStream(
      _batches(ownerId).snapshots().map((snapshot) {
        final items = snapshot.docs
            .map((document) => _batchFromData(document.id, document.data()))
            .toList();
        items.sort((a, b) {
          final date = b.effectiveAt.compareTo(a.effectiveAt);
          return date != 0 ? date : b.batchId.compareTo(a.batchId);
        });
        return items;
      }),
    );
  }

  @override
  Stream<List<RoomMeterState>> watchRoomMeterStates(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mappedStream(
      _states(ownerId).snapshots().map((snapshot) {
        final items = snapshot.docs.map(_stateFromDocument).toList();
        items.sort((a, b) => a.roomId.compareTo(b.roomId));
        return items;
      }),
    );
  }

  @override
  Stream<List<ElectricityMeter>> watchMeters(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mappedStream(
      _meters(ownerId).snapshots().map((snapshot) {
        final items = snapshot.docs.map(_meterFromDocument).toList();
        items.sort((a, b) {
          final room = a.roomId.compareTo(b.roomId);
          return room != 0 ? room : a.sequence.compareTo(b.sequence);
        });
        return items;
      }),
    );
  }

  @override
  Stream<List<MeterReading>> watchReadings(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mappedStream(
      _readings(ownerId).snapshots().map((snapshot) {
        final items = snapshot.docs.map(_readingFromDocument).toList();
        items.sort((a, b) {
          final room = a.roomId.compareTo(b.roomId);
          if (room != 0) return room;
          final date = a.readingDate.compareTo(b.readingDate);
          if (date != 0) return date;
          final sequence = a.sequence.compareTo(b.sequence);
          if (sequence != 0) return sequence;
          return a.readingId.compareTo(b.readingId);
        });
        return items;
      }),
    );
  }

  @override
  Stream<List<MeterReadingCorrection>> watchReadingCorrections(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mappedStream(
      _corrections(ownerId).snapshots().map((snapshot) {
        final items = snapshot.docs.map(_correctionFromDocument).toList();
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return items;
      }),
    );
  }

  @override
  Stream<List<ElectricityBillingRecord>> watchBillingRecords(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mappedStream(
      _records(ownerId).snapshots().map((snapshot) {
        final items = snapshot.docs.map(_recordFromDocument).toList();
        items.sort((a, b) {
          final date = b.endDateExclusive.compareTo(a.endDateExclusive);
          return date != 0
              ? date
              : b.billingRecordId.compareTo(a.billingRecordId);
        });
        return items;
      }),
    );
  }

  @override
  Future<void> initializeMeter({
    required String ownerId,
    required String roomId,
    required BusinessDate openingDate,
    required int openingReadingWh,
    String? note,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(roomId, 'Room');
    _validateRecordedDate(openingDate, 'Opening date');
    _validateNonNegative(openingReadingWh, 'Opening reading');
    final cleanNote = _optionalText(note, 'Note');
    final stateRef = _states(ownerId).doc(roomId);
    final meterRef = _meters(ownerId).doc();
    final readingRef = _readings(ownerId).doc();

    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final house = await transaction.get(_house(ownerId));
        final room = await transaction.get(_rooms(ownerId).doc(roomId));
        final state = await transaction.get(stateRef);
        if (!house.exists) {
          throw _notFound('The boarding house could not be found.');
        }
        if (!room.exists) throw _notFound('That room no longer exists.');
        if (state.exists) {
          throw const ElectricityRepositoryException(
            'This room already has an electricity meter.',
            code: 'meter-already-exists',
            isConflict: true,
          );
        }
        final timestamp = FieldValue.serverTimestamp();
        transaction.set(readingRef, {
          'readingId': readingRef.id,
          'meterId': meterRef.id,
          'roomId': roomId,
          'sequenceNumber': 1,
          'readingDate': _timestamp(openingDate),
          'readingWh': openingReadingWh,
          'kind': MeterReadingKind.opening.name,
          'previousReadingId': null,
          'previousReadingDate': null,
          'previousReadingWh': null,
          'consumptionWh': 0,
          'note': cleanNote,
          'billingRecordIds': <String>[],
          'correctionCount': 0,
          'lastCorrectionId': null,
          'lastCorrectedAt': null,
          'lastCorrectedBy': null,
          'createdAt': timestamp,
        });
        transaction.set(meterRef, {
          'meterId': meterRef.id,
          'roomId': roomId,
          'sequenceNumber': 1,
          'status': ElectricityMeterStatus.active.name,
          'startedOn': _timestamp(openingDate),
          'endedOn': null,
          'startKind': ElectricityMeterStartKind.initial.name,
          'transitionReason': null,
          'previousMeterId': null,
          'replacementMeterId': null,
          'lastReadingId': readingRef.id,
          'lastReadingDate': _timestamp(openingDate),
          'lastReadingWh': openingReadingWh,
          'createdAt': timestamp,
          'updatedAt': timestamp,
        });
        transaction.set(stateRef, {
          'roomId': roomId,
          'currentMeterId': meterRef.id,
          'lastTransitionId': meterRef.id,
          'createdAt': timestamp,
          'updatedAt': timestamp,
        });
      });
    });
  }

  @override
  Future<void> recordReading({
    required String ownerId,
    required String roomId,
    required BusinessDate readingDate,
    required int readingWh,
    MeterReadingKind kind = MeterReadingKind.regular,
    String? note,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(roomId, 'Room');
    _validateRecordedDate(readingDate, 'Reading date');
    _validateNonNegative(readingWh, 'Meter reading');
    if (kind != MeterReadingKind.regular &&
        kind != MeterReadingKind.intermediate) {
      throw const ElectricityRepositoryException(
        'Choose a regular or intermediate reading.',
        code: 'invalid-reading-kind',
      );
    }
    final cleanNote = _optionalText(note, 'Note');
    final stateRef = _states(ownerId).doc(roomId);
    final readingRef = _readings(ownerId).doc();

    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final state = await transaction.get(stateRef);
        if (!state.exists) {
          throw _notFound('Set up this room\'s meter before adding readings.');
        }
        final currentMeterId = _requiredString(
          state.data()!['currentMeterId'],
          'currentMeterId',
        );
        final meterRef = _meters(ownerId).doc(currentMeterId);
        final meter = await transaction.get(meterRef);
        final data = _activeMeterData(meter, roomId: roomId);
        final previousDate = _businessDate(
          data['lastReadingDate'],
          'lastReadingDate',
        );
        final previousWh = _nonNegativeInt(
          data['lastReadingWh'],
          'lastReadingWh',
        );
        final previousId = _requiredString(
          data['lastReadingId'],
          'lastReadingId',
        );
        if (!readingDate.isAfter(previousDate)) {
          throw ElectricityRepositoryException(
            'Reading date must be after $previousDate. Intermediate readings must be entered chronologically.',
            code: 'reading-not-chronological',
            isConflict: true,
          );
        }
        if (readingWh < previousWh) {
          throw const ElectricityRepositoryException(
            'The current reading cannot be lower. Use the reset, replacement, or correction workflow instead.',
            code: 'negative-consumption',
          );
        }
        final sequence = _positiveInt(data['sequenceNumber'], 'sequenceNumber');
        final timestamp = FieldValue.serverTimestamp();
        transaction.set(readingRef, {
          'readingId': readingRef.id,
          'meterId': currentMeterId,
          'roomId': roomId,
          'sequenceNumber': sequence,
          'readingDate': _timestamp(readingDate),
          'readingWh': readingWh,
          'kind': kind.name,
          'previousReadingId': previousId,
          'previousReadingDate': _timestamp(previousDate),
          'previousReadingWh': previousWh,
          'consumptionWh': readingWh - previousWh,
          'note': cleanNote,
          'billingRecordIds': <String>[],
          'correctionCount': 0,
          'lastCorrectionId': null,
          'lastCorrectedAt': null,
          'lastCorrectedBy': null,
          'createdAt': timestamp,
        });
        transaction.update(meterRef, {
          'lastReadingId': readingRef.id,
          'lastReadingDate': _timestamp(readingDate),
          'lastReadingWh': readingWh,
          'updatedAt': timestamp,
        });
      });
    });
  }

  @override
  Future<void> transitionMeter({
    required String ownerId,
    required String roomId,
    required BusinessDate transitionDate,
    required int closingReadingWh,
    required int newOpeningReadingWh,
    required ElectricityMeterStartKind startKind,
    required String reason,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(roomId, 'Room');
    _validateRecordedDate(transitionDate, 'Transition date');
    _validateNonNegative(closingReadingWh, 'Closing reading');
    _validateNonNegative(newOpeningReadingWh, 'New opening reading');
    if (startKind == ElectricityMeterStartKind.initial) {
      throw const ElectricityRepositoryException(
        'Choose reset, replacement, or correction.',
        code: 'invalid-transition-kind',
      );
    }
    final cleanReason = _requiredText(reason, 'Reason');
    final stateRef = _states(ownerId).doc(roomId);
    final newMeterRef = _meters(ownerId).doc();
    final closingReadingRef = _readings(ownerId).doc();
    final openingReadingRef = _readings(ownerId).doc();

    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final state = await transaction.get(stateRef);
        if (!state.exists) {
          throw _notFound('Set up this room\'s meter first.');
        }
        final oldMeterId = _requiredString(
          state.data()!['currentMeterId'],
          'currentMeterId',
        );
        final oldMeterRef = _meters(ownerId).doc(oldMeterId);
        final oldMeter = await transaction.get(oldMeterRef);
        final old = _activeMeterData(oldMeter, roomId: roomId);
        final previousDate = _businessDate(
          old['lastReadingDate'],
          'lastReadingDate',
        );
        final previousWh = _nonNegativeInt(
          old['lastReadingWh'],
          'lastReadingWh',
        );
        final previousId = _requiredString(
          old['lastReadingId'],
          'lastReadingId',
        );
        if (!transitionDate.isAfter(previousDate)) {
          throw ElectricityRepositoryException(
            'Transition date must be after $previousDate.',
            code: 'transition-not-chronological',
            isConflict: true,
          );
        }
        if (closingReadingWh < previousWh) {
          throw const ElectricityRepositoryException(
            'The old meter closing reading cannot be lower than its previous reading.',
            code: 'negative-consumption',
          );
        }
        final oldSequence = _positiveInt(
          old['sequenceNumber'],
          'sequenceNumber',
        );
        final newSequence = oldSequence + 1;
        final timestamp = FieldValue.serverTimestamp();
        transaction.set(closingReadingRef, {
          'readingId': closingReadingRef.id,
          'meterId': oldMeterId,
          'roomId': roomId,
          'sequenceNumber': oldSequence,
          'readingDate': _timestamp(transitionDate),
          'readingWh': closingReadingWh,
          'kind': MeterReadingKind.closing.name,
          'previousReadingId': previousId,
          'previousReadingDate': _timestamp(previousDate),
          'previousReadingWh': previousWh,
          'consumptionWh': closingReadingWh - previousWh,
          'note': cleanReason,
          'billingRecordIds': <String>[],
          'correctionCount': 0,
          'lastCorrectionId': null,
          'lastCorrectedAt': null,
          'lastCorrectedBy': null,
          'createdAt': timestamp,
        });
        transaction.update(oldMeterRef, {
          'status': ElectricityMeterStatus.retired.name,
          'endedOn': _timestamp(transitionDate),
          'replacementMeterId': newMeterRef.id,
          'lastReadingId': closingReadingRef.id,
          'lastReadingDate': _timestamp(transitionDate),
          'lastReadingWh': closingReadingWh,
          'updatedAt': timestamp,
        });
        transaction.set(openingReadingRef, {
          'readingId': openingReadingRef.id,
          'meterId': newMeterRef.id,
          'roomId': roomId,
          'sequenceNumber': newSequence,
          'readingDate': _timestamp(transitionDate),
          'readingWh': newOpeningReadingWh,
          'kind': MeterReadingKind.opening.name,
          'previousReadingId': null,
          'previousReadingDate': null,
          'previousReadingWh': null,
          'consumptionWh': 0,
          'note': cleanReason,
          'billingRecordIds': <String>[],
          'correctionCount': 0,
          'lastCorrectionId': null,
          'lastCorrectedAt': null,
          'lastCorrectedBy': null,
          'createdAt': timestamp,
        });
        transaction.set(newMeterRef, {
          'meterId': newMeterRef.id,
          'roomId': roomId,
          'sequenceNumber': newSequence,
          'status': ElectricityMeterStatus.active.name,
          'startedOn': _timestamp(transitionDate),
          'endedOn': null,
          'startKind': startKind.name,
          'transitionReason': cleanReason,
          'previousMeterId': oldMeterId,
          'replacementMeterId': null,
          'lastReadingId': openingReadingRef.id,
          'lastReadingDate': _timestamp(transitionDate),
          'lastReadingWh': newOpeningReadingWh,
          'createdAt': timestamp,
          'updatedAt': timestamp,
        });
        transaction.update(stateRef, {
          'currentMeterId': newMeterRef.id,
          'lastTransitionId': newMeterRef.id,
          'updatedAt': timestamp,
        });
      });
    });
  }

  @override
  Future<void> correctLatestReading({
    required String ownerId,
    required String roomId,
    required String readingId,
    required BusinessDate expectedReadingDate,
    required int expectedReadingWh,
    required int expectedCorrectionCount,
    required BusinessDate correctedReadingDate,
    required int correctedReadingWh,
    required String reason,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(roomId, 'Room');
    _validateId(readingId, 'Reading');
    _validateRecordedDate(correctedReadingDate, 'Corrected reading date');
    _validateNonNegative(correctedReadingWh, 'Corrected meter reading');
    if (expectedCorrectionCount < 0) {
      throw const ElectricityRepositoryException(
        'The reading revision is invalid. Refresh and try again.',
        code: 'invalid-argument',
        isConflict: true,
      );
    }
    final cleanReason = _correctionReason(reason);
    final readingRef = _readings(ownerId).doc(readingId);
    final correctionRef = _corrections(ownerId).doc();

    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final readingSnapshot = await transaction.get(readingRef);
        if (!readingSnapshot.exists) {
          throw _notFound('That meter reading no longer exists.');
        }
        final reading = readingSnapshot.data()!;
        if (reading['roomId'] != roomId || reading['readingId'] != readingId) {
          throw _integrity('The selected reading does not match this room.');
        }
        final meterId = _requiredString(reading['meterId'], 'meterId');
        final meterRef = _meters(ownerId).doc(meterId);
        final meterSnapshot = await transaction.get(meterRef);
        final meter = _activeMeterData(meterSnapshot, roomId: roomId);

        final currentDate = _businessDate(
          reading['readingDate'],
          'readingDate',
        );
        final currentWh = _nonNegativeInt(reading['readingWh'], 'readingWh');
        final currentConsumption = _nonNegativeInt(
          reading['consumptionWh'],
          'consumptionWh',
        );
        final currentCorrectionCount = _nonNegativeInt(
          reading['correctionCount'],
          'correctionCount',
        );
        if (currentDate != expectedReadingDate ||
            currentWh != expectedReadingWh ||
            currentCorrectionCount != expectedCorrectionCount) {
          throw const ElectricityRepositoryException(
            'This reading changed while the correction was open. The latest values have been reloaded.',
            code: 'correction-conflict',
            isConflict: true,
          );
        }
        if (_requiredString(meter['lastReadingId'], 'lastReadingId') !=
            readingId) {
          throw const ElectricityRepositoryException(
            'Only the latest reading can be corrected. A newer reading now exists.',
            code: 'reading-not-latest',
            isConflict: true,
          );
        }
        final locks = _stringList(
          reading['billingRecordIds'],
          'billingRecordIds',
        );
        if (locks.isNotEmpty) {
          throw const ElectricityRepositoryException(
            'This reading is already used by an electricity bill and is read-only.',
            code: 'reading-already-billed',
            isConflict: true,
          );
        }

        final kind = _enumValue(
          MeterReadingKind.values,
          reading['kind'],
          'kind',
        );
        final sequence = _positiveInt(
          reading['sequenceNumber'],
          'sequenceNumber',
        );
        final initialBaseline =
            kind == MeterReadingKind.opening &&
            sequence == 1 &&
            meter['startKind'] == ElectricityMeterStartKind.initial.name &&
            meter['previousMeterId'] == null;
        final regularReading =
            kind == MeterReadingKind.regular ||
            kind == MeterReadingKind.intermediate;
        if (!initialBaseline && !regularReading) {
          throw const ElectricityRepositoryException(
            'This sequence reading is preserved and cannot be corrected in place.',
            code: 'unsupported-reading-correction',
          );
        }

        final BusinessDate? previousDate;
        final int? previousWh;
        final int correctedConsumption;
        if (initialBaseline) {
          previousDate = null;
          previousWh = null;
          correctedConsumption = 0;
        } else {
          previousDate = _businessDate(
            reading['previousReadingDate'],
            'previousReadingDate',
          );
          previousWh = _nonNegativeInt(
            reading['previousReadingWh'],
            'previousReadingWh',
          );
          if (!correctedReadingDate.isAfter(previousDate)) {
            throw ElectricityRepositoryException(
              'Corrected date must be after $previousDate.',
              code: 'reading-not-chronological',
            );
          }
          if (correctedReadingWh < previousWh) {
            throw const ElectricityRepositoryException(
              'The corrected meter reading cannot be lower than the preceding reading.',
              code: 'negative-consumption',
            );
          }
          correctedConsumption = correctedReadingWh - previousWh;
        }
        if (correctedReadingDate == currentDate &&
            correctedReadingWh == currentWh) {
          throw const ElectricityRepositoryException(
            'Change the reading date, meter value, or both before confirming.',
            code: 'no-correction-change',
          );
        }

        final meterStartedOn = _businessDate(meter['startedOn'], 'startedOn');
        final meterLastDate = _businessDate(
          meter['lastReadingDate'],
          'lastReadingDate',
        );
        final meterLastWh = _nonNegativeInt(
          meter['lastReadingWh'],
          'lastReadingWh',
        );
        if (meterLastDate != currentDate || meterLastWh != currentWh) {
          throw _integrity('The meter head does not match its latest reading.');
        }

        final timestamp = FieldValue.serverTimestamp();
        transaction.update(readingRef, {
          'readingDate': _timestamp(correctedReadingDate),
          'readingWh': correctedReadingWh,
          'consumptionWh': correctedConsumption,
          'correctionCount': currentCorrectionCount + 1,
          'lastCorrectionId': correctionRef.id,
          'lastCorrectedAt': timestamp,
          'lastCorrectedBy': ownerId,
        });
        transaction.update(meterRef, {
          if (initialBaseline) 'startedOn': _timestamp(correctedReadingDate),
          'lastReadingDate': _timestamp(correctedReadingDate),
          'lastReadingWh': correctedReadingWh,
          'updatedAt': timestamp,
        });
        transaction.set(correctionRef, {
          'correctionId': correctionRef.id,
          'ownerId': ownerId,
          'roomId': roomId,
          'meterId': meterId,
          'readingId': readingId,
          'sequenceNumber': sequence,
          'kind': kind.name,
          'before': {
            'readingDate': _timestamp(currentDate),
            'readingWh': currentWh,
            'consumptionWh': currentConsumption,
            'meterStartedOn': _timestamp(meterStartedOn),
            'meterLastReadingDate': _timestamp(meterLastDate),
            'meterLastReadingWh': meterLastWh,
          },
          'after': {
            'readingDate': _timestamp(correctedReadingDate),
            'readingWh': correctedReadingWh,
            'consumptionWh': correctedConsumption,
            'meterStartedOn': _timestamp(
              initialBaseline ? correctedReadingDate : meterStartedOn,
            ),
            'meterLastReadingDate': _timestamp(correctedReadingDate),
            'meterLastReadingWh': correctedReadingWh,
          },
          'reason': cleanReason,
          'correctedBy': ownerId,
          'createdAt': timestamp,
        });
      });
    });
  }

  @override
  Future<void> insertHistoricalReading({
    required String ownerId,
    required String roomId,
    required String meterId,
    required String predecessorReadingId,
    required BusinessDate expectedPredecessorDate,
    required int expectedPredecessorWh,
    required String successorReadingId,
    required BusinessDate expectedSuccessorDate,
    required int expectedSuccessorWh,
    required BusinessDate readingDate,
    required int readingWh,
    required String reason,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(roomId, 'Room');
    _validateId(meterId, 'Meter');
    _validateId(predecessorReadingId, 'Preceding reading');
    _validateId(successorReadingId, 'Following reading');
    _validateRecordedDate(readingDate, 'Missing reading date');
    _validateNonNegative(readingWh, 'Missing meter reading');
    final cleanReason = _correctionReason(reason);
    if (!readingDate.isAfter(expectedPredecessorDate) ||
        !readingDate.isBefore(expectedSuccessorDate)) {
      throw ElectricityRepositoryException(
        'The missing reading date must be after $expectedPredecessorDate and before $expectedSuccessorDate.',
        code: 'historical-reading-not-between',
      );
    }
    if (readingWh < expectedPredecessorWh || readingWh > expectedSuccessorWh) {
      throw ElectricityRepositoryException(
        'The missing value must be from $expectedPredecessorWh to $expectedSuccessorWh Wh.',
        code: 'historical-reading-out-of-range',
      );
    }

    final predecessorRef = _readings(ownerId).doc(predecessorReadingId);
    final successorRef = _readings(ownerId).doc(successorReadingId);
    final insertedRef = _readings(ownerId).doc();
    final insertionRef = _insertions(ownerId).doc(insertedRef.id);
    final stateRef = _states(ownerId).doc(roomId);
    final meterRef = _meters(ownerId).doc(meterId);

    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final stateSnapshot = await transaction.get(stateRef);
        final meterSnapshot = await transaction.get(meterRef);
        final predecessorSnapshot = await transaction.get(predecessorRef);
        final successorSnapshot = await transaction.get(successorRef);
        if (!stateSnapshot.exists ||
            !meterSnapshot.exists ||
            !predecessorSnapshot.exists ||
            !successorSnapshot.exists) {
          throw _notFound(
            'The meter history changed. Refresh before adding the missing reading.',
          );
        }
        final state = stateSnapshot.data()!;
        _activeMeterData(meterSnapshot, roomId: roomId);
        final predecessor = predecessorSnapshot.data()!;
        final successor = successorSnapshot.data()!;
        if (state['currentMeterId'] != meterId ||
            predecessor['meterId'] != meterId ||
            successor['meterId'] != meterId ||
            predecessor['roomId'] != roomId ||
            successor['roomId'] != roomId) {
          throw const ElectricityRepositoryException(
            'Only the active room meter can receive a missing historical reading.',
            code: 'historical-reading-inactive-meter',
            isConflict: true,
          );
        }
        final predecessorDate = _businessDate(
          predecessor['readingDate'],
          'predecessor.readingDate',
        );
        final predecessorWh = _nonNegativeInt(
          predecessor['readingWh'],
          'predecessor.readingWh',
        );
        final successorDate = _businessDate(
          successor['readingDate'],
          'successor.readingDate',
        );
        final successorWh = _nonNegativeInt(
          successor['readingWh'],
          'successor.readingWh',
        );
        if (predecessorDate != expectedPredecessorDate ||
            predecessorWh != expectedPredecessorWh ||
            successorDate != expectedSuccessorDate ||
            successorWh != expectedSuccessorWh ||
            successor['previousReadingId'] != predecessorReadingId ||
            successor['previousReadingDate'] !=
                _timestamp(expectedPredecessorDate) ||
            successor['previousReadingWh'] != expectedPredecessorWh) {
          throw const ElectricityRepositoryException(
            'The meter history changed while this form was open. Refresh and try again.',
            code: 'historical-reading-conflict',
            isConflict: true,
          );
        }
        final predecessorLocks = _stringList(
          predecessor['billingRecordIds'],
          'predecessor.billingRecordIds',
        );
        final successorLocks = _stringList(
          successor['billingRecordIds'],
          'successor.billingRecordIds',
        );
        if (predecessorLocks.isNotEmpty || successorLocks.isNotEmpty) {
          throw const ElectricityRepositoryException(
            'A saved bill already uses this interval, so a reading cannot be inserted here.',
            code: 'historical-reading-billed',
            isConflict: true,
          );
        }
        if (!readingDate.isAfter(predecessorDate) ||
            !readingDate.isBefore(successorDate) ||
            readingWh < predecessorWh ||
            readingWh > successorWh) {
          throw const ElectricityRepositoryException(
            'The missing reading must stay between the surrounding dates and meter values.',
            code: 'historical-reading-out-of-range',
          );
        }
        final sequence = _positiveInt(
          predecessor['sequenceNumber'],
          'sequenceNumber',
        );
        if (successor['sequenceNumber'] != sequence) {
          throw _integrity('The surrounding readings use different sequences.');
        }
        final timestamp = FieldValue.serverTimestamp();
        transaction.set(insertedRef, {
          'readingId': insertedRef.id,
          'meterId': meterId,
          'roomId': roomId,
          'sequenceNumber': sequence,
          'readingDate': _timestamp(readingDate),
          'readingWh': readingWh,
          'kind': MeterReadingKind.intermediate.name,
          'previousReadingId': predecessorReadingId,
          'previousReadingDate': _timestamp(predecessorDate),
          'previousReadingWh': predecessorWh,
          'consumptionWh': readingWh - predecessorWh,
          'note': cleanReason,
          'billingRecordIds': <String>[],
          'correctionCount': 0,
          'lastCorrectionId': null,
          'lastCorrectedAt': null,
          'lastCorrectedBy': null,
          'createdAt': timestamp,
        });
        transaction.update(successorRef, {
          'previousReadingId': insertedRef.id,
          'previousReadingDate': _timestamp(readingDate),
          'previousReadingWh': readingWh,
          'consumptionWh': successorWh - readingWh,
        });
        transaction.set(insertionRef, {
          'insertionId': insertionRef.id,
          'ownerId': ownerId,
          'roomId': roomId,
          'meterId': meterId,
          'insertedReadingId': insertedRef.id,
          'predecessorReadingId': predecessorReadingId,
          'successorReadingId': successorReadingId,
          'readingDate': _timestamp(readingDate),
          'readingWh': readingWh,
          'reason': cleanReason,
          'createdBy': ownerId,
          'createdAt': timestamp,
        });
      });
    });
  }

  @override
  Future<String> createReadingBatchDraft({
    required String ownerId,
    required BusinessDate effectiveDate,
    required DateTime effectiveAt,
    required int rateMicropesosPerKwh,
    required List<ElectricityBatchRoomSource> rooms,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateBatchHeader(
      effectiveDate: effectiveDate,
      effectiveAt: effectiveAt,
      rateMicropesosPerKwh: rateMicropesosPerKwh,
    );
    if (rooms.isEmpty || rooms.length > 100) {
      throw const ElectricityRepositoryException(
        'A reading batch must contain at least one configured room.',
        code: 'invalid-argument',
      );
    }
    final roomIds = <String>{};
    for (final room in rooms) {
      _validateId(room.roomId, 'Room');
      _validateId(room.meterId, 'Meter');
      _validateId(room.previousReadingId, 'Previous reading');
      if (!roomIds.add(room.roomId) ||
          room.roomName.trim().isEmpty ||
          room.roomName.length > 120 ||
          room.sequence < 1 ||
          room.previousReadingWh < 0) {
        throw const ElectricityRepositoryException(
          'The batch contains invalid or duplicate room data.',
          code: 'invalid-argument',
        );
      }
    }
    final batchRef = _batches(ownerId).doc();
    final batchReference = _batchReference(effectiveDate, batchRef.id);
    final entries = rooms.map((room) {
      final readingId = _readings(ownerId).doc().id;
      return ElectricityReadingBatchEntry(
        roomId: room.roomId,
        roomName: room.roomName.trim(),
        meterId: room.meterId,
        sequence: room.sequence,
        previousReadingId: room.previousReadingId,
        previousReadingDate: room.previousReadingDate,
        previousReadingWh: room.previousReadingWh,
        targetReadingId: readingId,
        status: ElectricityBatchEntryStatus.pending,
        currentReadingWh: null,
        actualReadAt: null,
        readingId: null,
        consumptionWh: 0,
        chargeCentavos: 0,
        exclusionReason: null,
      );
    }).toList();
    await _guard(() async {
      await batchRef.set({
        'batchId': batchRef.id,
        'batchReference': batchReference,
        'status': ElectricityReadingBatchStatus.draft.name,
        'effectiveDate': _timestamp(effectiveDate),
        'effectiveAt': Timestamp.fromDate(effectiveAt.toUtc()),
        'rateMicropesosPerKwh': rateMicropesosPerKwh,
        'entries': entries.map(_batchEntryToMap).toList(),
        'roomCount': entries.length,
        'pendingCount': entries.length,
        'recordedCount': 0,
        'excludedCount': 0,
        'totalConsumptionWh': 0,
        'totalChargeCentavos': 0,
        'version': 1,
        'lastLinkId': null,
        'createdBy': ownerId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'finalizedAt': null,
        'usedAt': null,
        'voidReason': null,
        'voidedAt': null,
      });
    });
    return batchRef.id;
  }

  @override
  Future<void> updateReadingBatchDraft({
    required String ownerId,
    required String batchId,
    required int expectedVersion,
    required BusinessDate effectiveDate,
    required DateTime effectiveAt,
    required int rateMicropesosPerKwh,
    required List<ElectricityBatchEntryDraft> entries,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(batchId, 'Batch');
    _validateBatchHeader(
      effectiveDate: effectiveDate,
      effectiveAt: effectiveAt,
      rateMicropesosPerKwh: rateMicropesosPerKwh,
    );
    final inputByRoom = <String, ElectricityBatchEntryDraft>{};
    for (final entry in entries) {
      if (inputByRoom.containsKey(entry.roomId)) {
        throw const ElectricityRepositoryException(
          'A room appears more than once in this batch.',
          code: 'invalid-argument',
        );
      }
      inputByRoom[entry.roomId] = entry;
      final reason = entry.exclusionReason?.trim();
      if (reason != null &&
          reason.isNotEmpty &&
          (reason.length < 3 || reason.length > _maximumNoteLength)) {
        throw const ElectricityRepositoryException(
          'An excluded room requires a reason from 3 to 500 characters.',
          code: 'invalid-argument',
        );
      }
      if (entry.actualReadAt != null &&
          entry.actualReadAt!.toUtc().isAfter(DateTime.now().toUtc())) {
        throw const ElectricityRepositoryException(
          'An actual reading time cannot be in the future.',
          code: 'invalid-argument',
        );
      }
    }
    final batchRef = _batches(ownerId).doc(batchId);
    await _guard(
      () => _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(batchRef);
        if (!snapshot.exists) {
          throw _notFound('That reading batch no longer exists.');
        }
        final batch = _batchFromData(snapshot.id, snapshot.data()!);
        if (!batch.canEdit || batch.version != expectedVersion) {
          throw const ElectricityRepositoryException(
            'The batch changed after it was opened. Refresh and try again.',
            code: 'aborted',
            isConflict: true,
          );
        }
        if (inputByRoom.length != batch.entries.length) {
          throw const ElectricityRepositoryException(
            'Every batch room must be included or explicitly excluded.',
            code: 'invalid-argument',
          );
        }
        final updated = batch.entries.map((entry) {
          final input = inputByRoom[entry.roomId];
          if (input == null) {
            throw const ElectricityRepositoryException(
              'Every batch room must be included or explicitly excluded.',
              code: 'invalid-argument',
            );
          }
          if (entry.status == ElectricityBatchEntryStatus.recorded) {
            return entry;
          }
          if (!input.isExcluded &&
              input.currentReadingWh != null &&
              input.currentReadingWh! < entry.previousReadingWh) {
            throw ElectricityRepositoryException(
              '${entry.roomName} reading cannot be below its previous reading.',
              code: 'negative-consumption',
            );
          }
          if (!input.isExcluded &&
              !effectiveDate.isAfter(entry.previousReadingDate)) {
            throw ElectricityRepositoryException(
              '${entry.roomName} already has a reading on or after this batch date.',
              code: 'reading-not-chronological',
              isConflict: true,
            );
          }
          return entry.withDraft(
            draft: input,
            rateMicropesosPerKwh: rateMicropesosPerKwh,
          );
        }).toList();
        final totals = _batchTotals(updated);
        transaction.update(batchRef, {
          'effectiveDate': _timestamp(effectiveDate),
          'effectiveAt': Timestamp.fromDate(effectiveAt.toUtc()),
          'rateMicropesosPerKwh': rateMicropesosPerKwh,
          'entries': updated.map(_batchEntryToMap).toList(),
          'pendingCount': totals.pendingCount,
          'recordedCount': totals.recordedCount,
          'excludedCount': totals.excludedCount,
          'totalConsumptionWh': totals.totalConsumptionWh,
          'totalChargeCentavos': totals.totalChargeCentavos,
          'version': batch.version + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }),
    );
  }

  @override
  Future<void> finalizeReadingBatch({
    required String ownerId,
    required String batchId,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(batchId, 'Batch');
    final batchRef = _batches(ownerId).doc(batchId);

    while (true) {
      final snapshot = await _guard(() => batchRef.get());
      if (!snapshot.exists) {
        throw _notFound('That reading batch no longer exists.');
      }
      final current = _batchFromData(snapshot.id, snapshot.data()!);
      if (current.status == ElectricityReadingBatchStatus.finalized) return;
      if (!current.canEdit) {
        throw const ElectricityRepositoryException(
          'Only a draft reading batch can be finalized.',
          code: 'failed-precondition',
        );
      }
      final next = current.entries
          .where((entry) => entry.status == ElectricityBatchEntryStatus.pending)
          .firstOrNull;
      if (next == null) break;
      if (next.currentReadingWh == null) {
        throw ElectricityRepositoryException(
          'Enter ${next.roomName}\'s reading or exclude the room with a reason.',
          code: 'incomplete-batch',
        );
      }
      await _appendBatchReading(
        ownerId: ownerId,
        batchId: batchId,
        targetRoomId: next.roomId,
      );
    }

    await _guard(
      () => _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(batchRef);
        if (!snapshot.exists) {
          throw _notFound('That reading batch no longer exists.');
        }
        final batch = _batchFromData(snapshot.id, snapshot.data()!);
        if (batch.status == ElectricityReadingBatchStatus.finalized) return;
        if (!batch.canEdit ||
            batch.pendingCount != 0 ||
            batch.recordedCount + batch.excludedCount != batch.roomCount) {
          throw const ElectricityRepositoryException(
            'Complete or exclude every room before finalizing.',
            code: 'incomplete-batch',
          );
        }
        transaction.update(batchRef, {
          'status': ElectricityReadingBatchStatus.finalized.name,
          'version': batch.version + 1,
          'finalizedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }),
    );
  }

  Future<void> _appendBatchReading({
    required String ownerId,
    required String batchId,
    required String targetRoomId,
  }) async {
    final batchRef = _batches(ownerId).doc(batchId);
    await _guard(
      () => _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(batchRef);
        if (!snapshot.exists) {
          throw _notFound('That reading batch no longer exists.');
        }
        final batch = _batchFromData(snapshot.id, snapshot.data()!);
        if (!batch.canEdit) {
          throw const ElectricityRepositoryException(
            'The batch is no longer editable.',
            code: 'failed-precondition',
          );
        }
        final index = batch.entries.indexWhere(
          (entry) => entry.roomId == targetRoomId,
        );
        if (index < 0) throw _integrity('A batch room is missing.');
        final entry = batch.entries[index];
        if (entry.status != ElectricityBatchEntryStatus.pending) return;
        final currentWh = entry.currentReadingWh;
        if (currentWh == null ||
            currentWh < entry.previousReadingWh ||
            !batch.effectiveDate.isAfter(entry.previousReadingDate)) {
          throw ElectricityRepositoryException(
            '${entry.roomName} has an invalid reading.',
            code: 'invalid-reading',
          );
        }
        final meterRef = _meters(ownerId).doc(entry.meterId);
        final readingRef = _readings(ownerId).doc(entry.targetReadingId);
        final linkRef = _batchLinks(ownerId).doc(entry.targetReadingId);
        final meter = await transaction.get(meterRef);
        final reading = await transaction.get(readingRef);
        final data = _activeMeterData(meter, roomId: entry.roomId);
        final matchesHead =
            data['lastReadingId'] == entry.previousReadingId &&
            _businessDate(data['lastReadingDate'], 'lastReadingDate') ==
                entry.previousReadingDate &&
            _nonNegativeInt(data['lastReadingWh'], 'lastReadingWh') ==
                entry.previousReadingWh &&
            _positiveInt(data['sequenceNumber'], 'sequenceNumber') ==
                entry.sequence;
        if (!matchesHead || reading.exists) {
          throw ElectricityRepositoryException(
            '${entry.roomName} received another reading. Refresh the batch before continuing.',
            code: 'aborted',
            isConflict: true,
          );
        }
        final consumption = currentWh - entry.previousReadingWh;
        final charge = ElectricityValues.chargeCentavos(
          consumptionWh: consumption,
          rateMicropesosPerKwh: batch.rateMicropesosPerKwh,
        );
        final timestamp = FieldValue.serverTimestamp();
        transaction.set(readingRef, {
          'readingId': readingRef.id,
          'meterId': entry.meterId,
          'roomId': entry.roomId,
          'sequenceNumber': entry.sequence,
          'readingDate': _timestamp(batch.effectiveDate),
          'readingWh': currentWh,
          'kind': MeterReadingKind.regular.name,
          'previousReadingId': entry.previousReadingId,
          'previousReadingDate': _timestamp(entry.previousReadingDate),
          'previousReadingWh': entry.previousReadingWh,
          'consumptionWh': consumption,
          'note': 'Electricity batch ${batch.batchReference}',
          'billingRecordIds': <String>[],
          'correctionCount': 0,
          'lastCorrectionId': null,
          'lastCorrectedAt': null,
          'lastCorrectedBy': null,
          'createdAt': timestamp,
        });
        transaction.update(meterRef, {
          'lastReadingId': readingRef.id,
          'lastReadingDate': _timestamp(batch.effectiveDate),
          'lastReadingWh': currentWh,
          'updatedAt': timestamp,
        });
        transaction.set(linkRef, {
          'linkId': linkRef.id,
          'batchId': batch.batchId,
          'batchReference': batch.batchReference,
          'readingId': readingRef.id,
          'roomId': entry.roomId,
          'meterId': entry.meterId,
          'readingDate': _timestamp(batch.effectiveDate),
          'readingWh': currentWh,
          'consumptionWh': consumption,
          'chargeCentavos': charge,
          'createdBy': ownerId,
          'createdAt': timestamp,
        });
        final entries = [...batch.entries];
        entries[index] = ElectricityReadingBatchEntry(
          roomId: entry.roomId,
          roomName: entry.roomName,
          meterId: entry.meterId,
          sequence: entry.sequence,
          previousReadingId: entry.previousReadingId,
          previousReadingDate: entry.previousReadingDate,
          previousReadingWh: entry.previousReadingWh,
          targetReadingId: entry.targetReadingId,
          status: ElectricityBatchEntryStatus.recorded,
          currentReadingWh: currentWh,
          actualReadAt: entry.actualReadAt ?? batch.effectiveAt,
          readingId: readingRef.id,
          consumptionWh: consumption,
          chargeCentavos: charge,
          exclusionReason: null,
        );
        final totals = _batchTotals(entries);
        transaction.update(batchRef, {
          'entries': entries.map(_batchEntryToMap).toList(),
          'pendingCount': totals.pendingCount,
          'recordedCount': totals.recordedCount,
          'excludedCount': totals.excludedCount,
          'totalConsumptionWh': totals.totalConsumptionWh,
          'totalChargeCentavos': totals.totalChargeCentavos,
          'version': batch.version + 1,
          'lastLinkId': linkRef.id,
          'updatedAt': timestamp,
        });
      }),
    );
  }

  @override
  Future<void> voidReadingBatch({
    required String ownerId,
    required String batchId,
    required String reason,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(batchId, 'Batch');
    final cleanReason = reason.trim();
    if (cleanReason.length < 3 || cleanReason.length > _maximumNoteLength) {
      throw const ElectricityRepositoryException(
        'Enter a void reason from 3 to 500 characters.',
        code: 'invalid-argument',
      );
    }
    final batchRef = _batches(ownerId).doc(batchId);
    final voidRef = _batchVoids(ownerId).doc(batchId);
    await _guard(
      () => _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(batchRef);
        final existingVoid = await transaction.get(voidRef);
        if (!snapshot.exists) {
          throw _notFound('That reading batch no longer exists.');
        }
        final batch = _batchFromData(snapshot.id, snapshot.data()!);
        if (!batch.canVoid || existingVoid.exists) {
          throw const ElectricityRepositoryException(
            'Only a finalized, unused batch can be voided once.',
            code: 'failed-precondition',
          );
        }
        final timestamp = FieldValue.serverTimestamp();
        transaction.update(batchRef, {
          'status': ElectricityReadingBatchStatus.voided.name,
          'version': batch.version + 1,
          'voidReason': cleanReason,
          'voidedAt': timestamp,
          'updatedAt': timestamp,
        });
        transaction.set(voidRef, {
          'voidId': batchId,
          'batchId': batchId,
          'batchReference': batch.batchReference,
          'reason': cleanReason,
          'voidedBy': ownerId,
          'createdAt': timestamp,
        });
      }),
    );
  }

  @override
  Future<String> recordBillingSnapshot({
    required String ownerId,
    required ElectricityCalculationResult result,
    bool roomBillingSource = false,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateBillingResult(result);
    final recordId = roomBillingSource
        ? '${result.startDate}_${result.endDateExclusive}_roomV2'
        : '${result.startDate}_${result.endDateExclusive}';
    final recordRef = _records(ownerId).doc(recordId);
    final expectedSources = _expectedSourceReadings(result);
    final sourceReadingIds = expectedSources.keys.toList()..sort();
    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final house = await transaction.get(_house(ownerId));
        final existing = await transaction.get(recordRef);
        if (!house.exists) {
          throw _notFound('The boarding house could not be found.');
        }
        if (existing.exists) {
          throw const ElectricityRepositoryException(
            'An electricity record already exists for these dates.',
            code: 'billing-record-already-exists',
            isConflict: true,
          );
        }
        final sourceLocks = <String, List<String>>{};
        for (final readingId in sourceReadingIds) {
          final expected = expectedSources[readingId]!;
          final snapshot = await transaction.get(
            _readings(ownerId).doc(readingId),
          );
          if (!snapshot.exists) {
            throw _integrity('A source meter reading is missing.');
          }
          final data = snapshot.data()!;
          final matchesSnapshot =
              data['readingId'] == expected.readingId &&
              data['roomId'] == expected.roomId &&
              data['meterId'] == expected.meterId &&
              _businessDate(data['readingDate'], 'readingDate') ==
                  expected.readingDate &&
              _nonNegativeInt(data['readingWh'], 'readingWh') ==
                  expected.readingWh;
          if (!matchesSnapshot) {
            throw const ElectricityRepositoryException(
              'A source reading changed after this calculation was prepared. Recalculate the period and try again.',
              code: 'billing-source-conflict',
              isConflict: true,
            );
          }
          _nonNegativeInt(data['correctionCount'], 'correctionCount');
          final locks = _stringList(
            data['billingRecordIds'],
            'billingRecordIds',
          );
          sourceLocks[readingId] = locks;
        }
        transaction.set(recordRef, {
          'recordId': recordId,
          'startDate': _timestamp(result.startDate),
          'endDateExclusive': _timestamp(result.endDateExclusive),
          'rateMicropesosPerKwh': result.rateMicropesosPerKwh,
          'totalConsumptionWh': result.totalConsumptionWh,
          'totalBaseChargeCentavos': result.totalBaseChargeCentavos,
          'totalAdjustmentCentavos': result.totalAdjustmentsCentavos,
          'totalChargeCentavos': result.totalChargeCentavos,
          'totalAllocatedCentavos': result.totalAllocatedCentavos,
          'totalUnallocatedCentavos': result.totalUnallocatedCentavos,
          'roomCharges': result.roomCharges.map(_roomChargeToMap).toList(),
          'sourceReadingIds': sourceReadingIds,
          'warnings': result.warnings,
          'createdBy': ownerId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        for (final readingId in sourceReadingIds) {
          final currentLocks = sourceLocks[readingId]!;
          if (currentLocks.contains(recordId)) {
            throw const ElectricityRepositoryException(
              'A source reading is already locked by this billing record.',
              code: 'billing-source-conflict',
              isConflict: true,
            );
          }
          final locks = [...currentLocks, recordId];
          transaction.update(_readings(ownerId).doc(readingId), {
            'billingRecordIds': locks,
          });
        }
      });
    });
    return recordId;
  }

  Map<String, dynamic> _batchEntryToMap(ElectricityReadingBatchEntry value) => {
    'roomId': value.roomId,
    'roomName': value.roomName,
    'meterId': value.meterId,
    'sequenceNumber': value.sequence,
    'previousReadingId': value.previousReadingId,
    'previousReadingDate': _timestamp(value.previousReadingDate),
    'previousReadingWh': value.previousReadingWh,
    'targetReadingId': value.targetReadingId,
    'status': value.status.name,
    'currentReadingWh': value.currentReadingWh,
    'actualReadAt': value.actualReadAt == null
        ? null
        : Timestamp.fromDate(value.actualReadAt!.toUtc()),
    'readingId': value.readingId,
    'consumptionWh': value.consumptionWh,
    'chargeCentavos': value.chargeCentavos,
    'exclusionReason': value.exclusionReason,
  };

  ElectricityReadingBatch _batchFromData(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final id = _requiredString(data['batchId'], 'batchId');
    if (id != documentId) {
      throw _schema('An electricity batch ID is inconsistent.');
    }
    final entries = _mapList(
      data['entries'],
      'entries',
    ).map(_batchEntryFromMap).toList();
    final roomCount = _nonNegativeInt(data['roomCount'], 'roomCount');
    final pending = _nonNegativeInt(data['pendingCount'], 'pendingCount');
    final recorded = _nonNegativeInt(data['recordedCount'], 'recordedCount');
    final excluded = _nonNegativeInt(data['excludedCount'], 'excludedCount');
    if (roomCount != entries.length ||
        pending + recorded + excluded != roomCount) {
      throw _schema('An electricity batch has inconsistent room counts.');
    }
    return ElectricityReadingBatch(
      batchId: id,
      batchReference: _requiredString(data['batchReference'], 'batchReference'),
      status: _enumValue(
        ElectricityReadingBatchStatus.values,
        data['status'],
        'status',
      ),
      effectiveDate: _businessDate(data['effectiveDate'], 'effectiveDate'),
      effectiveAt: _dateTime(data['effectiveAt'], 'effectiveAt'),
      rateMicropesosPerKwh: _nonNegativeInt(
        data['rateMicropesosPerKwh'],
        'rateMicropesosPerKwh',
      ),
      entries: entries,
      roomCount: roomCount,
      pendingCount: pending,
      recordedCount: recorded,
      excludedCount: excluded,
      totalConsumptionWh: _nonNegativeInt(
        data['totalConsumptionWh'],
        'totalConsumptionWh',
      ),
      totalChargeCentavos: _nonNegativeInt(
        data['totalChargeCentavos'],
        'totalChargeCentavos',
      ),
      version: _positiveInt(data['version'], 'version'),
      lastLinkId: _optionalString(data['lastLinkId'], 'lastLinkId'),
      createdAt: _dateTime(data['createdAt'], 'createdAt'),
      updatedAt: _dateTime(data['updatedAt'], 'updatedAt'),
      finalizedAt: _optionalDateTime(data['finalizedAt'], 'finalizedAt'),
      usedAt: _optionalDateTime(data['usedAt'], 'usedAt'),
      voidReason: _optionalString(data['voidReason'], 'voidReason'),
      voidedAt: _optionalDateTime(data['voidedAt'], 'voidedAt'),
    );
  }

  ElectricityReadingBatchEntry _batchEntryFromMap(Map<String, dynamic> data) =>
      ElectricityReadingBatchEntry(
        roomId: _requiredString(data['roomId'], 'roomId'),
        roomName: _requiredString(data['roomName'], 'roomName'),
        meterId: _requiredString(data['meterId'], 'meterId'),
        sequence: _positiveInt(data['sequenceNumber'], 'sequenceNumber'),
        previousReadingId: _requiredString(
          data['previousReadingId'],
          'previousReadingId',
        ),
        previousReadingDate: _businessDate(
          data['previousReadingDate'],
          'previousReadingDate',
        ),
        previousReadingWh: _nonNegativeInt(
          data['previousReadingWh'],
          'previousReadingWh',
        ),
        targetReadingId: _requiredString(
          data['targetReadingId'],
          'targetReadingId',
        ),
        status: _enumValue(
          ElectricityBatchEntryStatus.values,
          data['status'],
          'status',
        ),
        currentReadingWh: _optionalNonNegativeInt(
          data['currentReadingWh'],
          'currentReadingWh',
        ),
        actualReadAt: _optionalDateTime(data['actualReadAt'], 'actualReadAt'),
        readingId: _optionalString(data['readingId'], 'readingId'),
        consumptionWh: _nonNegativeInt(data['consumptionWh'], 'consumptionWh'),
        chargeCentavos: _nonNegativeInt(
          data['chargeCentavos'],
          'chargeCentavos',
        ),
        exclusionReason: _optionalString(
          data['exclusionReason'],
          'exclusionReason',
        ),
      );

  _BatchTotals _batchTotals(List<ElectricityReadingBatchEntry> entries) {
    var pending = 0;
    var recorded = 0;
    var excluded = 0;
    var consumption = 0;
    var charge = 0;
    for (final entry in entries) {
      switch (entry.status) {
        case ElectricityBatchEntryStatus.pending:
          pending++;
        case ElectricityBatchEntryStatus.recorded:
          recorded++;
        case ElectricityBatchEntryStatus.excluded:
          excluded++;
      }
      consumption += entry.consumptionWh;
      charge += entry.chargeCentavos;
    }
    return _BatchTotals(
      pendingCount: pending,
      recordedCount: recorded,
      excludedCount: excluded,
      totalConsumptionWh: consumption,
      totalChargeCentavos: charge,
    );
  }

  void _validateBatchHeader({
    required BusinessDate effectiveDate,
    required DateTime effectiveAt,
    required int rateMicropesosPerKwh,
  }) {
    _validateRecordedDate(effectiveDate, 'Batch reading date');
    if (effectiveAt.toUtc().isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 1)),
        ) ||
        rateMicropesosPerKwh <= 0 ||
        rateMicropesosPerKwh > ElectricityValues.maximumRateMicropesosPerKwh) {
      throw const ElectricityRepositoryException(
        'Enter a valid batch time and electricity rate.',
        code: 'invalid-argument',
      );
    }
  }

  String _batchReference(BusinessDate date, String id) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final suffix = id.substring(0, id.length < 4 ? id.length : 4).toUpperCase();
    return 'EB-${date.year}-$month-$day-$suffix';
  }

  Map<String, dynamic> _roomChargeToMap(RoomElectricityCharge value) => {
    'roomId': value.roomId,
    'roomName': value.roomName,
    'segments': value.segments.map(_segmentToMap).toList(),
    'adjustments': value.adjustments.map(_adjustmentToMap).toList(),
    'boarderShares': value.boarderShares.map(_shareToMap).toList(),
    'consumptionWh': value.consumptionWh,
    'baseChargeCentavos': value.baseChargeCentavos,
    'adjustmentCentavos': value.adjustmentCentavos,
    'finalChargeCentavos': value.finalChargeCentavos,
    'allocatedCentavos': value.allocatedCentavos,
    'unallocatedCentavos': value.unallocatedCentavos,
    'hasEstimatedShares': value.hasEstimatedShares,
  };

  Map<String, dynamic> _segmentToMap(ElectricitySegmentSnapshot value) => {
    'meterId': value.meterId,
    'sequenceNumber': value.sequence,
    'previousReadingId': value.previousReadingId,
    'currentReadingId': value.currentReadingId,
    'startDate': _timestamp(value.startDate),
    'endDateExclusive': _timestamp(value.endDateExclusive),
    'previousReadingWh': value.previousReadingWh,
    'currentReadingWh': value.currentReadingWh,
    'consumptionWh': value.consumptionWh,
    'chargeCentavos': value.chargeCentavos,
    'boarderShares': value.boarderShares.map(_shareToMap).toList(),
    'unallocatedCentavos': value.unallocatedCentavos,
    'allocationQuality': value.allocationQuality.name,
  };

  Map<String, dynamic> _shareToMap(BoarderElectricityShare value) => {
    'boarderId': value.boarderId,
    'boarderName': value.boarderName,
    'occupancyIds': value.occupancyIds,
    'occupancyDays': value.occupancyDays,
    'amountCentavos': value.amountCentavos,
    'isEstimated': value.isEstimated,
  };

  Map<String, dynamic> _adjustmentToMap(ElectricityAdjustment value) => {
    'adjustmentId': value.adjustmentId,
    'roomId': value.roomId,
    'type': value.type.name,
    'magnitudeCentavos': value.magnitudeCentavos,
    'reason': value.reason,
    'adjustmentDate': _timestamp(value.adjustmentDate),
  };

  Map<String, _ExpectedSourceReading> _expectedSourceReadings(
    ElectricityCalculationResult result,
  ) {
    final expected = <String, _ExpectedSourceReading>{};
    void add(_ExpectedSourceReading candidate) {
      final existing = expected[candidate.readingId];
      if (existing != null && !existing.matches(candidate)) {
        throw const ElectricityRepositoryException(
          'The calculation contains inconsistent source meter readings.',
          code: 'invalid-billing-sources',
        );
      }
      expected[candidate.readingId] = candidate;
    }

    for (final room in result.roomCharges) {
      for (final segment in room.segments) {
        add(
          _ExpectedSourceReading(
            readingId: segment.previousReadingId,
            roomId: room.roomId,
            meterId: segment.meterId,
            readingDate: segment.startDate,
            readingWh: segment.previousReadingWh,
          ),
        );
        add(
          _ExpectedSourceReading(
            readingId: segment.currentReadingId,
            roomId: room.roomId,
            meterId: segment.meterId,
            readingDate: segment.endDateExclusive,
            readingWh: segment.currentReadingWh,
          ),
        );
      }
    }
    if (expected.isEmpty) {
      throw const ElectricityRepositoryException(
        'The electricity calculation has no source meter readings.',
        code: 'invalid-billing-sources',
      );
    }
    return expected;
  }

  RoomMeterState _stateFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final roomId = _requiredString(data['roomId'], 'roomId');
    if (roomId != document.id) {
      throw _schema('A meter state ID is inconsistent.');
    }
    return RoomMeterState(
      roomId: roomId,
      currentMeterId: _requiredString(data['currentMeterId'], 'currentMeterId'),
      lastTransitionId: _optionalString(
        data['lastTransitionId'],
        'lastTransitionId',
      ),
      createdAt: _dateTime(data['createdAt'], 'createdAt'),
      updatedAt: _dateTime(data['updatedAt'], 'updatedAt'),
    );
  }

  ElectricityMeter _meterFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final meterId = _requiredString(data['meterId'], 'meterId');
    if (meterId != document.id) throw _schema('A meter ID is inconsistent.');
    return ElectricityMeter(
      meterId: meterId,
      roomId: _requiredString(data['roomId'], 'roomId'),
      sequence: _positiveInt(data['sequenceNumber'], 'sequenceNumber'),
      status: _enumValue(
        ElectricityMeterStatus.values,
        data['status'],
        'status',
      ),
      startedOn: _businessDate(data['startedOn'], 'startedOn'),
      endedOn: _optionalBusinessDate(data['endedOn'], 'endedOn'),
      startKind: _enumValue(
        ElectricityMeterStartKind.values,
        data['startKind'],
        'startKind',
      ),
      transitionReason: _optionalString(
        data['transitionReason'],
        'transitionReason',
      ),
      previousMeterId: _optionalString(
        data['previousMeterId'],
        'previousMeterId',
      ),
      replacementMeterId: _optionalString(
        data['replacementMeterId'],
        'replacementMeterId',
      ),
      lastReadingId: _requiredString(data['lastReadingId'], 'lastReadingId'),
      lastReadingDate: _businessDate(
        data['lastReadingDate'],
        'lastReadingDate',
      ),
      lastReadingWh: _nonNegativeInt(data['lastReadingWh'], 'lastReadingWh'),
      createdAt: _dateTime(data['createdAt'], 'createdAt'),
      updatedAt: _dateTime(data['updatedAt'], 'updatedAt'),
    );
  }

  MeterReading _readingFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final readingId = _requiredString(data['readingId'], 'readingId');
    if (readingId != document.id) {
      throw _schema('A reading ID is inconsistent.');
    }
    const trackingFields = {
      'billingRecordIds',
      'correctionCount',
      'lastCorrectionId',
      'lastCorrectedAt',
      'lastCorrectedBy',
    };
    final presentTrackingFields = trackingFields.where(data.containsKey).length;
    if (presentTrackingFields != 0 &&
        presentTrackingFields != trackingFields.length) {
      throw _schema('Reading correction metadata is incomplete.');
    }
    final lockTrackingComplete = presentTrackingFields == trackingFields.length;
    return MeterReading(
      readingId: readingId,
      meterId: _requiredString(data['meterId'], 'meterId'),
      roomId: _requiredString(data['roomId'], 'roomId'),
      sequence: _positiveInt(data['sequenceNumber'], 'sequenceNumber'),
      readingDate: _businessDate(data['readingDate'], 'readingDate'),
      readingWh: _nonNegativeInt(data['readingWh'], 'readingWh'),
      kind: _enumValue(MeterReadingKind.values, data['kind'], 'kind'),
      previousReadingId: _optionalString(
        data['previousReadingId'],
        'previousReadingId',
      ),
      previousReadingDate: _optionalBusinessDate(
        data['previousReadingDate'],
        'previousReadingDate',
      ),
      previousReadingWh: _optionalNonNegativeInt(
        data['previousReadingWh'],
        'previousReadingWh',
      ),
      consumptionWh: _nonNegativeInt(data['consumptionWh'], 'consumptionWh'),
      note: _optionalString(data['note'], 'note'),
      createdAt: _dateTime(data['createdAt'], 'createdAt'),
      billingRecordIds: lockTrackingComplete
          ? _stringList(data['billingRecordIds'], 'billingRecordIds')
          : const [],
      lockTrackingComplete: lockTrackingComplete,
      correctionCount: lockTrackingComplete
          ? _nonNegativeInt(data['correctionCount'], 'correctionCount')
          : 0,
      lastCorrectionId: lockTrackingComplete
          ? _optionalString(data['lastCorrectionId'], 'lastCorrectionId')
          : null,
      lastCorrectedAt: lockTrackingComplete
          ? _optionalDateTime(data['lastCorrectedAt'], 'lastCorrectedAt')
          : null,
      lastCorrectedBy: lockTrackingComplete
          ? _optionalString(data['lastCorrectedBy'], 'lastCorrectedBy')
          : null,
    );
  }

  MeterReadingCorrection _correctionFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final correctionId = _requiredString(data['correctionId'], 'correctionId');
    if (correctionId != document.id) {
      throw _schema('A meter reading correction ID is inconsistent.');
    }
    return MeterReadingCorrection(
      correctionId: correctionId,
      ownerId: _requiredString(data['ownerId'], 'ownerId'),
      roomId: _requiredString(data['roomId'], 'roomId'),
      meterId: _requiredString(data['meterId'], 'meterId'),
      readingId: _requiredString(data['readingId'], 'readingId'),
      sequence: _positiveInt(data['sequenceNumber'], 'sequenceNumber'),
      kind: _enumValue(MeterReadingKind.values, data['kind'], 'kind'),
      before: _correctionVersionFromMap(_requiredMap(data['before'], 'before')),
      after: _correctionVersionFromMap(_requiredMap(data['after'], 'after')),
      reason: _requiredString(data['reason'], 'reason'),
      correctedBy: _requiredString(data['correctedBy'], 'correctedBy'),
      createdAt: _dateTime(data['createdAt'], 'createdAt'),
    );
  }

  MeterReadingCorrectionVersion _correctionVersionFromMap(
    Map<String, dynamic> data,
  ) => MeterReadingCorrectionVersion(
    readingDate: _businessDate(data['readingDate'], 'readingDate'),
    readingWh: _nonNegativeInt(data['readingWh'], 'readingWh'),
    consumptionWh: _nonNegativeInt(data['consumptionWh'], 'consumptionWh'),
    meterStartedOn: _businessDate(data['meterStartedOn'], 'meterStartedOn'),
    meterLastReadingDate: _businessDate(
      data['meterLastReadingDate'],
      'meterLastReadingDate',
    ),
    meterLastReadingWh: _nonNegativeInt(
      data['meterLastReadingWh'],
      'meterLastReadingWh',
    ),
  );

  ElectricityBillingRecord _recordFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final id = _requiredString(data['recordId'], 'recordId');
    if (id != document.id) {
      throw _schema('A billing record ID is inconsistent.');
    }
    final sourceLocksComplete = data.containsKey('sourceReadingIds');
    return ElectricityBillingRecord(
      billingRecordId: id,
      startDate: _businessDate(data['startDate'], 'startDate'),
      endDateExclusive: _businessDate(
        data['endDateExclusive'],
        'endDateExclusive',
      ),
      rateMicropesosPerKwh: _positiveInt(
        data['rateMicropesosPerKwh'],
        'rateMicropesosPerKwh',
      ),
      roomCharges: _mapList(
        data['roomCharges'],
        'roomCharges',
      ).map(_roomChargeFromMap).toList(),
      totalConsumptionWh: _nonNegativeInt(
        data['totalConsumptionWh'],
        'totalConsumptionWh',
      ),
      totalBaseChargeCentavos: _nonNegativeInt(
        data['totalBaseChargeCentavos'],
        'totalBaseChargeCentavos',
      ),
      totalAdjustmentsCentavos: _integer(
        data['totalAdjustmentCentavos'],
        'totalAdjustmentCentavos',
      ),
      totalChargeCentavos: _nonNegativeInt(
        data['totalChargeCentavos'],
        'totalChargeCentavos',
      ),
      totalAllocatedCentavos: _nonNegativeInt(
        data['totalAllocatedCentavos'],
        'totalAllocatedCentavos',
      ),
      totalUnallocatedCentavos: _nonNegativeInt(
        data['totalUnallocatedCentavos'],
        'totalUnallocatedCentavos',
      ),
      warnings: _stringList(data['warnings'], 'warnings'),
      recordedAt: _dateTime(data['createdAt'], 'createdAt'),
      sourceReadingIds: sourceLocksComplete
          ? _stringList(data['sourceReadingIds'], 'sourceReadingIds')
          : const [],
      sourceLocksComplete: sourceLocksComplete,
    );
  }

  RoomElectricityCharge _roomChargeFromMap(Map<String, dynamic> data) =>
      RoomElectricityCharge(
        roomId: _requiredString(data['roomId'], 'roomId'),
        roomName: _requiredString(data['roomName'], 'roomName'),
        segments: _mapList(
          data['segments'],
          'segments',
        ).map(_segmentFromMap).toList(),
        adjustments: _mapList(
          data['adjustments'],
          'adjustments',
        ).map(_adjustmentFromMap).toList(),
        boarderShares: _mapList(
          data['boarderShares'],
          'boarderShares',
        ).map(_shareFromMap).toList(),
        consumptionWh: _nonNegativeInt(data['consumptionWh'], 'consumptionWh'),
        baseChargeCentavos: _nonNegativeInt(
          data['baseChargeCentavos'],
          'baseChargeCentavos',
        ),
        adjustmentCentavos: _integer(
          data['adjustmentCentavos'],
          'adjustmentCentavos',
        ),
        finalChargeCentavos: _nonNegativeInt(
          data['finalChargeCentavos'],
          'finalChargeCentavos',
        ),
        allocatedCentavos: _nonNegativeInt(
          data['allocatedCentavos'],
          'allocatedCentavos',
        ),
        unallocatedCentavos: _nonNegativeInt(
          data['unallocatedCentavos'],
          'unallocatedCentavos',
        ),
        hasEstimatedShares: _boolean(
          data['hasEstimatedShares'],
          'hasEstimatedShares',
        ),
      );

  ElectricitySegmentSnapshot _segmentFromMap(Map<String, dynamic> data) =>
      ElectricitySegmentSnapshot(
        meterId: _requiredString(data['meterId'], 'meterId'),
        sequence: _positiveInt(data['sequenceNumber'], 'sequenceNumber'),
        previousReadingId: _requiredString(
          data['previousReadingId'],
          'previousReadingId',
        ),
        currentReadingId: _requiredString(
          data['currentReadingId'],
          'currentReadingId',
        ),
        startDate: _businessDate(data['startDate'], 'startDate'),
        endDateExclusive: _businessDate(
          data['endDateExclusive'],
          'endDateExclusive',
        ),
        previousReadingWh: _nonNegativeInt(
          data['previousReadingWh'],
          'previousReadingWh',
        ),
        currentReadingWh: _nonNegativeInt(
          data['currentReadingWh'],
          'currentReadingWh',
        ),
        consumptionWh: _nonNegativeInt(data['consumptionWh'], 'consumptionWh'),
        chargeCentavos: _nonNegativeInt(
          data['chargeCentavos'],
          'chargeCentavos',
        ),
        boarderShares: _mapList(
          data['boarderShares'],
          'boarderShares',
        ).map(_shareFromMap).toList(),
        unallocatedCentavos: _nonNegativeInt(
          data['unallocatedCentavos'],
          'unallocatedCentavos',
        ),
        allocationQuality: _enumValue(
          ElectricityAllocationQuality.values,
          data['allocationQuality'],
          'allocationQuality',
        ),
      );

  BoarderElectricityShare _shareFromMap(Map<String, dynamic> data) =>
      BoarderElectricityShare(
        boarderId: _requiredString(data['boarderId'], 'boarderId'),
        boarderName: _requiredString(data['boarderName'], 'boarderName'),
        occupancyIds: _stringList(data['occupancyIds'], 'occupancyIds'),
        occupancyDays: _nonNegativeInt(data['occupancyDays'], 'occupancyDays'),
        amountCentavos: _nonNegativeInt(
          data['amountCentavos'],
          'amountCentavos',
        ),
        isEstimated: _boolean(data['isEstimated'], 'isEstimated'),
      );

  ElectricityAdjustment _adjustmentFromMap(Map<String, dynamic> data) =>
      ElectricityAdjustment(
        adjustmentId: _requiredString(data['adjustmentId'], 'adjustmentId'),
        roomId: _requiredString(data['roomId'], 'roomId'),
        type: _enumValue(
          ElectricityAdjustmentType.values,
          data['type'],
          'type',
        ),
        magnitudeCentavos: _positiveInt(
          data['magnitudeCentavos'],
          'magnitudeCentavos',
        ),
        reason: _requiredString(data['reason'], 'reason'),
        adjustmentDate: _businessDate(data['adjustmentDate'], 'adjustmentDate'),
      );

  Map<String, dynamic> _activeMeterData(
    DocumentSnapshot<Map<String, dynamic>> meter, {
    required String roomId,
  }) {
    if (!meter.exists) {
      throw _integrity('The room\'s current meter is missing.');
    }
    final data = meter.data()!;
    if (data['roomId'] != roomId ||
        data['status'] != ElectricityMeterStatus.active.name) {
      throw _integrity('The room\'s meter state is inconsistent.');
    }
    return data;
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on ElectricityRepositoryException {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapFirestoreException(error);
    }
  }

  Stream<T> _mappedStream<T>(Stream<T> source) => source.transform(
    StreamTransformer<T, T>.fromHandlers(
      handleError: (Object error, StackTrace stack, EventSink<T> sink) {
        sink.addError(
          error is FirebaseException ? _mapFirestoreException(error) : error,
          stack,
        );
      },
    ),
  );

  ElectricityRepositoryException _mapFirestoreException(
    FirebaseException error,
  ) {
    final offline =
        error.code == 'unavailable' ||
        error.code == 'network-request-failed' ||
        error.code == 'deadline-exceeded';
    final conflict =
        error.code == 'aborted' ||
        error.code == 'already-exists' ||
        error.code == 'failed-precondition';
    final message = switch ((offline, conflict, error.code)) {
      (true, _, _) => 'This change could not be confirmed while offline. Reconnect and try again.',
      (_, true, _) => 'Another meter change happened at the same time. Refresh and try again.',
      (_, _, 'permission-denied') =>
        'You do not have permission to change this boarding house.',
      _ => 'The electricity record could not be saved. Please try again.',
    };
    return ElectricityRepositoryException(
      message,
      code: error.code,
      isOffline: offline,
      isConflict: conflict,
    );
  }

  void _validateRecordedDate(BusinessDate value, String label) {
    if (value.isAfter(BusinessDate.todayInManila())) {
      throw ElectricityRepositoryException(
        '$label cannot be in the future.',
        code: 'future-date',
      );
    }
  }

  void _validateBillingResult(ElectricityCalculationResult result) {
    final totalsAreValid =
        result.totalConsumptionWh >= 0 &&
        result.totalConsumptionWh <= ElectricityValues.maximumMeterReadingWh &&
        result.totalBaseChargeCentavos >= 0 &&
        result.totalBaseChargeCentavos <=
            ElectricityValues.maximumBillingTotalCentavos &&
        result.totalAdjustmentsCentavos.abs() <=
            ElectricityValues.maximumBillingTotalCentavos &&
        result.totalChargeCentavos >= 0 &&
        result.totalChargeCentavos <=
            ElectricityValues.maximumBillingTotalCentavos &&
        result.totalAllocatedCentavos >= 0 &&
        result.totalAllocatedCentavos <=
            ElectricityValues.maximumBillingTotalCentavos &&
        result.totalUnallocatedCentavos >= 0 &&
        result.totalUnallocatedCentavos <=
            ElectricityValues.maximumBillingTotalCentavos &&
        result.totalBaseChargeCentavos + result.totalAdjustmentsCentavos ==
            result.totalChargeCentavos &&
        result.totalAllocatedCentavos + result.totalUnallocatedCentavos ==
            result.totalChargeCentavos;
    if (!result.startDate.isBefore(result.endDateExclusive) ||
        result.endDateExclusive.isAfter(BusinessDate.todayInManila()) ||
        result.rateMicropesosPerKwh < 1 ||
        result.rateMicropesosPerKwh >
            ElectricityValues.maximumRateMicropesosPerKwh ||
        result.roomCharges.length > 500 ||
        result.warnings.length > 100 ||
        !totalsAreValid) {
      throw const ElectricityRepositoryException(
        'The electricity calculation is outside the supported billing limits.',
        code: 'invalid-argument',
      );
    }
  }

  void _validateNonNegative(int value, String label) {
    if (value < 0 || value > ElectricityValues.maximumMeterReadingWh) {
      throw ElectricityRepositoryException(
        '$label must be within the supported range.',
        code: 'invalid-argument',
      );
    }
  }

  void _validateId(String value, String label) {
    if (value.trim().isEmpty || value.contains('/')) {
      throw ElectricityRepositoryException(
        '$label identifier is invalid.',
        code: 'invalid-argument',
      );
    }
  }

  String _requiredText(String value, String label) {
    final clean = value.trim();
    if (clean.isEmpty || clean.length > _maximumNoteLength) {
      throw ElectricityRepositoryException(
        '$label is required and must be $_maximumNoteLength characters or fewer.',
        code: 'invalid-argument',
      );
    }
    return clean;
  }

  String _correctionReason(String value) {
    final clean = value.trim();
    if (clean.length < 3 || clean.length > _maximumNoteLength) {
      throw const ElectricityRepositoryException(
        'Enter a correction reason between 3 and 500 characters.',
        code: 'invalid-correction-reason',
      );
    }
    return clean;
  }

  String? _optionalText(String? value, String label) {
    if (value == null) return null;
    final clean = value.trim();
    if (clean.length > _maximumNoteLength) {
      throw ElectricityRepositoryException(
        '$label must be $_maximumNoteLength characters or fewer.',
        code: 'invalid-argument',
      );
    }
    return clean.isEmpty ? null : clean;
  }

  String _requiredString(Object? value, String field) {
    if (value is! String || value.isEmpty) throw _schema('$field is invalid.');
    return value;
  }

  String? _optionalString(Object? value, String field) {
    if (value == null) return null;
    if (value is! String) throw _schema('$field is invalid.');
    return value;
  }

  int _integer(Object? value, String field) {
    if (value is! int) throw _schema('$field is invalid.');
    return value;
  }

  int _nonNegativeInt(Object? value, String field) {
    final result = _integer(value, field);
    if (result < 0) throw _schema('$field is negative.');
    return result;
  }

  int? _optionalNonNegativeInt(Object? value, String field) {
    if (value == null) return null;
    return _nonNegativeInt(value, field);
  }

  int _positiveInt(Object? value, String field) {
    final result = _integer(value, field);
    if (result <= 0) throw _schema('$field must be positive.');
    return result;
  }

  bool _boolean(Object? value, String field) {
    if (value is! bool) throw _schema('$field is invalid.');
    return value;
  }

  DateTime _dateTime(Object? value, String field) {
    if (value is! Timestamp) throw _schema('$field is invalid.');
    return value.toDate().toUtc();
  }

  DateTime? _optionalDateTime(Object? value, String field) =>
      value == null ? null : _dateTime(value, field);

  BusinessDate _businessDate(Object? value, String field) {
    if (value is! Timestamp) throw _schema('$field is invalid.');
    try {
      return BusinessDate.fromUtcDateTime(value.toDate());
    } on FormatException {
      throw _schema('$field is not a date-only value.');
    }
  }

  BusinessDate? _optionalBusinessDate(Object? value, String field) =>
      value == null ? null : _businessDate(value, field);

  E _enumValue<E extends Enum>(List<E> values, Object? value, String field) {
    if (value is! String) throw _schema('$field is invalid.');
    for (final item in values) {
      if (item.name == value) return item;
    }
    throw _schema('$field has an unsupported value.');
  }

  List<Map<String, dynamic>> _mapList(Object? value, String field) {
    if (value is! List) throw _schema('$field is invalid.');
    return value.map((item) {
      if (item is! Map) throw _schema('$field contains invalid data.');
      return Map<String, dynamic>.from(item);
    }).toList();
  }

  Map<String, dynamic> _requiredMap(Object? value, String field) {
    if (value is! Map) throw _schema('$field is invalid.');
    return Map<String, dynamic>.from(value);
  }

  List<String> _stringList(Object? value, String field) {
    if (value is! List || value.any((item) => item is! String)) {
      throw _schema('$field is invalid.');
    }
    return value.cast<String>();
  }

  Timestamp _timestamp(BusinessDate value) =>
      Timestamp.fromDate(value.asUtcDateTime);

  ElectricityRepositoryException _notFound(String message) =>
      ElectricityRepositoryException(message, code: 'not-found');

  ElectricityRepositoryException _integrity(String message) =>
      ElectricityRepositoryException(
        '$message Refresh before making more changes.',
        code: 'data-integrity',
        isConflict: true,
      );

  ElectricityRepositoryException _schema(String message) =>
      ElectricityRepositoryException(
        '$message Refresh the app. If it continues, contact support.',
        code: 'invalid-data',
      );
}

class _BatchTotals {
  const _BatchTotals({
    required this.pendingCount,
    required this.recordedCount,
    required this.excludedCount,
    required this.totalConsumptionWh,
    required this.totalChargeCentavos,
  });

  final int pendingCount;
  final int recordedCount;
  final int excludedCount;
  final int totalConsumptionWh;
  final int totalChargeCentavos;
}

class _ExpectedSourceReading {
  const _ExpectedSourceReading({
    required this.readingId,
    required this.roomId,
    required this.meterId,
    required this.readingDate,
    required this.readingWh,
  });

  final String readingId;
  final String roomId;
  final String meterId;
  final BusinessDate readingDate;
  final int readingWh;

  bool matches(_ExpectedSourceReading other) =>
      readingId == other.readingId &&
      roomId == other.roomId &&
      meterId == other.meterId &&
      readingDate == other.readingDate &&
      readingWh == other.readingWh;
}
