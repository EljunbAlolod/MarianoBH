import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../property_management/domain/business_date.dart';
import '../domain/rent_models.dart';
import '../domain/rent_repository.dart';
import '../domain/rent_values.dart';
import '../domain/rent_cycle_models.dart';
import '../domain/rent_cycle_service.dart';

class FirestoreRentRepository implements RentRepository {
  FirestoreRentRepository(this._firestore);

  static const primaryHouseId = 'primary';
  static const settingsId = 'config';

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _house(String ownerId) => _firestore
      .collection('owners')
      .doc(ownerId)
      .collection('boardingHouses')
      .doc(primaryHouseId);

  DocumentReference<Map<String, dynamic>> _settings(String ownerId) =>
      _house(ownerId).collection('rentSettings').doc(settingsId);

  CollectionReference<Map<String, dynamic>> _records(String ownerId) =>
      _house(ownerId).collection('rentBillingRecords');

  CollectionReference<Map<String, dynamic>> _agreements(String ownerId) =>
      _house(ownerId).collection('rentAgreements');

  CollectionReference<Map<String, dynamic>> _cycles(String ownerId) =>
      _house(ownerId).collection('rentCycles');

  CollectionReference<Map<String, dynamic>> _cycleControls(String ownerId) =>
      _house(ownerId).collection('rentCycleControls');

  CollectionReference<Map<String, dynamic>> _payments(String ownerId) =>
      _house(ownerId).collection('rentPayments');

  CollectionReference<Map<String, dynamic>> _resolutions(String ownerId) =>
      _house(ownerId).collection('rentExtraStayResolutions');

  @override
  Stream<List<RentAgreement>> watchAgreements(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _agreements(ownerId).snapshots().map((snapshot) {
        final values = snapshot.docs.map(_agreementFromDocument).toList();
        values.sort((a, b) => b.startDate.compareTo(a.startDate));
        return values;
      }),
    );
  }

  @override
  Stream<List<RentCycle>> watchCycles(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _cycles(ownerId).snapshots().map((snapshot) {
        final values = snapshot.docs.map(_cycleFromDocument).toList();
        values.sort((a, b) => b.coverageStart.compareTo(a.coverageStart));
        return values;
      }),
    );
  }

  @override
  Stream<List<RentCycleControl>> watchCycleControls(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _cycleControls(ownerId)
          .snapshots()
          .map((snapshot) => snapshot.docs.map(_controlFromDocument).toList()),
    );
  }

  @override
  Stream<List<RentPayment>> watchPayments(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _payments(ownerId).snapshots().map((snapshot) {
        final values = snapshot.docs.map(_paymentFromDocument).toList();
        values.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return values;
      }),
    );
  }

  @override
  Stream<List<RentExtraStayResolution>> watchExtraStayResolutions(
    String ownerId,
  ) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _resolutions(ownerId).snapshots().map((snapshot) {
        final values = snapshot.docs.map(_resolutionFromDocument).toList();
        values.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return values;
      }),
    );
  }

  @override
  Stream<RentSettings> watchSettings(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _settings(ownerId).snapshots().map((snapshot) {
        if (!snapshot.exists) return RentSettings.defaults();
        final data = snapshot.data()!;
        if (snapshot.id != settingsId || data['settingsId'] != settingsId) {
          throw _schema('Rent settings have an inconsistent identifier.');
        }
        _dateTime(data['createdAt'], 'createdAt');
        _dateTime(data['updatedAt'], 'updatedAt');
        return RentSettings(
          mode: _enumValue(RentBillingMode.values, data['mode'], 'mode'),
        );
      }),
    );
  }

  @override
  Stream<List<RentBillingRecord>> watchBillingRecords(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _records(ownerId).snapshots().map((snapshot) {
        final records = snapshot.docs.map(_recordFromDocument).toList();
        records.sort((a, b) {
          final byEnd = b.endDateExclusive.compareTo(a.endDateExclusive);
          return byEnd != 0 ? byEnd : b.rentRecordId.compareTo(a.rentRecordId);
        });
        return records;
      }),
    );
  }

  @override
  Future<void> saveSettings({
    required String ownerId,
    required RentSettings settings,
  }) async {
    _validateId(ownerId, 'Owner');
    final reference = _settings(ownerId);
    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final house = await transaction.get(_house(ownerId));
        final existing = await transaction.get(reference);
        if (!house.exists) {
          throw _notFound('The boarding house could not be found.');
        }
        final timestamp = FieldValue.serverTimestamp();
        if (existing.exists) {
          transaction.update(reference, {
            'mode': settings.mode.name,
            'updatedAt': timestamp,
          });
        } else {
          transaction.set(reference, {
            'settingsId': settingsId,
            'mode': settings.mode.name,
            'createdAt': timestamp,
            'updatedAt': timestamp,
          });
        }
      });
    });
  }

  @override
  Future<String> recordBillingSnapshot({
    required String ownerId,
    required RentCalculationResult result,
    bool roomBillingSource = false,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateResult(result);
    final recordId = roomBillingSource
        ? '${result.startDate}_${result.endDateExclusive}_roomV2'
        : '${result.startDate}_${result.endDateExclusive}';
    final reference = _records(ownerId).doc(recordId);
    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final house = await transaction.get(_house(ownerId));
        final existing = await transaction.get(reference);
        if (!house.exists) {
          throw _notFound('The boarding house could not be found.');
        }
        if (existing.exists) {
          throw const RentRepositoryException(
            'A rent record already exists for these dates.',
            code: 'rent-record-already-exists',
            isConflict: true,
          );
        }
        transaction.set(reference, {
          'recordId': recordId,
          'startDate': _timestamp(result.startDate),
          'endDateExclusive': _timestamp(result.endDateExclusive),
          'mode': result.mode.name,
          'periodDays': result.periodDays,
          'totalRentCentavos': result.totalRentCentavos,
          'totalAdjustmentCentavos': result.totalAdjustmentCentavos,
          'grandTotalCentavos': result.grandTotalCentavos,
          'roomAllocations': result.roomAllocations.map(_roomToMap).toList(),
          'boarderCharges': result.boarderCharges.map(_boarderToMap).toList(),
          'adjustments': result.adjustments.map(_adjustmentToMap).toList(),
          'warnings': result.warnings,
          'createdBy': ownerId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
    });
    return recordId;
  }

  @override
  Future<String> createAgreement({
    required String ownerId,
    required String occupancyId,
    required int monthlyRentCentavos,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(occupancyId, 'Occupancy');
    if (monthlyRentCentavos <= 0 ||
        monthlyRentCentavos > RentValues.maximumAmountCentavos) {
      throw const RentRepositoryException(
        'Enter a monthly rent greater than zero.',
        code: 'invalid-argument',
      );
    }
    final agreementRef = _agreements(ownerId).doc(occupancyId);
    final occupancyRef = _house(ownerId)
        .collection('occupancies')
        .doc(occupancyId);
    await _guard(
      () => _firestore.runTransaction((transaction) async {
        final occupancy = await transaction.get(occupancyRef);
        final existing = await transaction.get(agreementRef);
        if (!occupancy.exists) {
          throw _notFound('That occupancy no longer exists.');
        }
        if (existing.exists) {
          throw const RentRepositoryException(
            'A rent agreement already exists for this occupancy.',
            code: 'already-exists',
            isConflict: true,
          );
        }
        final occupancyData = occupancy.data()!;
        final boarderId = _string(occupancyData['boarderId'], 'boarderId');
        final roomId = _string(occupancyData['roomId'], 'roomId');
        final boarder = await transaction.get(
          _house(ownerId).collection('boarders').doc(boarderId),
        );
        final room = await transaction.get(
          _house(ownerId).collection('rooms').doc(roomId),
        );
        if (!boarder.exists || !room.exists) {
          throw _notFound('The boarder or room could not be found.');
        }
        final startDate = _businessDate(
          occupancyData['moveInDate'],
          'moveInDate',
        );
        transaction.set(agreementRef, {
          'agreementId': occupancyId,
          'occupancyId': occupancyId,
          'boarderId': boarderId,
          'boarderName': _string(boarder.data()!['fullName'], 'fullName'),
          'roomId': roomId,
          'roomName': _string(room.data()!['roomName'], 'roomName'),
          'startDate': _timestamp(startDate),
          'anchorDay': startDate.day,
          'monthlyRentCentavos': monthlyRentCentavos,
          'createdBy': ownerId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }),
    );
    return occupancyId;
  }

  @override
  Future<int> createDueCycles({
    required String ownerId,
    required RentAgreement agreement,
    required BusinessDate throughDate,
  }) async {
    _validateId(ownerId, 'Owner');
    if (throughDate.isAfter(BusinessDate.todayInManila())) {
      throw const RentRepositoryException(
        'Rent cycles cannot be created through a future date.',
        code: 'future-date',
      );
    }
    final calculated = const RentCycleService().completedCycles(
      agreement,
      throughDate: throughDate,
    );
    if (calculated.isEmpty) return 0;
    var created = 0;
    for (final cycle in calculated) {
      await _guard(
        () => _firestore.runTransaction((transaction) async {
          final storedAgreement = await transaction.get(
            _agreements(ownerId).doc(agreement.agreementId),
          );
          if (!storedAgreement.exists ||
              storedAgreement.data()!['monthlyRentCentavos'] !=
                  agreement.monthlyRentCentavos) {
            throw const RentRepositoryException(
              'The rent agreement changed. Refresh and try again.',
              code: 'aborted',
              isConflict: true,
            );
          }
          final cycleRef = _cycles(ownerId).doc(cycle.cycleId);
          final controlRef = _cycleControls(ownerId).doc(cycle.cycleId);
          final existing = await transaction.get(cycleRef);
          if (existing.exists) return;
          transaction.set(cycleRef, _cycleToCreateMap(cycle, ownerId));
          transaction.set(controlRef, {
            'cycleId': cycle.cycleId,
            'totalPaidCentavos': 0,
            'lastPaymentId': null,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          created++;
        }),
      );
    }
    return created;
  }

  @override
  Future<String> recordPayment({
    required String ownerId,
    required String cycleId,
    required int expectedPaidCentavos,
    required int amountCentavos,
    required BusinessDate receivedOn,
    String? note,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(cycleId, 'Rent cycle');
    if (amountCentavos <= 0 ||
        receivedOn.isAfter(BusinessDate.todayInManila())) {
      throw const RentRepositoryException(
        'Enter a valid payment amount and date.',
        code: 'invalid-argument',
      );
    }
    final cleanNote = note?.trim();
    if ((cleanNote?.length ?? 0) > 500) {
      throw const RentRepositoryException(
        'Payment note must be 500 characters or fewer.',
        code: 'invalid-argument',
      );
    }
    final paymentRef = _payments(ownerId).doc();
    await _guard(
      () => _firestore.runTransaction((transaction) async {
        final cycleRef = _cycles(ownerId).doc(cycleId);
        final controlRef = _cycleControls(ownerId).doc(cycleId);
        final cycle = await transaction.get(cycleRef);
        final control = await transaction.get(controlRef);
        if (!cycle.exists || !control.exists) {
          throw _notFound('That rent cycle no longer exists.');
        }
        final paid = _nonNegative(
          control.data()!['totalPaidCentavos'],
          'totalPaidCentavos',
        );
        final total = _nonNegative(
          cycle.data()!['amountCentavos'],
          'amountCentavos',
        );
        if (paid != expectedPaidCentavos) {
          throw const RentRepositoryException(
            'Another payment was recorded. Refresh and try again.',
            code: 'aborted',
            isConflict: true,
          );
        }
        if (amountCentavos > total - paid) {
          throw const RentRepositoryException(
            'Payment cannot exceed the outstanding balance.',
            code: 'invalid-argument',
          );
        }
        transaction.set(paymentRef, {
          'paymentId': paymentRef.id,
          'cycleId': cycleId,
          'agreementId': _string(cycle.data()!['agreementId'], 'agreementId'),
          'amountCentavos': amountCentavos,
          'note': cleanNote?.isEmpty == true ? null : cleanNote,
          'receivedOn': _timestamp(receivedOn),
          'createdBy': ownerId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(controlRef, {
          'totalPaidCentavos': paid + amountCentavos,
          'lastPaymentId': paymentRef.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }),
    );
    return paymentRef.id;
  }

  @override
  Future<String> resolveExtraStay({
    required String ownerId,
    required RentAgreement agreement,
    required BusinessDate moveOutDate,
    required ExtraStayDecision decision,
    required int amountCentavos,
    required String note,
  }) async {
    _validateId(ownerId, 'Owner');
    final cleanNote = note.trim();
    if (cleanNote.length < 3 || cleanNote.length > 500) {
      throw const RentRepositoryException(
        'Enter a decision note from 3 to 500 characters.',
        code: 'invalid-argument',
      );
    }
    final expectedAmount = switch (decision) {
      ExtraStayDecision.waived => 0,
      ExtraStayDecision.manualCharge => amountCentavos,
      ExtraStayDecision.fullCycle => agreement.monthlyRentCentavos,
    };
    if (expectedAmount < 0 ||
        (decision == ExtraStayDecision.manualCharge && expectedAmount == 0)) {
      throw const RentRepositoryException(
        'Enter a valid extra-stay amount.',
        code: 'invalid-argument',
      );
    }
    final service = const RentCycleService();
    final completed = service.completedCycles(
      agreement,
      throughDate: moveOutDate,
    );
    final extraStart = completed.isEmpty
        ? agreement.startDate
        : completed.last.coverageEndExclusive;
    if (!moveOutDate.isAfter(extraStart)) {
      throw const RentRepositoryException(
        'This occupancy does not have an unresolved extra stay.',
        code: 'invalid-argument',
      );
    }
    final resolutionRef = _resolutions(ownerId).doc(agreement.occupancyId);
    final occupancyRef = _house(ownerId)
        .collection('occupancies')
        .doc(agreement.occupancyId);
    RentCycle? chargeCycle;
    if (decision == ExtraStayDecision.manualCharge) {
      chargeCycle = RentCycle(
        cycleId: '${agreement.agreementId}_extra',
        agreementId: agreement.agreementId,
        occupancyId: agreement.occupancyId,
        boarderId: agreement.boarderId,
        boarderName: agreement.boarderName,
        roomId: agreement.roomId,
        roomName: agreement.roomName,
        kind: RentCycleKind.extraStay,
        cycleNumber: completed.length + 1,
        coverageStart: extraStart,
        coverageEndExclusive: moveOutDate,
        dueDate: moveOutDate,
        amountCentavos: expectedAmount,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    } else if (decision == ExtraStayDecision.fullCycle) {
      chargeCycle = service.monthlyCycle(agreement, completed.length + 1);
    }
    await _guard(
      () => _firestore.runTransaction((transaction) async {
        final occupancy = await transaction.get(occupancyRef);
        final existing = await transaction.get(resolutionRef);
        if (!occupancy.exists || occupancy.data()!['moveOutDate'] == null) {
          throw _notFound('The completed occupancy could not be found.');
        }
        if (_businessDate(occupancy.data()!['moveOutDate'], 'moveOutDate') !=
            moveOutDate) {
          throw const RentRepositoryException(
            'The move-out date changed. Refresh and try again.',
            code: 'aborted',
            isConflict: true,
          );
        }
        if (existing.exists) {
          throw const RentRepositoryException(
            'This extra stay already has a recorded decision.',
            code: 'already-exists',
            isConflict: true,
          );
        }
        DocumentReference<Map<String, dynamic>>? cycleRef;
        DocumentReference<Map<String, dynamic>>? controlRef;
        if (chargeCycle != null) {
          cycleRef = _cycles(ownerId).doc(chargeCycle.cycleId);
          controlRef = _cycleControls(ownerId).doc(chargeCycle.cycleId);
          final existingCycle = await transaction.get(cycleRef);
          if (existingCycle.exists) {
            throw const RentRepositoryException(
              'A charge already exists for this period.',
              code: 'already-exists',
              isConflict: true,
            );
          }
        }
        transaction.set(resolutionRef, {
          'resolutionId': agreement.occupancyId,
          'agreementId': agreement.agreementId,
          'occupancyId': agreement.occupancyId,
          'boarderId': agreement.boarderId,
          'roomId': agreement.roomId,
          'extraStayStart': _timestamp(extraStart),
          'moveOutDate': _timestamp(moveOutDate),
          'decision': decision.name,
          'amountCentavos': expectedAmount,
          'note': cleanNote,
          'chargeCycleId': chargeCycle?.cycleId,
          'createdBy': ownerId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (chargeCycle != null) {
          transaction.set(cycleRef!, _cycleToCreateMap(chargeCycle, ownerId));
          transaction.set(controlRef!, {
            'cycleId': chargeCycle.cycleId,
            'totalPaidCentavos': 0,
            'lastPaymentId': null,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }),
    );
    return resolutionRef.id;
  }

  Map<String, dynamic> _cycleToCreateMap(RentCycle value, String ownerId) => {
    'cycleId': value.cycleId,
    'agreementId': value.agreementId,
    'occupancyId': value.occupancyId,
    'boarderId': value.boarderId,
    'boarderName': value.boarderName,
    'roomId': value.roomId,
    'roomName': value.roomName,
    'kind': value.kind.name,
    'cycleNumber': value.cycleNumber,
    'coverageStart': _timestamp(value.coverageStart),
    'coverageEndExclusive': _timestamp(value.coverageEndExclusive),
    'dueDate': _timestamp(value.dueDate),
    'amountCentavos': value.amountCentavos,
    'createdBy': ownerId,
    'createdAt': FieldValue.serverTimestamp(),
  };

  Map<String, dynamic> _roomToMap(RoomRentAllocation value) => {
    'roomId': value.roomId,
    'roomName': value.roomName,
    'monthlyRentCentavos': value.monthlyRentCentavos,
    'occupiedDays': value.occupiedDays,
    'personDays': value.personDays,
    'rentCentavos': value.rentCentavos,
    'boarderShares': value.boarderShares
        .map(
          (share) => {
            'boarderId': share.boarderId,
            'boarderName': share.boarderName,
            'occupancyIds': share.occupancyIds,
            'occupancyDays': share.occupancyDays,
            'rentCentavos': share.rentCentavos,
          },
        )
        .toList(),
  };

  Map<String, dynamic> _boarderToMap(BoarderRentCharge value) => {
    'boarderId': value.boarderId,
    'boarderName': value.boarderName,
    'occupancyIds': value.occupancyIds,
    'roomIds': value.roomIds,
    'occupancyDays': value.occupancyDays,
    'rentCentavos': value.rentCentavos,
    'adjustmentCentavos': value.adjustmentCentavos,
    'totalCentavos': value.totalCentavos,
  };

  Map<String, dynamic> _adjustmentToMap(BillingAdjustment value) => {
    'adjustmentId': value.adjustmentId,
    'boarderId': value.boarderId,
    'type': value.type.name,
    'amountCentavos': value.amountCentavos,
    'reason': value.reason.trim(),
    'adjustmentDate': _timestamp(value.adjustmentDate),
  };

  RentBillingRecord _recordFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final id = _string(data['recordId'], 'recordId');
    if (id != document.id) throw _schema('A rent record ID is inconsistent.');
    return RentBillingRecord(
      rentRecordId: id,
      startDate: _businessDate(data['startDate'], 'startDate'),
      endDateExclusive: _businessDate(
        data['endDateExclusive'],
        'endDateExclusive',
      ),
      mode: _enumValue(RentBillingMode.values, data['mode'], 'mode'),
      periodDays: _nonNegative(data['periodDays'], 'periodDays'),
      totalRentCentavos: _nonNegative(
        data['totalRentCentavos'],
        'totalRentCentavos',
      ),
      totalAdjustmentCentavos: _integer(
        data['totalAdjustmentCentavos'],
        'totalAdjustmentCentavos',
      ),
      grandTotalCentavos: _nonNegative(
        data['grandTotalCentavos'],
        'grandTotalCentavos',
      ),
      roomAllocations: _maps(
        data['roomAllocations'],
        'roomAllocations',
      ).map(_roomFromMap).toList(),
      boarderCharges: _maps(
        data['boarderCharges'],
        'boarderCharges',
      ).map(_boarderFromMap).toList(),
      adjustments: _maps(
        data['adjustments'],
        'adjustments',
      ).map(_adjustmentFromMap).toList(),
      warnings: _strings(data['warnings'], 'warnings'),
      recordedAt: _dateTime(data['createdAt'], 'createdAt'),
    );
  }

  RoomRentAllocation _roomFromMap(Map<String, dynamic> data) =>
      RoomRentAllocation(
        roomId: _string(data['roomId'], 'roomId'),
        roomName: _string(data['roomName'], 'roomName'),
        monthlyRentCentavos: _nonNegative(
          data['monthlyRentCentavos'],
          'monthlyRentCentavos',
        ),
        occupiedDays: _nonNegative(data['occupiedDays'], 'occupiedDays'),
        personDays: _nonNegative(data['personDays'], 'personDays'),
        rentCentavos: _nonNegative(data['rentCentavos'], 'rentCentavos'),
        boarderShares: _maps(data['boarderShares'], 'boarderShares')
            .map(
              (share) => RoomBoarderRentShare(
                boarderId: _string(share['boarderId'], 'boarderId'),
                boarderName: _string(share['boarderName'], 'boarderName'),
                occupancyIds: _strings(share['occupancyIds'], 'occupancyIds'),
                occupancyDays: _nonNegative(
                  share['occupancyDays'],
                  'occupancyDays',
                ),
                rentCentavos: _nonNegative(
                  share['rentCentavos'],
                  'rentCentavos',
                ),
              ),
            )
            .toList(),
      );

  BoarderRentCharge _boarderFromMap(Map<String, dynamic> data) =>
      BoarderRentCharge(
        boarderId: _string(data['boarderId'], 'boarderId'),
        boarderName: _string(data['boarderName'], 'boarderName'),
        occupancyIds: _strings(data['occupancyIds'], 'occupancyIds'),
        roomIds: _strings(data['roomIds'], 'roomIds'),
        occupancyDays: _nonNegative(data['occupancyDays'], 'occupancyDays'),
        rentCentavos: _nonNegative(data['rentCentavos'], 'rentCentavos'),
        adjustmentCentavos: _integer(
          data['adjustmentCentavos'],
          'adjustmentCentavos',
        ),
        totalCentavos: _nonNegative(data['totalCentavos'], 'totalCentavos'),
      );

  BillingAdjustment _adjustmentFromMap(Map<String, dynamic> data) =>
      BillingAdjustment(
        adjustmentId: _string(data['adjustmentId'], 'adjustmentId'),
        boarderId: _string(data['boarderId'], 'boarderId'),
        type: _enumValue(BillingAdjustmentType.values, data['type'], 'type'),
        amountCentavos: _nonNegative(data['amountCentavos'], 'amountCentavos'),
        reason: _string(data['reason'], 'reason'),
        adjustmentDate: _businessDate(data['adjustmentDate'], 'adjustmentDate'),
      );

  RentAgreement _agreementFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final id = _string(data['agreementId'], 'agreementId');
    if (id != document.id) {
      throw _schema('A rent agreement ID is inconsistent.');
    }
    return RentAgreement(
      agreementId: id,
      occupancyId: _string(data['occupancyId'], 'occupancyId'),
      boarderId: _string(data['boarderId'], 'boarderId'),
      boarderName: _string(data['boarderName'], 'boarderName'),
      roomId: _string(data['roomId'], 'roomId'),
      roomName: _string(data['roomName'], 'roomName'),
      startDate: _businessDate(data['startDate'], 'startDate'),
      anchorDay: _nonNegative(data['anchorDay'], 'anchorDay'),
      monthlyRentCentavos: _nonNegative(
        data['monthlyRentCentavos'],
        'monthlyRentCentavos',
      ),
      createdAt: _dateTime(data['createdAt'], 'createdAt'),
    );
  }

  RentCycle _cycleFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final id = _string(data['cycleId'], 'cycleId');
    if (id != document.id) throw _schema('A rent cycle ID is inconsistent.');
    final start = _businessDate(data['coverageStart'], 'coverageStart');
    final end = _businessDate(
      data['coverageEndExclusive'],
      'coverageEndExclusive',
    );
    if (!start.isBefore(end)) throw _schema('A rent cycle has invalid dates.');
    return RentCycle(
      cycleId: id,
      agreementId: _string(data['agreementId'], 'agreementId'),
      occupancyId: _string(data['occupancyId'], 'occupancyId'),
      boarderId: _string(data['boarderId'], 'boarderId'),
      boarderName: _string(data['boarderName'], 'boarderName'),
      roomId: _string(data['roomId'], 'roomId'),
      roomName: _string(data['roomName'], 'roomName'),
      kind: _enumValue(RentCycleKind.values, data['kind'], 'kind'),
      cycleNumber: _nonNegative(data['cycleNumber'], 'cycleNumber'),
      coverageStart: start,
      coverageEndExclusive: end,
      dueDate: _businessDate(data['dueDate'], 'dueDate'),
      amountCentavos: _nonNegative(data['amountCentavos'], 'amountCentavos'),
      createdAt: _dateTime(data['createdAt'], 'createdAt'),
    );
  }

  RentCycleControl _controlFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final id = _string(data['cycleId'], 'cycleId');
    if (id != document.id) throw _schema('A rent control ID is inconsistent.');
    return RentCycleControl(
      cycleId: id,
      totalPaidCentavos: _nonNegative(
        data['totalPaidCentavos'],
        'totalPaidCentavos',
      ),
      lastPaymentId: _optionalString(data['lastPaymentId'], 'lastPaymentId'),
      updatedAt: _dateTime(data['updatedAt'], 'updatedAt'),
    );
  }

  RentPayment _paymentFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final id = _string(data['paymentId'], 'paymentId');
    if (id != document.id) throw _schema('A rent payment ID is inconsistent.');
    return RentPayment(
      paymentId: id,
      cycleId: _string(data['cycleId'], 'cycleId'),
      agreementId: _string(data['agreementId'], 'agreementId'),
      amountCentavos: _nonNegative(data['amountCentavos'], 'amountCentavos'),
      note: _optionalString(data['note'], 'note'),
      receivedOn: _businessDate(data['receivedOn'], 'receivedOn'),
      createdBy: _string(data['createdBy'], 'createdBy'),
      createdAt: _dateTime(data['createdAt'], 'createdAt'),
    );
  }

  RentExtraStayResolution _resolutionFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final id = _string(data['resolutionId'], 'resolutionId');
    if (id != document.id) {
      throw _schema('A rent resolution ID is inconsistent.');
    }
    return RentExtraStayResolution(
      resolutionId: id,
      agreementId: _string(data['agreementId'], 'agreementId'),
      occupancyId: _string(data['occupancyId'], 'occupancyId'),
      boarderId: _string(data['boarderId'], 'boarderId'),
      roomId: _string(data['roomId'], 'roomId'),
      extraStayStart: _businessDate(data['extraStayStart'], 'extraStayStart'),
      moveOutDate: _businessDate(data['moveOutDate'], 'moveOutDate'),
      decision: _enumValue(
        ExtraStayDecision.values,
        data['decision'],
        'decision',
      ),
      amountCentavos: _nonNegative(data['amountCentavos'], 'amountCentavos'),
      note: _string(data['note'], 'note'),
      createdBy: _string(data['createdBy'], 'createdBy'),
      createdAt: _dateTime(data['createdAt'], 'createdAt'),
    );
  }

  void _validateResult(RentCalculationResult result) {
    final valid =
        result.startDate.isBefore(result.endDateExclusive) &&
        !result.endDateExclusive.isAfter(BusinessDate.todayInManila()) &&
        result.periodDays ==
            result.startDate.daysUntil(result.endDateExclusive) &&
        result.periodDays <= 366 &&
        result.totalRentCentavos >= 0 &&
        result.grandTotalCentavos >= 0 &&
        result.totalRentCentavos + result.totalAdjustmentCentavos ==
            result.grandTotalCentavos &&
        result.roomAllocations.length <= 500 &&
        result.boarderCharges.length <= 2000 &&
        result.adjustments.length <= 500 &&
        result.warnings.length <= 100;
    if (!valid ||
        result.totalRentCentavos > RentValues.maximumAmountCentavos ||
        result.grandTotalCentavos > RentValues.maximumAmountCentavos ||
        result.totalAdjustmentCentavos.abs() >
            RentValues.maximumAmountCentavos) {
      throw const RentRepositoryException(
        'The rent calculation is outside the supported billing limits.',
        code: 'invalid-argument',
      );
    }
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on RentRepositoryException {
      rethrow;
    } on FirebaseException catch (error) {
      final offline =
          error.code == 'unavailable' ||
          error.code == 'network-request-failed' ||
          error.code == 'deadline-exceeded';
      final conflict =
          error.code == 'aborted' ||
          error.code == 'already-exists' ||
          error.code == 'failed-precondition';
      throw RentRepositoryException(
        offline
            ? 'This change could not be confirmed while offline. Reconnect and try again.'
            : conflict
            ? 'Another rent-billing change happened at the same time. Refresh and try again.'
            : error.code == 'permission-denied'
            ? 'You do not have permission to change this boarding house.'
            : 'The rent record could not be saved. Please try again.',
        code: error.code,
        isOffline: offline,
        isConflict: conflict,
      );
    }
  }

  Stream<T> _mapped<T>(Stream<T> source) => source.transform(
    StreamTransformer<T, T>.fromHandlers(
      handleError: (Object error, StackTrace stack, EventSink<T> sink) {
        if (error is FirebaseException) {
          sink.addError(
            RentRepositoryException(
              'Rent data could not be loaded. Please try again.',
              code: error.code,
              isOffline: error.code == 'unavailable',
            ),
            stack,
          );
        } else {
          sink.addError(error, stack);
        }
      },
    ),
  );

  void _validateId(String value, String label) {
    if (value.trim().isEmpty || value.contains('/')) {
      throw RentRepositoryException(
        '$label identifier is invalid.',
        code: 'invalid-argument',
      );
    }
  }

  String _string(Object? value, String field) {
    if (value is! String || value.isEmpty) throw _schema('$field is invalid.');
    return value;
  }

  String? _optionalString(Object? value, String field) {
    if (value == null) return null;
    if (value is! String || value.isEmpty) throw _schema('$field is invalid.');
    return value;
  }

  int _integer(Object? value, String field) {
    if (value is! int) throw _schema('$field is invalid.');
    return value;
  }

  int _nonNegative(Object? value, String field) {
    final parsed = _integer(value, field);
    if (parsed < 0) throw _schema('$field is invalid.');
    return parsed;
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

  E _enumValue<E extends Enum>(List<E> values, Object? value, String field) {
    if (value is String) {
      for (final item in values) {
        if (item.name == value) return item;
      }
    }
    throw _schema('$field has an unsupported value.');
  }

  List<Map<String, dynamic>> _maps(Object? value, String field) {
    if (value is! List) throw _schema('$field is invalid.');
    return value.map((item) {
      if (item is! Map) throw _schema('$field contains invalid data.');
      return Map<String, dynamic>.from(item);
    }).toList();
  }

  List<String> _strings(Object? value, String field) {
    if (value is! List || value.any((item) => item is! String)) {
      throw _schema('$field is invalid.');
    }
    return value.cast<String>();
  }

  Timestamp _timestamp(BusinessDate value) =>
      Timestamp.fromDate(value.asUtcDateTime);

  RentRepositoryException _notFound(String message) =>
      RentRepositoryException(message, code: 'not-found');

  RentRepositoryException _schema(String message) =>
      RentRepositoryException(message, code: 'invalid-schema');
}
