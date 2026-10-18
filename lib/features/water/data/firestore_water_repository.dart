import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../property_management/domain/business_date.dart';
import '../domain/water_batch_models.dart';
import '../domain/water_models.dart';
import '../domain/water_repository.dart';
import '../domain/water_values.dart';
import '../domain/water_selection.dart';

class FirestoreWaterRepository implements WaterRepository {
  FirestoreWaterRepository(this._firestore);

  static const primaryHouseId = 'primary';
  static const settingsId = 'config';

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _house(String ownerId) => _firestore
      .collection('owners')
      .doc(ownerId)
      .collection('boardingHouses')
      .doc(primaryHouseId);

  DocumentReference<Map<String, dynamic>> _settings(String ownerId) =>
      _house(ownerId).collection('waterSettings').doc(settingsId);

  CollectionReference<Map<String, dynamic>> _records(String ownerId) =>
      _house(ownerId).collection('waterBillingRecords');

  CollectionReference<Map<String, dynamic>> _batches(String ownerId) =>
      _house(ownerId).collection('waterBillingBatches');

  CollectionReference<Map<String, dynamic>> _batchVoids(String ownerId) =>
      _house(ownerId).collection('waterBillingBatchVoids');

  DocumentReference<Map<String, dynamic>> _electricityBatch(
    String ownerId,
    String batchId,
  ) => _house(ownerId).collection('electricityReadingBatches').doc(batchId);

  @override
  Stream<List<WaterBillingBatch>> watchBillingBatches(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mappedStream(
      _batches(ownerId).snapshots().map((snapshot) {
        final batches = snapshot.docs
            .map((document) => _batchFromData(document.id, document.data()))
            .toList();
        batches.sort((a, b) {
          final byReceipt = b.receiptDate.compareTo(a.receiptDate);
          return byReceipt != 0
              ? byReceipt
              : b.batchReference.compareTo(a.batchReference);
        });
        return batches;
      }),
    );
  }

  @override
  Stream<WaterSettings> watchSettings(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mappedStream(
      _settings(ownerId).snapshots().map((snapshot) {
        if (!snapshot.exists) return WaterSettings.defaults();
        return _settingsFromDocument(snapshot);
      }),
    );
  }

  @override
  Stream<List<WaterBillingRecord>> watchBillingRecords(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mappedStream(
      _records(ownerId).snapshots().map((snapshot) {
        final records = snapshot.docs.map(_recordFromDocument).toList();
        records.sort((a, b) {
          final byEnd = b.endDateExclusive.compareTo(a.endDateExclusive);
          return byEnd != 0
              ? byEnd
              : b.waterRecordId.compareTo(a.waterRecordId);
        });
        return records;
      }),
    );
  }

  @override
  Future<void> saveSettings({
    required String ownerId,
    required WaterSettings settings,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateSettings(settings);
    final reference = _settings(ownerId);
    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final house = await transaction.get(_house(ownerId));
        final existing = await transaction.get(reference);
        if (!house.exists) {
          throw _notFound('The boarding house could not be found.');
        }
        final timestamp = FieldValue.serverTimestamp();
        final data = <String, dynamic>{
          'settingsId': settingsId,
          'defaultMethod': settings.defaultMethod.name,
          'summerBasis': settings.summerBasis.name,
          'summerMonths': settings.summerMonths,
          'allowManualMethodOverride': settings.allowManualMethodOverride,
          'updatedAt': timestamp,
        };
        if (existing.exists) {
          transaction.update(reference, data);
        } else {
          transaction.set(reference, {...data, 'createdAt': timestamp});
        }
      });
    });
  }

  @override
  Future<String> createBillingBatchDraft({
    required String ownerId,
    required BusinessDate receiptDate,
    required WaterCalculationResult result,
    required String? electricityBatchId,
    required bool referencePeriodMismatchConfirmed,
    required String? referenceExplanation,
    required String? notes,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateBatchInput(
      receiptDate: receiptDate,
      result: result,
      electricityBatchId: electricityBatchId,
      referencePeriodMismatchConfirmed: referencePeriodMismatchConfirmed,
      referenceExplanation: referenceExplanation,
      notes: notes,
    );
    final reference = _batches(ownerId).doc();
    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final house = await transaction.get(_house(ownerId));
        if (!house.exists) {
          throw _notFound('The boarding house could not be found.');
        }
        final source = await _electricitySource(
          transaction,
          ownerId: ownerId,
          electricityBatchId: electricityBatchId,
          result: result,
        );
        await _checkSelectionOccupancies(transaction, ownerId, result);
        final timestamp = FieldValue.serverTimestamp();
        transaction.set(reference, {
          ..._batchSnapshotData(
            result: result,
            receiptDate: receiptDate,
            electricityBatchId: electricityBatchId,
            source: source,
            referencePeriodMismatchConfirmed: referencePeriodMismatchConfirmed,
            referenceExplanation: referenceExplanation,
            notes: notes,
          ),
          'batchId': reference.id,
          'batchReference': _batchReference(receiptDate, reference.id),
          'status': WaterBillingBatchStatus.draft.name,
          'version': 1,
          'createdBy': ownerId,
          'createdAt': timestamp,
          'updatedAt': timestamp,
          'finalizedAt': null,
          'usedAt': null,
          'voidReason': null,
          'voidedAt': null,
        });
      });
    });
    return reference.id;
  }

  @override
  Future<void> updateBillingBatchDraft({
    required String ownerId,
    required String batchId,
    required int expectedVersion,
    required BusinessDate receiptDate,
    required WaterCalculationResult result,
    required String? electricityBatchId,
    required bool referencePeriodMismatchConfirmed,
    required String? referenceExplanation,
    required String? notes,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(batchId, 'Water batch');
    _validateBatchInput(
      receiptDate: receiptDate,
      result: result,
      electricityBatchId: electricityBatchId,
      referencePeriodMismatchConfirmed: referencePeriodMismatchConfirmed,
      referenceExplanation: referenceExplanation,
      notes: notes,
    );
    final reference = _batches(ownerId).doc(batchId);
    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);
        if (!snapshot.exists) {
          throw _notFound('That water batch no longer exists.');
        }
        final batch = _batchFromData(snapshot.id, snapshot.data()!);
        if (!batch.canEdit || batch.version != expectedVersion) {
          throw const WaterRepositoryException(
            'The water batch changed after it was opened. Refresh and try again.',
            code: 'aborted',
            isConflict: true,
          );
        }
        final source = await _electricitySource(
          transaction,
          ownerId: ownerId,
          electricityBatchId: electricityBatchId,
          result: result,
        );
        await _checkSelectionOccupancies(transaction, ownerId, result);
        transaction.update(reference, {
          ..._batchSnapshotData(
            result: result,
            receiptDate: receiptDate,
            electricityBatchId: electricityBatchId,
            source: source,
            referencePeriodMismatchConfirmed: referencePeriodMismatchConfirmed,
            referenceExplanation: referenceExplanation,
            notes: notes,
          ),
          'version': batch.version + 1,
          'updatedAt': FieldValue.serverTimestamp(),
          if (result.method != WaterBillingMethod.selectedBoarders &&
              batch.method == WaterBillingMethod.selectedBoarders) ...{
            'allocationSchemaVersion': FieldValue.delete(),
            'roundingPolicy': FieldValue.delete(),
            'includedBoarderCount': FieldValue.delete(),
            'decisions': FieldValue.delete(),
          },
        });
      });
    });
  }

  @override
  Future<void> finalizeBillingBatch({
    required String ownerId,
    required String batchId,
    int? expectedVersion,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(batchId, 'Water batch');
    final reference = _batches(ownerId).doc(batchId);
    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);
        if (!snapshot.exists) {
          throw _notFound('That water batch no longer exists.');
        }
        final batch = _batchFromData(snapshot.id, snapshot.data()!);
        if (!batch.canEdit ||
            (expectedVersion != null && batch.version != expectedVersion)) {
          throw const WaterRepositoryException(
            'Only a draft water batch can be finalized.',
            code: 'failed-precondition',
          );
        }
        _validateResult(batch);
        await _checkSelectionOccupancies(transaction, ownerId, batch);
        await _electricitySource(
          transaction,
          ownerId: ownerId,
          electricityBatchId: batch.electricityBatchId,
          result: batch,
        );
        transaction.update(reference, {
          'status': WaterBillingBatchStatus.finalized.name,
          'version': batch.version + 1,
          'finalizedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    });
  }

  @override
  Future<void> voidBillingBatch({
    required String ownerId,
    required String batchId,
    required String reason,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(batchId, 'Water batch');
    final cleanReason = reason.trim();
    if (cleanReason.length < 3 || cleanReason.length > 500) {
      throw const WaterRepositoryException(
        'Enter a void reason from 3 to 500 characters.',
        code: 'invalid-argument',
      );
    }
    final reference = _batches(ownerId).doc(batchId);
    final audit = _batchVoids(ownerId).doc(batchId);
    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);
        final existingAudit = await transaction.get(audit);
        if (!snapshot.exists) {
          throw _notFound('That water batch no longer exists.');
        }
        final batch = _batchFromData(snapshot.id, snapshot.data()!);
        if (!batch.canVoid || existingAudit.exists) {
          throw const WaterRepositoryException(
            'Only a finalized, unused water batch can be voided once.',
            code: 'failed-precondition',
          );
        }
        final timestamp = FieldValue.serverTimestamp();
        transaction.update(reference, {
          'status': WaterBillingBatchStatus.voided.name,
          'version': batch.version + 1,
          'voidReason': cleanReason,
          'voidedAt': timestamp,
          'updatedAt': timestamp,
        });
        transaction.set(audit, {
          'voidId': batchId,
          'batchId': batchId,
          'batchReference': batch.batchReference,
          'reason': cleanReason,
          'voidedBy': ownerId,
          'createdAt': timestamp,
        });
      });
    });
  }

  Future<void> _checkSelectionOccupancies(
    Transaction transaction,
    String ownerId,
    WaterCalculationResult result,
  ) async {
    if (result.method != WaterBillingMethod.selectedBoarders) return;
    for (final decision in result.decisions) {
      for (final evidence in decision.occupancies) {
        final snapshot = await transaction.get(
          _house(ownerId).collection('occupancies').doc(evidence.occupancyId),
        );
        final data = snapshot.data();
        if (data == null ||
            data['boarderId'] != decision.boarderId ||
            data['roomId'] != evidence.roomId ||
            _businessDate(data['moveInDate'], 'moveInDate') !=
                evidence.moveIn ||
            _optionalBusinessDate(data['moveOutDate'], 'moveOutDate') !=
                evidence.moveOut) {
          throw const WaterRepositoryException(
            'Occupancy changed after review. Reopen the draft and review the boarders again.',
            code: 'aborted',
            isConflict: true,
          );
        }
      }
    }
  }

  @override
  Future<String> recordBillingSnapshot({
    required String ownerId,
    required WaterCalculationResult result,
  }) async {
    _validateId(ownerId, 'Owner');
    if (result.method == WaterBillingMethod.selectedBoarders) {
      throw const WaterRepositoryException(
        'Save selected-boarder allocations through a water billing batch.',
        code: 'invalid-argument',
      );
    }
    _validateResult(result);
    final recordId = result.method == WaterBillingMethod.roomDays
        ? '${result.startDate}_${result.endDateExclusive}_roomDays'
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
          throw const WaterRepositoryException(
            'A water record already exists for these dates.',
            code: 'water-record-already-exists',
            isConflict: true,
          );
        }
        transaction.set(reference, {
          'recordId': recordId,
          'startDate': _timestamp(result.startDate),
          'endDateExclusive': _timestamp(result.endDateExclusive),
          'waterBillCentavos': result.waterBillCentavos,
          'method': result.method.name,
          'summerBasis': result.summerBasis.name,
          'electricityRecordId': result.electricityRecordId,
          'totalPersonDays': result.totalPersonDays,
          'totalElectricityBasis': result.totalElectricityBasis,
          'totalAllocatedCentavos': result.totalAllocatedCentavos,
          'totalUnallocatedCentavos': result.totalUnallocatedCentavos,
          'roomAllocations': result.roomAllocations
              .map(_roomAllocationToMap)
              .toList(),
          'boarderShares': result.boarderShares
              .map(_boarderShareToMap)
              .toList(),
          'warnings': result.warnings,
          'createdBy': ownerId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
    });
    return recordId;
  }

  Future<_ElectricitySource?> _electricitySource(
    Transaction transaction, {
    required String ownerId,
    required String? electricityBatchId,
    required WaterCalculationResult result,
  }) async {
    if (result.method != WaterBillingMethod.electricityPercentage) {
      if (electricityBatchId != null || result.electricityRecordId != null) {
        throw const WaterRepositoryException(
          'Normal water allocation must not include an electricity reference.',
          code: 'invalid-argument',
        );
      }
      return null;
    }
    if (electricityBatchId == null ||
        electricityBatchId.isEmpty ||
        result.electricityRecordId != electricityBatchId) {
      throw const WaterRepositoryException(
        'Summer water allocation requires the explicitly selected electricity batch.',
        code: 'missing-electricity-batch',
      );
    }
    final snapshot = await transaction.get(
      _electricityBatch(ownerId, electricityBatchId),
    );
    if (!snapshot.exists) {
      throw _notFound('The selected electricity batch no longer exists.');
    }
    final data = snapshot.data()!;
    final status = _requiredString(data['status'], 'electricity.status');
    if (status != 'finalized' && status != 'usedInBilling') {
      throw const WaterRepositoryException(
        'Select a finalized electricity batch that has not been voided.',
        code: 'invalid-electricity-batch',
        isConflict: true,
      );
    }
    final reference = _requiredString(
      data['batchReference'],
      'electricity.batchReference',
    );
    final end = _businessDate(
      data['effectiveDate'],
      'electricity.effectiveDate',
    );
    final entries = _mapList(data['entries'], 'electricity.entries');
    BusinessDate? start;
    for (final entry in entries) {
      if (entry['status'] != 'recorded') continue;
      final candidate = _businessDate(
        entry['previousReadingDate'],
        'electricity.previousReadingDate',
      );
      if (start == null || candidate.isBefore(start)) start = candidate;
    }
    return _ElectricitySource(
      batchReference: reference,
      measurementStart: start ?? end,
      measurementEnd: end,
    );
  }

  Map<String, dynamic> _batchSnapshotData({
    required WaterCalculationResult result,
    required BusinessDate receiptDate,
    required String? electricityBatchId,
    required _ElectricitySource? source,
    required bool referencePeriodMismatchConfirmed,
    required String? referenceExplanation,
    required String? notes,
  }) {
    final mismatch =
        source != null &&
        (source.measurementStart != result.startDate ||
            source.measurementEnd != result.endDateExclusive);
    if (mismatch && !referencePeriodMismatchConfirmed) {
      throw const WaterRepositoryException(
        'Confirm the different electricity and water periods before saving.',
        code: 'period-mismatch-not-confirmed',
      );
    }
    return {
      'startDate': _timestamp(result.startDate),
      'endDateExclusive': _timestamp(result.endDateExclusive),
      'receiptDate': _timestamp(receiptDate),
      'waterBillCentavos': result.waterBillCentavos,
      'method': result.method.name,
      'summerBasis': result.summerBasis.name,
      'electricityBatchId': electricityBatchId,
      'electricityBatchReference': source?.batchReference,
      'electricityMeasurementStart': source == null
          ? null
          : _timestamp(source.measurementStart),
      'electricityMeasurementEnd': source == null
          ? null
          : _timestamp(source.measurementEnd),
      'referencePeriodMismatchConfirmed':
          mismatch && referencePeriodMismatchConfirmed,
      'referenceExplanation': _cleanOptional(referenceExplanation),
      'notes': _cleanOptional(notes),
      'totalPersonDays': result.totalPersonDays,
      'totalElectricityBasis': result.totalElectricityBasis,
      'totalAllocatedCentavos': result.totalAllocatedCentavos,
      'totalUnallocatedCentavos': result.totalUnallocatedCentavos,
      'roomAllocations': result.roomAllocations
          .map(_roomAllocationToMap)
          .toList(),
      'boarderShares': result.boarderShares.map(_boarderShareToMap).toList(),
      'warnings': result.warnings,
      if (result.method == WaterBillingMethod.selectedBoarders) ...{
        'allocationSchemaVersion': 1,
        'roundingPolicy': 'boarderIdAscending',
        'includedBoarderCount': result.includedBoarderCount,
        'decisions': result.decisions.map((d) => d.toMap()).toList(),
      },
    };
  }

  WaterBillingBatch _batchFromData(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final batchId = _requiredString(data['batchId'], 'batchId');
    if (batchId != documentId) {
      throw _schema('A water batch ID is inconsistent.');
    }
    final method = _enumValue(
      WaterBillingMethod.values,
      data['method'],
      'method',
    );
    if (method == WaterBillingMethod.selectedBoarders &&
        (data['allocationSchemaVersion'] != 1 ||
            data['roundingPolicy'] != 'boarderIdAscending')) {
      throw _schema('Unknown selected-boarder allocation schema.');
    }
    final electricityBatchId = _optionalString(
      data['electricityBatchId'],
      'electricityBatchId',
    );
    if ((method == WaterBillingMethod.electricityPercentage) !=
        (electricityBatchId != null)) {
      throw _schema('A water batch has an invalid electricity reference.');
    }
    return WaterBillingBatch(
      batchId: batchId,
      batchReference: _requiredString(data['batchReference'], 'batchReference'),
      status: _enumValue(
        WaterBillingBatchStatus.values,
        data['status'],
        'status',
      ),
      startDate: _businessDate(data['startDate'], 'startDate'),
      endDateExclusive: _businessDate(
        data['endDateExclusive'],
        'endDateExclusive',
      ),
      receiptDate: _businessDate(data['receiptDate'], 'receiptDate'),
      waterBillCentavos: _nonNegativeInt(
        data['waterBillCentavos'],
        'waterBillCentavos',
      ),
      method: method,
      summerBasis: _enumValue(
        SummerElectricityBasis.values,
        data['summerBasis'],
        'summerBasis',
      ),
      electricityBatchId: electricityBatchId,
      electricityBatchReference: _optionalString(
        data['electricityBatchReference'],
        'electricityBatchReference',
      ),
      electricityMeasurementStart: _optionalBusinessDate(
        data['electricityMeasurementStart'],
        'electricityMeasurementStart',
      ),
      electricityMeasurementEnd: _optionalBusinessDate(
        data['electricityMeasurementEnd'],
        'electricityMeasurementEnd',
      ),
      referencePeriodMismatchConfirmed: _boolean(
        data['referencePeriodMismatchConfirmed'],
        'referencePeriodMismatchConfirmed',
      ),
      referenceExplanation: _optionalString(
        data['referenceExplanation'],
        'referenceExplanation',
      ),
      notes: _optionalString(data['notes'], 'notes'),
      totalPersonDays: _nonNegativeInt(
        data['totalPersonDays'],
        'totalPersonDays',
      ),
      totalElectricityBasis: _nonNegativeInt(
        data['totalElectricityBasis'],
        'totalElectricityBasis',
      ),
      totalAllocatedCentavos: _nonNegativeInt(
        data['totalAllocatedCentavos'],
        'totalAllocatedCentavos',
      ),
      totalUnallocatedCentavos: _nonNegativeInt(
        data['totalUnallocatedCentavos'],
        'totalUnallocatedCentavos',
      ),
      roomAllocations: _mapList(
        data['roomAllocations'],
        'roomAllocations',
      ).map(_roomAllocationFromMap).toList(),
      boarderShares: _mapList(
        data['boarderShares'],
        'boarderShares',
      ).map(_boarderShareFromMap).toList(),
      warnings: _stringList(data['warnings'], 'warnings'),
      decisions: method == WaterBillingMethod.selectedBoarders
          ? _mapList(
              data['decisions'],
              'decisions',
            ).map(WaterBoarderDecision.fromMap).toList()
          : const [],
      version: _positiveInt(data['version'], 'version'),
      createdAt: _dateTime(data['createdAt'], 'createdAt'),
      updatedAt: _dateTime(data['updatedAt'], 'updatedAt'),
      finalizedAt: _optionalDateTime(data['finalizedAt'], 'finalizedAt'),
      usedAt: _optionalDateTime(data['usedAt'], 'usedAt'),
      voidReason: _optionalString(data['voidReason'], 'voidReason'),
      voidedAt: _optionalDateTime(data['voidedAt'], 'voidedAt'),
    );
  }

  Map<String, dynamic> _roomAllocationToMap(WaterRoomAllocation value) => {
    'roomId': value.roomId,
    'roomName': value.roomName,
    'electricityBasisValue': value.electricityBasisValue,
    'occupancyDays': value.occupancyDays,
    'roomChargeCentavos': value.roomChargeCentavos,
    'allocatedCentavos': value.allocatedCentavos,
    'unallocatedCentavos': value.unallocatedCentavos,
    'boarderShares': value.boarderShares.map(_roomBoarderShareToMap).toList(),
  };

  Map<String, dynamic> _roomBoarderShareToMap(RoomBoarderWaterShare value) => {
    'boarderId': value.boarderId,
    'boarderName': value.boarderName,
    'occupancyIds': value.occupancyIds,
    'occupancyDays': value.occupancyDays,
    'amountCentavos': value.amountCentavos,
  };

  Map<String, dynamic> _boarderShareToMap(BoarderWaterShare value) => {
    'boarderId': value.boarderId,
    'boarderName': value.boarderName,
    'occupancyIds': value.occupancyIds,
    'roomIds': value.roomIds,
    'occupancyDays': value.occupancyDays,
    'amountCentavos': value.amountCentavos,
  };

  WaterSettings _settingsFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data()!;
    if (document.id != settingsId || data['settingsId'] != settingsId) {
      throw _schema('Water settings have an inconsistent identifier.');
    }
    final months = _integerList(data['summerMonths'], 'summerMonths');
    final settings = WaterSettings(
      defaultMethod: _enumValue(
        WaterBillingMethod.values,
        data['defaultMethod'],
        'defaultMethod',
      ),
      summerBasis: _enumValue(
        SummerElectricityBasis.values,
        data['summerBasis'],
        'summerBasis',
      ),
      summerMonths: months,
      allowManualMethodOverride: _boolean(
        data['allowManualMethodOverride'],
        'allowManualMethodOverride',
      ),
    );
    _validateSettings(settings);
    _dateTime(data['createdAt'], 'createdAt');
    _dateTime(data['updatedAt'], 'updatedAt');
    return settings;
  }

  WaterBillingRecord _recordFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final recordId = _requiredString(data['recordId'], 'recordId');
    if (recordId != document.id) {
      throw _schema('A water record ID is inconsistent.');
    }
    return WaterBillingRecord(
      waterRecordId: recordId,
      startDate: _businessDate(data['startDate'], 'startDate'),
      endDateExclusive: _businessDate(
        data['endDateExclusive'],
        'endDateExclusive',
      ),
      waterBillCentavos: _nonNegativeInt(
        data['waterBillCentavos'],
        'waterBillCentavos',
      ),
      method: _enumValue(WaterBillingMethod.values, data['method'], 'method'),
      summerBasis: _enumValue(
        SummerElectricityBasis.values,
        data['summerBasis'],
        'summerBasis',
      ),
      electricityRecordId: _optionalString(
        data['electricityRecordId'],
        'electricityRecordId',
      ),
      totalPersonDays: _nonNegativeInt(
        data['totalPersonDays'],
        'totalPersonDays',
      ),
      totalElectricityBasis: _nonNegativeInt(
        data['totalElectricityBasis'],
        'totalElectricityBasis',
      ),
      totalAllocatedCentavos: _nonNegativeInt(
        data['totalAllocatedCentavos'],
        'totalAllocatedCentavos',
      ),
      totalUnallocatedCentavos: _nonNegativeInt(
        data['totalUnallocatedCentavos'],
        'totalUnallocatedCentavos',
      ),
      roomAllocations: _mapList(
        data['roomAllocations'],
        'roomAllocations',
      ).map(_roomAllocationFromMap).toList(),
      boarderShares: _mapList(
        data['boarderShares'],
        'boarderShares',
      ).map(_boarderShareFromMap).toList(),
      warnings: _stringList(data['warnings'], 'warnings'),
      recordedAt: _dateTime(data['createdAt'], 'createdAt'),
    );
  }

  WaterRoomAllocation _roomAllocationFromMap(Map<String, dynamic> data) =>
      WaterRoomAllocation(
        roomId: _requiredString(data['roomId'], 'roomId'),
        roomName: _requiredString(data['roomName'], 'roomName'),
        electricityBasisValue: _nonNegativeInt(
          data['electricityBasisValue'],
          'electricityBasisValue',
        ),
        occupancyDays: _nonNegativeInt(data['occupancyDays'], 'occupancyDays'),
        roomChargeCentavos: _nonNegativeInt(
          data['roomChargeCentavos'],
          'roomChargeCentavos',
        ),
        allocatedCentavos: _nonNegativeInt(
          data['allocatedCentavos'],
          'allocatedCentavos',
        ),
        unallocatedCentavos: _nonNegativeInt(
          data['unallocatedCentavos'],
          'unallocatedCentavos',
        ),
        boarderShares: _mapList(
          data['boarderShares'],
          'room.boarderShares',
        ).map(_roomBoarderShareFromMap).toList(),
      );

  RoomBoarderWaterShare _roomBoarderShareFromMap(Map<String, dynamic> data) =>
      RoomBoarderWaterShare(
        boarderId: _requiredString(data['boarderId'], 'boarderId'),
        boarderName: _requiredString(data['boarderName'], 'boarderName'),
        occupancyIds: _stringList(data['occupancyIds'], 'occupancyIds'),
        occupancyDays: _nonNegativeInt(data['occupancyDays'], 'occupancyDays'),
        amountCentavos: _nonNegativeInt(
          data['amountCentavos'],
          'amountCentavos',
        ),
      );

  BoarderWaterShare _boarderShareFromMap(Map<String, dynamic> data) =>
      BoarderWaterShare(
        boarderId: _requiredString(data['boarderId'], 'boarderId'),
        boarderName: _requiredString(data['boarderName'], 'boarderName'),
        occupancyIds: _stringList(data['occupancyIds'], 'occupancyIds'),
        roomIds: _stringList(data['roomIds'], 'roomIds'),
        occupancyDays: _nonNegativeInt(data['occupancyDays'], 'occupancyDays'),
        amountCentavos: _nonNegativeInt(
          data['amountCentavos'],
          'amountCentavos',
        ),
      );

  void _validateSettings(WaterSettings settings) {
    final months = settings.summerMonths.toSet();
    if (months.isEmpty ||
        months.length != settings.summerMonths.length ||
        months.any((month) => month < 1 || month > 12)) {
      throw const WaterRepositoryException(
        'Select one or more unique summer months.',
        code: 'invalid-argument',
      );
    }
  }

  void _validateResult(WaterCalculationResult result) {
    if (result.method == WaterBillingMethod.selectedBoarders) {
      if (result.decisions.length > 2000 ||
          utf8
                  .encode(
                    jsonEncode(result.decisions.map((d) => d.toMap()).toList()),
                  )
                  .length >
              500000) {
        throw _schema(
          'The occupancy snapshot is too large for one water batch.',
        );
      }
      final expected = calculateSelectedWater(
        start: result.startDate,
        end: result.endDateExclusive,
        amount: result.waterBillCentavos,
        decisions: result.decisions,
      );
      if (jsonEncode(
                result.roomAllocations.map(_roomAllocationToMap).toList(),
              ) !=
              jsonEncode(
                expected.roomAllocations.map(_roomAllocationToMap).toList(),
              ) ||
          jsonEncode(result.boarderShares.map(_boarderShareToMap).toList()) !=
              jsonEncode(
                expected.boarderShares.map(_boarderShareToMap).toList(),
              ) ||
          result.totalPersonDays != expected.totalPersonDays ||
          result.totalAllocatedCentavos != expected.totalAllocatedCentavos ||
          result.totalUnallocatedCentavos != 0) {
        throw _schema(
          'Selected boarder decisions and water totals do not reconcile.',
        );
      }
    }
    final today = BusinessDate.todayInManila();
    final reconciles =
        result.totalAllocatedCentavos + result.totalUnallocatedCentavos ==
        result.waterBillCentavos;
    final methodFieldsMatch = switch (result.method) {
      WaterBillingMethod.selectedBoarders =>
        result.electricityRecordId == null &&
            result.totalElectricityBasis == 0 &&
            result.decisions.isNotEmpty,
      WaterBillingMethod.personDays =>
        result.electricityRecordId == null && result.totalElectricityBasis == 0,
      WaterBillingMethod.roomDays =>
        result.electricityRecordId == null &&
            result.totalElectricityBasis == 0 &&
            result.boarderShares.isEmpty,
      WaterBillingMethod.electricityPercentage =>
        (result.electricityRecordId?.isNotEmpty ?? false) &&
            result.totalElectricityBasis > 0,
    };
    if (!result.startDate.isBefore(result.endDateExclusive) ||
        result.endDateExclusive.isAfter(today) ||
        result.waterBillCentavos < 0 ||
        result.waterBillCentavos > WaterValues.maximumBillCentavos ||
        result.totalAllocatedCentavos < 0 ||
        result.totalUnallocatedCentavos < 0 ||
        result.totalAllocatedCentavos > WaterValues.maximumBillCentavos ||
        result.totalUnallocatedCentavos > WaterValues.maximumBillCentavos ||
        result.totalPersonDays < 0 ||
        result.totalElectricityBasis < 0 ||
        result.roomAllocations.length > 500 ||
        result.boarderShares.length > 2000 ||
        result.warnings.length > 100 ||
        !reconciles ||
        !methodFieldsMatch) {
      throw const WaterRepositoryException(
        'The water calculation is outside the supported billing limits.',
        code: 'invalid-argument',
      );
    }
  }

  void _validateBatchInput({
    required BusinessDate receiptDate,
    required WaterCalculationResult result,
    required String? electricityBatchId,
    required bool referencePeriodMismatchConfirmed,
    required String? referenceExplanation,
    required String? notes,
  }) {
    _validateResult(result);
    final today = BusinessDate.todayInManila();
    final explanation = referenceExplanation?.trim();
    final cleanNotes = notes?.trim();
    if (result.method == WaterBillingMethod.roomDays ||
        receiptDate.isAfter(today) ||
        (electricityBatchId != null && electricityBatchId.contains('/')) ||
        (explanation != null && explanation.length > 500) ||
        (cleanNotes != null && cleanNotes.length > 1000)) {
      throw const WaterRepositoryException(
        'The water batch details are outside the supported limits.',
        code: 'invalid-argument',
      );
    }
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on WaterRepositoryException {
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

  WaterRepositoryException _mapFirestoreException(FirebaseException error) {
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
      (_, true, _) => 'Another water-billing change happened at the same time. Refresh and try again.',
      (_, _, 'permission-denied') =>
        'You do not have permission to change this boarding house.',
      _ => 'The water record could not be saved. Please try again.',
    };
    return WaterRepositoryException(
      message,
      code: error.code,
      isOffline: offline,
      isConflict: conflict,
    );
  }

  void _validateId(String value, String label) {
    if (value.trim().isEmpty || value.contains('/')) {
      throw WaterRepositoryException(
        '$label identifier is invalid.',
        code: 'invalid-argument',
      );
    }
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

  int _nonNegativeInt(Object? value, String field) {
    if (value is! int || value < 0) throw _schema('$field is invalid.');
    return value;
  }

  int _positiveInt(Object? value, String field) {
    if (value is! int || value < 1) throw _schema('$field is invalid.');
    return value;
  }

  bool _boolean(Object? value, String field) {
    if (value is! bool) throw _schema('$field is invalid.');
    return value;
  }

  DateTime _dateTime(Object? value, String field) {
    if (value is! Timestamp) throw _schema('$field is invalid.');
    return value.toDate().toUtc();
  }

  DateTime? _optionalDateTime(Object? value, String field) {
    if (value == null) return null;
    return _dateTime(value, field);
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

  List<String> _stringList(Object? value, String field) {
    if (value is! List || value.any((item) => item is! String)) {
      throw _schema('$field is invalid.');
    }
    return value.cast<String>();
  }

  List<int> _integerList(Object? value, String field) {
    if (value is! List || value.any((item) => item is! int)) {
      throw _schema('$field is invalid.');
    }
    return value.cast<int>();
  }

  Timestamp _timestamp(BusinessDate value) =>
      Timestamp.fromDate(value.asUtcDateTime);

  String? _cleanOptional(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  String _batchReference(BusinessDate receiptDate, String documentId) {
    final suffix = documentId
        .replaceAll(RegExp('[^A-Za-z0-9]'), '')
        .toUpperCase();
    final short = suffix.substring(0, suffix.length.clamp(0, 6));
    return 'WB-${receiptDate.year}-${receiptDate.month.toString().padLeft(2, '0')}-$short';
  }

  WaterRepositoryException _notFound(String message) =>
      WaterRepositoryException(message, code: 'not-found');

  WaterRepositoryException _schema(String message) => WaterRepositoryException(
    '$message Refresh the app. If it continues, contact support.',
    code: 'invalid-data',
  );
}

class _ElectricitySource {
  const _ElectricitySource({
    required this.batchReference,
    required this.measurementStart,
    required this.measurementEnd,
  });

  final String batchReference;
  final BusinessDate measurementStart;
  final BusinessDate measurementEnd;
}
