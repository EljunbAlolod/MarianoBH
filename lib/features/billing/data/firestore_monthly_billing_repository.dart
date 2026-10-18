import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../electricity/domain/electricity_batch_models.dart';
import '../../property_management/domain/business_date.dart';
import '../../water/domain/water_batch_models.dart';
import '../../water/domain/water_models.dart';
import '../domain/monthly_billing_models.dart';
import '../domain/monthly_billing_repository.dart';
import '../domain/room_billing_models.dart';
import '../domain/utility_billing_models.dart';

class FirestoreMonthlyBillingRepository implements MonthlyBillingRepository {
  FirestoreMonthlyBillingRepository(this._firestore);

  static const _houseId = 'primary';
  static const _maximumAmountCentavos = 1000000000000000;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _house(String ownerId) => _firestore
      .collection('owners')
      .doc(ownerId)
      .collection('boardingHouses')
      .doc(_houseId);

  CollectionReference<Map<String, dynamic>> _collection(
    String ownerId,
    String name,
  ) => _house(ownerId).collection(name);

  @override
  Stream<List<UtilityBillingBatch>> watchUtilityBillingBatches(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _collection(ownerId, 'utilityBillingBatches').snapshots().map((snapshot) {
        final items = snapshot.docs.map(_utilityBatchFromDoc).toList();
        items.sort((a, b) {
          final byIssued = b.issuedOn.compareTo(a.issuedOn);
          return byIssued != 0 ? byIssued : b.createdAt.compareTo(a.createdAt);
        });
        return items;
      }),
    );
  }

  @override
  Stream<List<UtilityRoomBillAccount>> watchUtilityRoomAccounts(
    String ownerId,
  ) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _collection(ownerId, 'utilityRoomBillAccounts').snapshots().map(
        (snapshot) => snapshot.docs.map(_utilityRoomAccountFromDoc).toList(),
      ),
    );
  }

  @override
  Stream<List<UtilityRoomPaymentRecord>> watchUtilityRoomPayments(
    String ownerId,
  ) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _collection(ownerId, 'utilityRoomPayments').snapshots().map((snapshot) {
        final items = snapshot.docs.map(_utilityRoomPaymentFromDoc).toList();
        items.sort((a, b) {
          final byDate = b.paymentDate.compareTo(a.paymentDate);
          return byDate != 0 ? byDate : b.recordedAt.compareTo(a.recordedAt);
        });
        return items;
      }),
    );
  }

  @override
  Stream<List<MonthlyBillingCycle>> watchCycles(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _collection(ownerId, 'monthlyBillingCycles').snapshots().map((snapshot) {
        final items = snapshot.docs.map(_cycleFromDoc).toList();
        items.sort((a, b) {
          final byEnd = b.endDateExclusive.compareTo(a.endDateExclusive);
          return byEnd != 0 ? byEnd : b.version.compareTo(a.version);
        });
        return items;
      }),
    );
  }

  @override
  Stream<List<BillingCycleControl>> watchControls(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _collection(ownerId, 'billingCycleControls').snapshots().map(
        (snapshot) => snapshot.docs.map(_controlFromDoc).toList(),
      ),
    );
  }

  @override
  Stream<List<BoarderBillAccount>> watchAccounts(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _collection(ownerId, 'boarderBillAccounts').snapshots().map(
        (snapshot) => snapshot.docs.map(_accountFromDoc).toList(),
      ),
    );
  }

  @override
  Stream<List<PaymentRecord>> watchPayments(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _collection(ownerId, 'payments').snapshots().map((snapshot) {
        final items = snapshot.docs.map(_paymentFromDoc).toList();
        items.sort((a, b) {
          final byDate = b.paymentDate.compareTo(a.paymentDate);
          return byDate != 0 ? byDate : b.recordedAt.compareTo(a.recordedAt);
        });
        return items;
      }),
    );
  }

  @override
  Stream<List<RoomBillingCycle>> watchRoomCycles(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _collection(ownerId, 'roomBillingCycles').snapshots().map((snapshot) {
        final items = snapshot.docs.map(_roomCycleFromDoc).toList();
        items.sort((a, b) {
          final byEnd = b.endDateExclusive.compareTo(a.endDateExclusive);
          return byEnd != 0 ? byEnd : b.version.compareTo(a.version);
        });
        return items;
      }),
    );
  }

  @override
  Stream<List<BillingCycleControl>> watchRoomControls(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _collection(ownerId, 'roomBillingControls').snapshots().map(
        (snapshot) => snapshot.docs.map(_controlFromDoc).toList(),
      ),
    );
  }

  @override
  Stream<List<RoomBillAccount>> watchRoomAccounts(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _collection(ownerId, 'roomBillAccounts').snapshots().map(
        (snapshot) => snapshot.docs.map(_roomAccountFromDoc).toList(),
      ),
    );
  }

  @override
  Stream<List<RoomPaymentRecord>> watchRoomPayments(String ownerId) {
    _validateId(ownerId, 'Owner');
    return _mapped(
      _collection(ownerId, 'roomPayments').snapshots().map((snapshot) {
        final items = snapshot.docs.map(_roomPaymentFromDoc).toList();
        items.sort((a, b) {
          final byDate = b.paymentDate.compareTo(a.paymentDate);
          return byDate != 0 ? byDate : b.recordedAt.compareTo(a.recordedAt);
        });
        return items;
      }),
    );
  }

  @override
  Future<String> finalizeCycle({
    required String ownerId,
    required MonthlyBillingResult result,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateResult(result);
    final periodId = '${result.startDate}_${result.endDateExclusive}';
    final periodRef = _collection(ownerId, 'billingPeriods').doc(periodId);
    return _guard(() async {
      return _firestore.runTransaction((transaction) async {
        final house = await transaction.get(_house(ownerId));
        final period = await transaction.get(periodRef);
        if (!house.exists) throw _notFound('The boarding house was not found.');

        var version = 1;
        String? replacesCycleId;
        if (period.exists) {
          final data = period.data()!;
          if (data['activeCycleId'] != null) {
            throw const MonthlyBillingRepositoryException(
              'This billing period has already been finalized.',
              code: 'billing-period-already-finalized',
              isConflict: true,
            );
          }
          version = _integer(data['latestVersion'], 'latestVersion') + 1;
          replacesCycleId = _optionalString(
            data['latestCycleId'],
            'latestCycleId',
          );
        }
        final cycleId = '${periodId}_v$version';
        final cycleRef = _collection(
          ownerId,
          'monthlyBillingCycles',
        ).doc(cycleId);
        final controlRef = _collection(
          ownerId,
          'billingCycleControls',
        ).doc(cycleId);
        final now = FieldValue.serverTimestamp();
        transaction.set(cycleRef, {
          'billingCycleId': cycleId,
          'periodId': periodId,
          'version': version,
          'replacesCycleId': replacesCycleId,
          'startDate': _date(result.startDate),
          'endDateExclusive': _date(result.endDateExclusive),
          'electricityRecordId': result.electricityRecordId,
          'waterRecordId': result.waterRecordId,
          'rentRecordId': result.rentRecordId,
          'electricityTotalCentavos': result.electricityTotalCentavos,
          'waterTotalCentavos': result.waterTotalCentavos,
          'rentTotalCentavos': result.rentTotalCentavos,
          'rentAdjustmentCentavos': result.rentAdjustmentCentavos,
          'totalBilledCentavos': result.totalBilledCentavos,
          'totalUnallocatedCentavos': result.totalUnallocatedCentavos,
          'statements': result.statements.map(_statementToMap).toList(),
          'warnings': result.warnings,
          'createdBy': ownerId,
          'createdAt': now,
        });
        transaction.set(controlRef, {
          'billingCycleId': cycleId,
          'state': BillingCycleState.active.name,
          'totalBilledCentavos': result.totalBilledCentavos,
          'totalPaidCentavos': 0,
          'outstandingCentavos': result.totalBilledCentavos,
          'voidReason': null,
          'voidedAt': null,
          'reissuedAsCycleId': null,
          'lastPaymentId': null,
          'createdAt': now,
          'updatedAt': now,
        });
        if (period.exists) {
          transaction.update(periodRef, {
            'activeCycleId': cycleId,
            'latestCycleId': cycleId,
            'latestVersion': version,
            'updatedAt': now,
          });
          if (replacesCycleId != null) {
            transaction.update(
              _collection(ownerId, 'billingCycleControls').doc(replacesCycleId),
              {'reissuedAsCycleId': cycleId, 'updatedAt': now},
            );
          }
        } else {
          transaction.set(periodRef, {
            'periodId': periodId,
            'startDate': _date(result.startDate),
            'endDateExclusive': _date(result.endDateExclusive),
            'activeCycleId': cycleId,
            'latestCycleId': cycleId,
            'latestVersion': version,
            'createdAt': now,
            'updatedAt': now,
          });
        }
        for (final statement in result.statements) {
          final accountId = '${cycleId}_${statement.boarderId}';
          transaction.set(
            _collection(ownerId, 'boarderBillAccounts').doc(accountId),
            {
              'accountId': accountId,
              'billingCycleId': cycleId,
              'boarderId': statement.boarderId,
              'boarderName': statement.boarderName,
              'totalChargesCentavos': statement.currentChargesCentavos,
              'previousBalanceCentavos': statement.previousBalanceCentavos,
              'totalPaidCentavos': 0,
              'lastPaymentId': null,
              'createdAt': now,
              'updatedAt': now,
            },
          );
        }
        return cycleId;
      });
    });
  }

  @override
  Future<String> finalizeRoomCycle({
    required String ownerId,
    required RoomBillingResult result,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateRoomResult(result);
    final periodId = '${result.startDate}_${result.endDateExclusive}';
    final periodRef = _collection(ownerId, 'roomBillingPeriods').doc(periodId);
    return _guard(() async {
      return _firestore.runTransaction((transaction) async {
        final house = await transaction.get(_house(ownerId));
        final period = await transaction.get(periodRef);
        if (!house.exists) throw _notFound('The boarding house was not found.');

        var version = 1;
        String? replacesCycleId;
        if (period.exists) {
          final data = period.data()!;
          if (data['activeCycleId'] != null) {
            throw const MonthlyBillingRepositoryException(
              'This room billing month has already been finalized.',
              code: 'room-billing-period-already-finalized',
              isConflict: true,
            );
          }
          version = _integer(data['latestVersion'], 'latestVersion') + 1;
          replacesCycleId = _optionalString(
            data['latestCycleId'],
            'latestCycleId',
          );
        }
        final cycleId = '${periodId}_room_v$version';
        final cycleRef = _collection(ownerId, 'roomBillingCycles').doc(cycleId);
        final controlRef = _collection(
          ownerId,
          'roomBillingControls',
        ).doc(cycleId);
        final now = FieldValue.serverTimestamp();
        transaction.set(cycleRef, {
          'billingCycleId': cycleId,
          'periodId': periodId,
          'billingModel': 'roomV2',
          'version': version,
          'replacesCycleId': replacesCycleId,
          'startDate': _date(result.startDate),
          'endDateExclusive': _date(result.endDateExclusive),
          'electricityRecordId': result.electricityRecordId,
          'waterRecordId': result.waterRecordId,
          'rentRecordId': result.rentRecordId,
          'electricityTotalCentavos': result.electricityTotalCentavos,
          'waterTotalCentavos': result.waterTotalCentavos,
          'rentTotalCentavos': result.rentTotalCentavos,
          'adjustmentTotalCentavos': result.adjustmentTotalCentavos,
          'totalBilledCentavos': result.totalBilledCentavos,
          'totalUnallocatedCentavos': result.totalUnallocatedCentavos,
          'statements': result.statements.map(_roomStatementToMap).toList(),
          'warnings': result.warnings,
          'createdBy': ownerId,
          'createdAt': now,
        });
        transaction.set(controlRef, {
          'billingCycleId': cycleId,
          'state': BillingCycleState.active.name,
          'totalBilledCentavos': result.totalBilledCentavos,
          'totalPaidCentavos': 0,
          'outstandingCentavos': result.totalBilledCentavos,
          'voidReason': null,
          'voidedAt': null,
          'reissuedAsCycleId': null,
          'lastPaymentId': null,
          'createdAt': now,
          'updatedAt': now,
        });
        if (period.exists) {
          transaction.update(periodRef, {
            'activeCycleId': cycleId,
            'latestCycleId': cycleId,
            'latestVersion': version,
            'updatedAt': now,
          });
          if (replacesCycleId != null) {
            transaction.update(
              _collection(ownerId, 'roomBillingControls').doc(replacesCycleId),
              {'reissuedAsCycleId': cycleId, 'updatedAt': now},
            );
          }
        } else {
          transaction.set(periodRef, {
            'periodId': periodId,
            'startDate': _date(result.startDate),
            'endDateExclusive': _date(result.endDateExclusive),
            'activeCycleId': cycleId,
            'latestCycleId': cycleId,
            'latestVersion': version,
            'createdAt': now,
            'updatedAt': now,
          });
        }
        for (final statement in result.statements) {
          final accountId = '${cycleId}_${statement.roomId}';
          transaction.set(
            _collection(ownerId, 'roomBillAccounts').doc(accountId),
            {
              'accountId': accountId,
              'billingCycleId': cycleId,
              'roomId': statement.roomId,
              'roomName': statement.roomName,
              'totalChargesCentavos': statement.currentChargesCentavos,
              'totalPaidCentavos': 0,
              'lastPaymentId': null,
              'createdAt': now,
              'updatedAt': now,
            },
          );
        }
        return cycleId;
      });
    });
  }

  @override
  Future<String> finalizeUtilityBillingBatch({
    required String ownerId,
    required UtilityBillingResult result,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateUtilityResult(result);
    final billingRef = _collection(ownerId, 'utilityBillingBatches').doc();
    final electricityRef = _collection(
      ownerId,
      'electricityReadingBatches',
    ).doc(result.electricityBatchId);
    final waterRef = _collection(
      ownerId,
      'waterBillingBatches',
    ).doc(result.waterBatchId);
    return _guard(() async {
      return _firestore.runTransaction((transaction) async {
        final house = await transaction.get(_house(ownerId));
        final electricity = await transaction.get(electricityRef);
        final water = await transaction.get(waterRef);
        if (!house.exists) throw _notFound('The boarding house was not found.');
        if (!electricity.exists || !water.exists) {
          throw _notFound('A selected utility batch no longer exists.');
        }
        final electricityData = electricity.data()!;
        final waterData = water.data()!;
        if (electricityData['status'] !=
                ElectricityReadingBatchStatus.finalized.name ||
            waterData['status'] != WaterBillingBatchStatus.finalized.name) {
          throw const MonthlyBillingRepositoryException(
            'A selected utility batch was already used or changed. Refresh and choose available batches.',
            code: 'utility-source-conflict',
            isConflict: true,
          );
        }
        _validateUtilitySources(
          result: result,
          electricity: electricityData,
          water: waterData,
        );
        final now = FieldValue.serverTimestamp();
        final reference = _utilityBatchReference(
          result.issuedOn,
          billingRef.id,
        );
        transaction.set(billingRef, {
          'billingBatchId': billingRef.id,
          'billingBatchReference': reference,
          'status': UtilityBillingBatchStatus.finalized.name,
          'issuedOn': _date(result.issuedOn),
          'electricityBatchId': result.electricityBatchId,
          'electricityBatchReference': result.electricityBatchReference,
          'electricityMeasurementStart': _date(
            result.electricityMeasurementStart,
          ),
          'electricityMeasurementEnd': _date(result.electricityMeasurementEnd),
          'electricityRateMicropesosPerKwh':
              result.electricityRateMicropesosPerKwh,
          'sourceReadingIds': result.sourceReadingIds,
          'waterBatchId': result.waterBatchId,
          'waterBatchReference': result.waterBatchReference,
          'waterPeriodStart': _date(result.waterPeriodStart),
          'waterPeriodEndExclusive': _date(result.waterPeriodEndExclusive),
          'waterReceiptDate': _date(result.waterReceiptDate),
          'waterMethod': result.waterMethod.name,
          'waterSummerBasis': result.waterSummerBasis.name,
          'waterReferenceElectricityBatchId':
              result.waterReferenceElectricityBatchId,
          'waterReferenceElectricityBatchReference':
              result.waterReferenceElectricityBatchReference,
          'associationMismatchConfirmed': result.associationMismatchConfirmed,
          'electricityTotalCentavos': result.electricityTotalCentavos,
          'waterTotalCentavos': result.waterTotalCentavos,
          'adjustmentTotalCentavos': result.adjustmentTotalCentavos,
          'totalBilledCentavos': result.totalBilledCentavos,
          'totalUnallocatedCentavos': result.totalUnallocatedCentavos,
          'statements': result.statements.map(_utilityStatementToMap).toList(),
          'warnings': result.warnings,
          'createdBy': ownerId,
          'createdAt': now,
          'voidReason': null,
          'voidedAt': null,
        });
        transaction.update(electricityRef, {
          'status': ElectricityReadingBatchStatus.usedInBilling.name,
          'billingBatchId': billingRef.id,
          'version': _integer(electricityData['version'], 'version') + 1,
          'usedAt': now,
          'updatedAt': now,
        });
        transaction.update(waterRef, {
          'status': WaterBillingBatchStatus.usedInBilling.name,
          'billingBatchId': billingRef.id,
          'version': _integer(waterData['version'], 'version') + 1,
          'usedAt': now,
          'updatedAt': now,
        });
        for (final statement in result.statements) {
          final accountId = '${billingRef.id}_${statement.roomId}';
          transaction.set(
            _collection(ownerId, 'utilityRoomBillAccounts').doc(accountId),
            {
              'accountId': accountId,
              'billingBatchId': billingRef.id,
              'roomId': statement.roomId,
              'roomName': statement.roomName,
              'totalChargesCentavos': statement.totalCentavos,
              'totalPaidCentavos': 0,
              'lastPaymentId': null,
              'createdAt': now,
              'updatedAt': now,
            },
          );
        }
        return billingRef.id;
      });
    });
  }

  @override
  Future<void> voidCycle({
    required String ownerId,
    required String billingCycleId,
    required String reason,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(billingCycleId, 'Billing cycle');
    final cleanReason = reason.trim();
    if (cleanReason.length < 3 || cleanReason.length > 500) {
      throw const MonthlyBillingRepositoryException(
        'Enter a correction reason between 3 and 500 characters.',
        code: 'invalid-void-reason',
      );
    }
    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final cycleRef = _collection(
          ownerId,
          'monthlyBillingCycles',
        ).doc(billingCycleId);
        final controlRef = _collection(
          ownerId,
          'billingCycleControls',
        ).doc(billingCycleId);
        final cycle = await transaction.get(cycleRef);
        final control = await transaction.get(controlRef);
        if (!cycle.exists || !control.exists) {
          throw _notFound('The billing cycle was not found.');
        }
        final controlData = control.data()!;
        if (controlData['state'] != BillingCycleState.active.name) {
          throw const MonthlyBillingRepositoryException(
            'This billing cycle is already voided.',
            code: 'billing-cycle-already-voided',
            isConflict: true,
          );
        }
        if (_integer(controlData['totalPaidCentavos'], 'totalPaidCentavos') !=
            0) {
          throw const MonthlyBillingRepositoryException(
            'A cycle with payments cannot be voided. Keep the payment history and issue a documented adjustment instead.',
            code: 'paid-cycle-cannot-be-voided',
            isConflict: true,
          );
        }
        final periodId = _string(cycle.data()!['periodId'], 'periodId');
        final periodRef = _collection(ownerId, 'billingPeriods').doc(periodId);
        final period = await transaction.get(periodRef);
        if (!period.exists ||
            period.data()!['activeCycleId'] != billingCycleId) {
          throw const MonthlyBillingRepositoryException(
            'The active billing-period pointer is inconsistent.',
            code: 'billing-period-conflict',
            isConflict: true,
          );
        }
        final now = FieldValue.serverTimestamp();
        transaction.update(controlRef, {
          'state': BillingCycleState.voided.name,
          'voidReason': cleanReason,
          'voidedAt': now,
          'updatedAt': now,
        });
        transaction.update(periodRef, {
          'activeCycleId': null,
          'updatedAt': now,
        });
      });
    });
  }

  @override
  Future<void> voidRoomCycle({
    required String ownerId,
    required String billingCycleId,
    required String reason,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(billingCycleId, 'Billing cycle');
    final cleanReason = reason.trim();
    if (cleanReason.length < 3 || cleanReason.length > 500) {
      throw const MonthlyBillingRepositoryException(
        'Enter a correction reason between 3 and 500 characters.',
        code: 'invalid-void-reason',
      );
    }
    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final cycleRef = _collection(
          ownerId,
          'roomBillingCycles',
        ).doc(billingCycleId);
        final controlRef = _collection(
          ownerId,
          'roomBillingControls',
        ).doc(billingCycleId);
        final cycle = await transaction.get(cycleRef);
        final control = await transaction.get(controlRef);
        if (!cycle.exists || !control.exists) {
          throw _notFound('The room billing cycle was not found.');
        }
        final controlData = control.data()!;
        if (controlData['state'] != BillingCycleState.active.name) {
          throw const MonthlyBillingRepositoryException(
            'This room billing cycle is already voided.',
            code: 'billing-cycle-already-voided',
            isConflict: true,
          );
        }
        if (_integer(controlData['totalPaidCentavos'], 'totalPaidCentavos') !=
            0) {
          throw const MonthlyBillingRepositoryException(
            'A room bill with payments cannot be voided. Use a documented adjustment instead.',
            code: 'paid-cycle-cannot-be-voided',
            isConflict: true,
          );
        }
        final periodId = _string(cycle.data()!['periodId'], 'periodId');
        final periodRef = _collection(
          ownerId,
          'roomBillingPeriods',
        ).doc(periodId);
        final period = await transaction.get(periodRef);
        if (!period.exists ||
            period.data()!['activeCycleId'] != billingCycleId) {
          throw const MonthlyBillingRepositoryException(
            'The active room billing-period pointer is inconsistent.',
            code: 'billing-period-conflict',
            isConflict: true,
          );
        }
        final now = FieldValue.serverTimestamp();
        transaction.update(controlRef, {
          'state': BillingCycleState.voided.name,
          'voidReason': cleanReason,
          'voidedAt': now,
          'updatedAt': now,
        });
        transaction.update(periodRef, {
          'activeCycleId': null,
          'updatedAt': now,
        });
      });
    });
  }

  @override
  Future<String> recordPayment({
    required String ownerId,
    required String billingCycleId,
    required String boarderId,
    required int amountCentavos,
    required BusinessDate paymentDate,
    required PaymentMethod method,
    String? notes,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(billingCycleId, 'Billing cycle');
    _validateId(boarderId, 'Boarder');
    if (amountCentavos <= 0 || amountCentavos > _maximumAmountCentavos) {
      throw const MonthlyBillingRepositoryException(
        'Enter a payment greater than zero.',
        code: 'invalid-payment-amount',
      );
    }
    if (paymentDate.isAfter(BusinessDate.todayInManila())) {
      throw const MonthlyBillingRepositoryException(
        'A payment date cannot be in the future.',
        code: 'future-payment-date',
      );
    }
    final cleanNotes = notes?.trim();
    if ((cleanNotes?.length ?? 0) > 500) {
      throw const MonthlyBillingRepositoryException(
        'Payment notes must be 500 characters or fewer.',
        code: 'payment-notes-too-long',
      );
    }
    final accountId = '${billingCycleId}_$boarderId';
    final paymentRef = _collection(ownerId, 'payments').doc();
    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final controlRef = _collection(
          ownerId,
          'billingCycleControls',
        ).doc(billingCycleId);
        final accountRef = _collection(
          ownerId,
          'boarderBillAccounts',
        ).doc(accountId);
        final control = await transaction.get(controlRef);
        final account = await transaction.get(accountRef);
        if (!control.exists || !account.exists) {
          throw _notFound('The boarder bill was not found.');
        }
        if (control.data()!['state'] != BillingCycleState.active.name) {
          throw const MonthlyBillingRepositoryException(
            'Payments cannot be added to a voided cycle.',
            code: 'voided-cycle-payment',
            isConflict: true,
          );
        }
        final accountData = account.data()!;
        final accountPaid = _integer(
          accountData['totalPaidCentavos'],
          'totalPaidCentavos',
        );
        final accountTotal = _integer(
          accountData['totalChargesCentavos'],
          'totalChargesCentavos',
        );
        if (amountCentavos > accountTotal - accountPaid) {
          throw const MonthlyBillingRepositoryException(
            'This payment is greater than the remaining balance. Credits are not enabled yet.',
            code: 'payment-exceeds-balance',
            isConflict: true,
          );
        }
        final controlData = control.data()!;
        final controlPaid = _integer(
          controlData['totalPaidCentavos'],
          'totalPaidCentavos',
        );
        final controlTotal = _integer(
          controlData['totalBilledCentavos'],
          'totalBilledCentavos',
        );
        final newAccountPaid = accountPaid + amountCentavos;
        final newControlPaid = controlPaid + amountCentavos;
        final now = FieldValue.serverTimestamp();
        transaction.set(paymentRef, {
          'paymentId': paymentRef.id,
          'billingCycleId': billingCycleId,
          'accountId': accountId,
          'boarderId': boarderId,
          'boarderName': _string(accountData['boarderName'], 'boarderName'),
          'amountCentavos': amountCentavos,
          'paymentDate': _date(paymentDate),
          'method': method.name,
          'notes': cleanNotes?.isEmpty == true ? null : cleanNotes,
          'createdBy': ownerId,
          'createdAt': now,
        });
        transaction.update(accountRef, {
          'totalPaidCentavos': newAccountPaid,
          'lastPaymentId': paymentRef.id,
          'updatedAt': now,
        });
        transaction.update(controlRef, {
          'totalPaidCentavos': newControlPaid,
          'outstandingCentavos': controlTotal - newControlPaid,
          'lastPaymentId': paymentRef.id,
          'updatedAt': now,
        });
      });
    });
    return paymentRef.id;
  }

  @override
  Future<String> recordRoomPayment({
    required String ownerId,
    required String billingCycleId,
    required String roomId,
    required int amountCentavos,
    required BusinessDate paymentDate,
    required PaymentMethod method,
    String? notes,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(billingCycleId, 'Billing cycle');
    _validateId(roomId, 'Room');
    if (amountCentavos <= 0 || amountCentavos > _maximumAmountCentavos) {
      throw const MonthlyBillingRepositoryException(
        'Enter a payment greater than zero.',
        code: 'invalid-payment-amount',
      );
    }
    if (paymentDate.isAfter(BusinessDate.todayInManila())) {
      throw const MonthlyBillingRepositoryException(
        'A payment date cannot be in the future.',
        code: 'future-payment-date',
      );
    }
    final cleanNotes = notes?.trim();
    if ((cleanNotes?.length ?? 0) > 500) {
      throw const MonthlyBillingRepositoryException(
        'Payment notes must be 500 characters or fewer.',
        code: 'payment-notes-too-long',
      );
    }
    final accountId = '${billingCycleId}_$roomId';
    final paymentRef = _collection(ownerId, 'roomPayments').doc();
    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final controlRef = _collection(
          ownerId,
          'roomBillingControls',
        ).doc(billingCycleId);
        final accountRef = _collection(
          ownerId,
          'roomBillAccounts',
        ).doc(accountId);
        final control = await transaction.get(controlRef);
        final account = await transaction.get(accountRef);
        if (!control.exists || !account.exists) {
          throw _notFound('The room bill was not found.');
        }
        if (control.data()!['state'] != BillingCycleState.active.name) {
          throw const MonthlyBillingRepositoryException(
            'Payments cannot be added to a voided room bill.',
            code: 'voided-cycle-payment',
            isConflict: true,
          );
        }
        final accountData = account.data()!;
        final accountPaid = _integer(
          accountData['totalPaidCentavos'],
          'totalPaidCentavos',
        );
        final accountTotal = _integer(
          accountData['totalChargesCentavos'],
          'totalChargesCentavos',
        );
        if (amountCentavos > accountTotal - accountPaid) {
          throw const MonthlyBillingRepositoryException(
            'This payment is greater than the remaining room balance.',
            code: 'payment-exceeds-balance',
            isConflict: true,
          );
        }
        final controlData = control.data()!;
        final controlPaid = _integer(
          controlData['totalPaidCentavos'],
          'totalPaidCentavos',
        );
        final controlTotal = _integer(
          controlData['totalBilledCentavos'],
          'totalBilledCentavos',
        );
        final newAccountPaid = accountPaid + amountCentavos;
        final newControlPaid = controlPaid + amountCentavos;
        final now = FieldValue.serverTimestamp();
        transaction.set(paymentRef, {
          'paymentId': paymentRef.id,
          'billingCycleId': billingCycleId,
          'accountId': accountId,
          'roomId': roomId,
          'roomName': _string(accountData['roomName'], 'roomName'),
          'amountCentavos': amountCentavos,
          'paymentDate': _date(paymentDate),
          'method': method.name,
          'notes': cleanNotes?.isEmpty == true ? null : cleanNotes,
          'createdBy': ownerId,
          'createdAt': now,
        });
        transaction.update(accountRef, {
          'totalPaidCentavos': newAccountPaid,
          'lastPaymentId': paymentRef.id,
          'updatedAt': now,
        });
        transaction.update(controlRef, {
          'totalPaidCentavos': newControlPaid,
          'outstandingCentavos': controlTotal - newControlPaid,
          'lastPaymentId': paymentRef.id,
          'updatedAt': now,
        });
      });
    });
    return paymentRef.id;
  }

  @override
  Future<String> recordUtilityRoomPayment({
    required String ownerId,
    required String billingBatchId,
    required String roomId,
    required int amountCentavos,
    required BusinessDate paymentDate,
    required PaymentMethod method,
    String? notes,
  }) async {
    _validateId(ownerId, 'Owner');
    _validateId(billingBatchId, 'Billing batch');
    _validateId(roomId, 'Room');
    if (amountCentavos <= 0 || amountCentavos > _maximumAmountCentavos) {
      throw const MonthlyBillingRepositoryException(
        'Enter a payment greater than zero.',
        code: 'invalid-payment-amount',
      );
    }
    if (paymentDate.isAfter(BusinessDate.todayInManila())) {
      throw const MonthlyBillingRepositoryException(
        'A payment date cannot be in the future.',
        code: 'future-payment-date',
      );
    }
    final cleanNotes = notes?.trim();
    if ((cleanNotes?.length ?? 0) > 500) {
      throw const MonthlyBillingRepositoryException(
        'Payment notes must be 500 characters or fewer.',
        code: 'payment-notes-too-long',
      );
    }
    final accountId = '${billingBatchId}_$roomId';
    final paymentRef = _collection(ownerId, 'utilityRoomPayments').doc();
    await _guard(() {
      return _firestore.runTransaction((transaction) async {
        final billingRef = _collection(
          ownerId,
          'utilityBillingBatches',
        ).doc(billingBatchId);
        final accountRef = _collection(
          ownerId,
          'utilityRoomBillAccounts',
        ).doc(accountId);
        final billing = await transaction.get(billingRef);
        final account = await transaction.get(accountRef);
        if (!billing.exists || !account.exists) {
          throw _notFound('The room utility bill was not found.');
        }
        if (billing.data()!['status'] !=
            UtilityBillingBatchStatus.finalized.name) {
          throw const MonthlyBillingRepositoryException(
            'Payments cannot be added to a voided utility bill.',
            code: 'voided-utility-bill-payment',
            isConflict: true,
          );
        }
        final accountData = account.data()!;
        final accountPaid = _integer(
          accountData['totalPaidCentavos'],
          'totalPaidCentavos',
        );
        final accountTotal = _integer(
          accountData['totalChargesCentavos'],
          'totalChargesCentavos',
        );
        if (amountCentavos > accountTotal - accountPaid) {
          throw const MonthlyBillingRepositoryException(
            'This payment is greater than the remaining room balance.',
            code: 'payment-exceeds-balance',
            isConflict: true,
          );
        }
        final now = FieldValue.serverTimestamp();
        transaction.set(paymentRef, {
          'paymentId': paymentRef.id,
          'billingBatchId': billingBatchId,
          'accountId': accountId,
          'roomId': roomId,
          'roomName': _string(accountData['roomName'], 'roomName'),
          'amountCentavos': amountCentavos,
          'paymentDate': _date(paymentDate),
          'method': method.name,
          'notes': cleanNotes?.isEmpty == true ? null : cleanNotes,
          'createdBy': ownerId,
          'createdAt': now,
        });
        transaction.update(accountRef, {
          'totalPaidCentavos': accountPaid + amountCentavos,
          'lastPaymentId': paymentRef.id,
          'updatedAt': now,
        });
      });
    });
    return paymentRef.id;
  }

  Map<String, dynamic> _statementToMap(BoarderMonthlyStatement value) => {
    'boarderId': value.boarderId,
    'boarderName': value.boarderName,
    'roomIds': value.roomIds,
    'rentCentavos': value.rentCentavos,
    'rentAdjustmentCentavos': value.rentAdjustmentCentavos,
    'electricityCentavos': value.electricityCentavos,
    'waterCentavos': value.waterCentavos,
    'currentChargesCentavos': value.currentChargesCentavos,
    'previousBalanceCentavos': value.previousBalanceCentavos,
  };

  Map<String, dynamic> _roomStatementToMap(RoomMonthlyStatement value) => {
    'roomId': value.roomId,
    'roomName': value.roomName,
    'occupiedRanges': value.occupiedRanges
        .map(
          (range) => {
            'startDate': _date(range.startDate),
            'endDateExclusive': _date(range.endDateExclusive),
          },
        )
        .toList(),
    'occupiedDays': value.occupiedDays,
    'rentCentavos': value.rentCentavos,
    'adjustmentCentavos': value.adjustmentCentavos,
    'electricityCentavos': value.electricityCentavos,
    'waterCentavos': value.waterCentavos,
    'currentChargesCentavos': value.currentChargesCentavos,
  };

  Map<String, dynamic> _utilityStatementToMap(RoomUtilityBillStatement value) =>
      {
        'roomId': value.roomId,
        'roomName': value.roomName,
        'electricityCentavos': value.electricityCentavos,
        'waterCentavos': value.waterCentavos,
        'adjustmentCentavos': value.adjustmentCentavos,
        'totalCentavos': value.totalCentavos,
      };

  UtilityBillingBatch _utilityBatchFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    if (_string(data['billingBatchId'], 'billingBatchId') != doc.id) {
      throw _schema('A utility billing batch has an inconsistent identifier.');
    }
    return UtilityBillingBatch(
      billingBatchId: doc.id,
      billingBatchReference: _string(
        data['billingBatchReference'],
        'billingBatchReference',
      ),
      status: _enumValue(
        UtilityBillingBatchStatus.values,
        data['status'],
        'status',
      ),
      issuedOn: _businessDate(data['issuedOn'], 'issuedOn'),
      electricityBatchId: _string(
        data['electricityBatchId'],
        'electricityBatchId',
      ),
      electricityBatchReference: _string(
        data['electricityBatchReference'],
        'electricityBatchReference',
      ),
      electricityMeasurementStart: _businessDate(
        data['electricityMeasurementStart'],
        'electricityMeasurementStart',
      ),
      electricityMeasurementEnd: _businessDate(
        data['electricityMeasurementEnd'],
        'electricityMeasurementEnd',
      ),
      electricityRateMicropesosPerKwh: _integer(
        data['electricityRateMicropesosPerKwh'],
        'electricityRateMicropesosPerKwh',
      ),
      sourceReadingIds: _stringList(
        data['sourceReadingIds'],
        'sourceReadingIds',
      ),
      waterBatchId: _string(data['waterBatchId'], 'waterBatchId'),
      waterBatchReference: _string(
        data['waterBatchReference'],
        'waterBatchReference',
      ),
      waterPeriodStart: _businessDate(
        data['waterPeriodStart'],
        'waterPeriodStart',
      ),
      waterPeriodEndExclusive: _businessDate(
        data['waterPeriodEndExclusive'],
        'waterPeriodEndExclusive',
      ),
      waterReceiptDate: _businessDate(
        data['waterReceiptDate'],
        'waterReceiptDate',
      ),
      waterMethod: _enumValue(
        WaterBillingMethod.values,
        data['waterMethod'],
        'waterMethod',
      ),
      waterSummerBasis: _enumValue(
        SummerElectricityBasis.values,
        data['waterSummerBasis'],
        'waterSummerBasis',
      ),
      waterReferenceElectricityBatchId: _optionalString(
        data['waterReferenceElectricityBatchId'],
        'waterReferenceElectricityBatchId',
      ),
      waterReferenceElectricityBatchReference: _optionalString(
        data['waterReferenceElectricityBatchReference'],
        'waterReferenceElectricityBatchReference',
      ),
      associationMismatchConfirmed: _boolean(
        data['associationMismatchConfirmed'],
        'associationMismatchConfirmed',
      ),
      electricityTotalCentavos: _integer(
        data['electricityTotalCentavos'],
        'electricityTotalCentavos',
      ),
      waterTotalCentavos: _integer(
        data['waterTotalCentavos'],
        'waterTotalCentavos',
      ),
      adjustmentTotalCentavos: _integer(
        data['adjustmentTotalCentavos'],
        'adjustmentTotalCentavos',
      ),
      totalBilledCentavos: _integer(
        data['totalBilledCentavos'],
        'totalBilledCentavos',
      ),
      totalUnallocatedCentavos: _integer(
        data['totalUnallocatedCentavos'],
        'totalUnallocatedCentavos',
      ),
      statements: _list(
        data['statements'],
        'statements',
      ).map(_utilityStatementFromMap).toList(),
      warnings: _stringList(data['warnings'], 'warnings'),
      createdAt: _dateTime(data['createdAt'], 'createdAt'),
      voidReason: _optionalString(data['voidReason'], 'voidReason'),
      voidedAt: _optionalDateTime(data['voidedAt'], 'voidedAt'),
    );
  }

  RoomUtilityBillStatement _utilityStatementFromMap(Object? raw) {
    if (raw is! Map) throw _schema('A room utility statement is malformed.');
    final data = Map<String, dynamic>.from(raw);
    return RoomUtilityBillStatement(
      roomId: _string(data['roomId'], 'roomId'),
      roomName: _string(data['roomName'], 'roomName'),
      electricityCentavos: _integer(
        data['electricityCentavos'],
        'electricityCentavos',
      ),
      waterCentavos: _integer(data['waterCentavos'], 'waterCentavos'),
      adjustmentCentavos: _integer(
        data['adjustmentCentavos'],
        'adjustmentCentavos',
      ),
      totalCentavos: _integer(data['totalCentavos'], 'totalCentavos'),
    );
  }

  RoomBillingCycle _roomCycleFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    if (_string(data['billingCycleId'], 'billingCycleId') != doc.id ||
        data['billingModel'] != 'roomV2') {
      throw _schema('A room billing cycle has an inconsistent identifier.');
    }
    return RoomBillingCycle(
      billingCycleId: doc.id,
      periodId: _string(data['periodId'], 'periodId'),
      version: _integer(data['version'], 'version'),
      replacesCycleId: _optionalString(
        data['replacesCycleId'],
        'replacesCycleId',
      ),
      startDate: _businessDate(data['startDate'], 'startDate'),
      endDateExclusive: _businessDate(
        data['endDateExclusive'],
        'endDateExclusive',
      ),
      electricityRecordId: _string(
        data['electricityRecordId'],
        'electricityRecordId',
      ),
      waterRecordId: _string(data['waterRecordId'], 'waterRecordId'),
      rentRecordId: _string(data['rentRecordId'], 'rentRecordId'),
      electricityTotalCentavos: _integer(
        data['electricityTotalCentavos'],
        'electricityTotalCentavos',
      ),
      waterTotalCentavos: _integer(
        data['waterTotalCentavos'],
        'waterTotalCentavos',
      ),
      rentTotalCentavos: _integer(
        data['rentTotalCentavos'],
        'rentTotalCentavos',
      ),
      adjustmentTotalCentavos: _integer(
        data['adjustmentTotalCentavos'],
        'adjustmentTotalCentavos',
      ),
      totalBilledCentavos: _integer(
        data['totalBilledCentavos'],
        'totalBilledCentavos',
      ),
      totalUnallocatedCentavos: _integer(
        data['totalUnallocatedCentavos'],
        'totalUnallocatedCentavos',
      ),
      statements: _list(
        data['statements'],
        'statements',
      ).map(_roomStatementFromMap).toList(),
      warnings: _stringList(data['warnings'], 'warnings'),
      finalizedAt: _dateTime(data['createdAt'], 'createdAt'),
    );
  }

  RoomMonthlyStatement _roomStatementFromMap(Object? raw) {
    if (raw is! Map) throw _schema('A room statement is malformed.');
    final data = Map<String, dynamic>.from(raw);
    final ranges = _list(data['occupiedRanges'], 'occupiedRanges').map((raw) {
      if (raw is! Map) throw _schema('An occupied range is malformed.');
      final range = Map<String, dynamic>.from(raw);
      return OccupiedDateRange(
        startDate: _businessDate(range['startDate'], 'range.startDate'),
        endDateExclusive: _businessDate(
          range['endDateExclusive'],
          'range.endDateExclusive',
        ),
      );
    }).toList();
    return RoomMonthlyStatement(
      roomId: _string(data['roomId'], 'roomId'),
      roomName: _string(data['roomName'], 'roomName'),
      occupiedRanges: ranges,
      occupiedDays: _integer(data['occupiedDays'], 'occupiedDays'),
      rentCentavos: _integer(data['rentCentavos'], 'rentCentavos'),
      adjustmentCentavos: _integer(
        data['adjustmentCentavos'],
        'adjustmentCentavos',
      ),
      electricityCentavos: _integer(
        data['electricityCentavos'],
        'electricityCentavos',
      ),
      waterCentavos: _integer(data['waterCentavos'], 'waterCentavos'),
      currentChargesCentavos: _integer(
        data['currentChargesCentavos'],
        'currentChargesCentavos',
      ),
    );
  }

  MonthlyBillingCycle _cycleFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    if (_string(data['billingCycleId'], 'billingCycleId') != doc.id) {
      throw _schema('A billing cycle has an inconsistent identifier.');
    }
    return MonthlyBillingCycle(
      billingCycleId: doc.id,
      periodId: _string(data['periodId'], 'periodId'),
      version: _integer(data['version'], 'version'),
      replacesCycleId: _optionalString(
        data['replacesCycleId'],
        'replacesCycleId',
      ),
      startDate: _businessDate(data['startDate'], 'startDate'),
      endDateExclusive: _businessDate(
        data['endDateExclusive'],
        'endDateExclusive',
      ),
      electricityRecordId: _string(
        data['electricityRecordId'],
        'electricityRecordId',
      ),
      waterRecordId: _string(data['waterRecordId'], 'waterRecordId'),
      rentRecordId: _string(data['rentRecordId'], 'rentRecordId'),
      electricityTotalCentavos: _integer(
        data['electricityTotalCentavos'],
        'electricityTotalCentavos',
      ),
      waterTotalCentavos: _integer(
        data['waterTotalCentavos'],
        'waterTotalCentavos',
      ),
      rentTotalCentavos: _integer(
        data['rentTotalCentavos'],
        'rentTotalCentavos',
      ),
      rentAdjustmentCentavos: _integer(
        data['rentAdjustmentCentavos'],
        'rentAdjustmentCentavos',
      ),
      totalBilledCentavos: _integer(
        data['totalBilledCentavos'],
        'totalBilledCentavos',
      ),
      totalUnallocatedCentavos: _integer(
        data['totalUnallocatedCentavos'],
        'totalUnallocatedCentavos',
      ),
      statements: _list(
        data['statements'],
        'statements',
      ).map(_statementFromMap).toList(),
      warnings: _stringList(data['warnings'], 'warnings'),
      finalizedAt: _dateTime(data['createdAt'], 'createdAt'),
    );
  }

  BoarderMonthlyStatement _statementFromMap(Object? raw) {
    if (raw is! Map) throw _schema('A boarder statement is malformed.');
    final data = Map<String, dynamic>.from(raw);
    return BoarderMonthlyStatement(
      boarderId: _string(data['boarderId'], 'boarderId'),
      boarderName: _string(data['boarderName'], 'boarderName'),
      roomIds: _stringList(data['roomIds'], 'roomIds'),
      rentCentavos: _integer(data['rentCentavos'], 'rentCentavos'),
      rentAdjustmentCentavos: _integer(
        data['rentAdjustmentCentavos'],
        'rentAdjustmentCentavos',
      ),
      electricityCentavos: _integer(
        data['electricityCentavos'],
        'electricityCentavos',
      ),
      waterCentavos: _integer(data['waterCentavos'], 'waterCentavos'),
      currentChargesCentavos: _integer(
        data['currentChargesCentavos'],
        'currentChargesCentavos',
      ),
      previousBalanceCentavos: _integer(
        data['previousBalanceCentavos'],
        'previousBalanceCentavos',
      ),
    );
  }

  BillingCycleControl _controlFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return BillingCycleControl(
      billingCycleId: _matchingId(data, doc.id, 'billingCycleId'),
      state: _enumValue(BillingCycleState.values, data['state'], 'state'),
      totalBilledCentavos: _integer(
        data['totalBilledCentavos'],
        'totalBilledCentavos',
      ),
      totalPaidCentavos: _integer(
        data['totalPaidCentavos'],
        'totalPaidCentavos',
      ),
      outstandingCentavos: _integer(
        data['outstandingCentavos'],
        'outstandingCentavos',
      ),
      voidReason: _optionalString(data['voidReason'], 'voidReason'),
      voidedAt: _optionalDateTime(data['voidedAt'], 'voidedAt'),
      reissuedAsCycleId: _optionalString(
        data['reissuedAsCycleId'],
        'reissuedAsCycleId',
      ),
      updatedAt: _dateTime(data['updatedAt'], 'updatedAt'),
    );
  }

  BoarderBillAccount _accountFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return BoarderBillAccount(
      accountId: _matchingId(data, doc.id, 'accountId'),
      billingCycleId: _string(data['billingCycleId'], 'billingCycleId'),
      boarderId: _string(data['boarderId'], 'boarderId'),
      boarderName: _string(data['boarderName'], 'boarderName'),
      totalChargesCentavos: _integer(
        data['totalChargesCentavos'],
        'totalChargesCentavos',
      ),
      previousBalanceCentavos: _integer(
        data['previousBalanceCentavos'],
        'previousBalanceCentavos',
      ),
      totalPaidCentavos: _integer(
        data['totalPaidCentavos'],
        'totalPaidCentavos',
      ),
      updatedAt: _dateTime(data['updatedAt'], 'updatedAt'),
    );
  }

  RoomBillAccount _roomAccountFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return RoomBillAccount(
      accountId: _matchingId(data, doc.id, 'accountId'),
      billingCycleId: _string(data['billingCycleId'], 'billingCycleId'),
      roomId: _string(data['roomId'], 'roomId'),
      roomName: _string(data['roomName'], 'roomName'),
      totalChargesCentavos: _integer(
        data['totalChargesCentavos'],
        'totalChargesCentavos',
      ),
      totalPaidCentavos: _integer(
        data['totalPaidCentavos'],
        'totalPaidCentavos',
      ),
      updatedAt: _dateTime(data['updatedAt'], 'updatedAt'),
    );
  }

  UtilityRoomBillAccount _utilityRoomAccountFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return UtilityRoomBillAccount(
      accountId: _matchingId(data, doc.id, 'accountId'),
      billingBatchId: _string(data['billingBatchId'], 'billingBatchId'),
      roomId: _string(data['roomId'], 'roomId'),
      roomName: _string(data['roomName'], 'roomName'),
      totalChargesCentavos: _integer(
        data['totalChargesCentavos'],
        'totalChargesCentavos',
      ),
      totalPaidCentavos: _integer(
        data['totalPaidCentavos'],
        'totalPaidCentavos',
      ),
      createdAt: _dateTime(data['createdAt'], 'createdAt'),
      updatedAt: _dateTime(data['updatedAt'], 'updatedAt'),
    );
  }

  PaymentRecord _paymentFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return PaymentRecord(
      paymentId: _matchingId(data, doc.id, 'paymentId'),
      billingCycleId: _string(data['billingCycleId'], 'billingCycleId'),
      boarderId: _string(data['boarderId'], 'boarderId'),
      boarderName: _string(data['boarderName'], 'boarderName'),
      amountCentavos: _integer(data['amountCentavos'], 'amountCentavos'),
      paymentDate: _businessDate(data['paymentDate'], 'paymentDate'),
      method: _enumValue(PaymentMethod.values, data['method'], 'method'),
      notes: _optionalString(data['notes'], 'notes'),
      recordedAt: _dateTime(data['createdAt'], 'createdAt'),
    );
  }

  RoomPaymentRecord _roomPaymentFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return RoomPaymentRecord(
      paymentId: _matchingId(data, doc.id, 'paymentId'),
      billingCycleId: _string(data['billingCycleId'], 'billingCycleId'),
      roomId: _string(data['roomId'], 'roomId'),
      roomName: _string(data['roomName'], 'roomName'),
      amountCentavos: _integer(data['amountCentavos'], 'amountCentavos'),
      paymentDate: _businessDate(data['paymentDate'], 'paymentDate'),
      method: _enumValue(PaymentMethod.values, data['method'], 'method'),
      notes: _optionalString(data['notes'], 'notes'),
      recordedAt: _dateTime(data['createdAt'], 'createdAt'),
    );
  }

  UtilityRoomPaymentRecord _utilityRoomPaymentFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return UtilityRoomPaymentRecord(
      paymentId: _matchingId(data, doc.id, 'paymentId'),
      billingBatchId: _string(data['billingBatchId'], 'billingBatchId'),
      accountId: _string(data['accountId'], 'accountId'),
      roomId: _string(data['roomId'], 'roomId'),
      roomName: _string(data['roomName'], 'roomName'),
      amountCentavos: _integer(data['amountCentavos'], 'amountCentavos'),
      paymentDate: _businessDate(data['paymentDate'], 'paymentDate'),
      method: _enumValue(PaymentMethod.values, data['method'], 'method'),
      notes: _optionalString(data['notes'], 'notes'),
      recordedAt: _dateTime(data['createdAt'], 'createdAt'),
    );
  }

  void _validateResult(MonthlyBillingResult result) {
    if (!result.startDate.isBefore(result.endDateExclusive) ||
        result.endDateExclusive.isAfter(BusinessDate.todayInManila()) ||
        result.startDate.daysUntil(result.endDateExclusive) > 366 ||
        result.statements.length > 400 ||
        result.warnings.length > 100) {
      throw const MonthlyBillingRepositoryException(
        'The monthly billing period or snapshot size is invalid.',
        code: 'invalid-monthly-billing-result',
      );
    }
    for (final id in [
      result.electricityRecordId,
      result.waterRecordId,
      result.rentRecordId,
    ]) {
      _validateId(id, 'Source record');
    }
    final ids = <String>{};
    var total = 0;
    for (final statement in result.statements) {
      _validateId(statement.boarderId, 'Boarder');
      if (!ids.add(statement.boarderId) ||
          statement.boarderName.trim().isEmpty ||
          statement.boarderName.length > 120 ||
          statement.currentChargesCentavos < 0 ||
          statement.previousBalanceCentavos < 0) {
        throw const MonthlyBillingRepositoryException(
          'A boarder statement is invalid.',
          code: 'invalid-boarder-statement',
        );
      }
      total += statement.currentChargesCentavos;
    }
    if (total != result.totalBilledCentavos ||
        total < 0 ||
        total > _maximumAmountCentavos ||
        result.totalUnallocatedCentavos < 0 ||
        result.totalUnallocatedCentavos > _maximumAmountCentavos) {
      throw const MonthlyBillingRepositoryException(
        'The monthly billing totals do not reconcile.',
        code: 'monthly-billing-totals-do-not-reconcile',
      );
    }
  }

  void _validateRoomResult(RoomBillingResult result) {
    final start = result.startDate;
    final expectedEnd = start.month == 12
        ? BusinessDate(start.year + 1, 1, 1)
        : BusinessDate(start.year, start.month + 1, 1);
    if (start.day != 1 ||
        result.endDateExclusive != expectedEnd ||
        result.endDateExclusive.isAfter(BusinessDate.todayInManila()) ||
        result.statements.isEmpty ||
        result.statements.length > 400 ||
        result.warnings.length > 100) {
      throw const MonthlyBillingRepositoryException(
        'The room billing month or snapshot size is invalid.',
        code: 'invalid-room-billing-result',
      );
    }
    for (final id in [
      result.electricityRecordId,
      result.waterRecordId,
      result.rentRecordId,
    ]) {
      _validateId(id, 'Source record');
    }
    if (result.rentRecordId != roomBillingNoRentRecordId ||
        result.rentTotalCentavos != 0 ||
        result.adjustmentTotalCentavos != 0) {
      throw const MonthlyBillingRepositoryException(
        'Room bills may include electricity and water only.',
        code: 'room-billing-rent-not-allowed',
      );
    }
    final ids = <String>{};
    var total = 0;
    for (final statement in result.statements) {
      _validateId(statement.roomId, 'Room');
      final rangeDays = statement.occupiedRanges.fold<int>(
        0,
        (runningTotal, range) => runningTotal + range.days,
      );
      if (!ids.add(statement.roomId) ||
          statement.roomName.trim().isEmpty ||
          statement.roomName.length > 120 ||
          statement.occupiedRanges.isEmpty ||
          rangeDays != statement.occupiedDays ||
          statement.occupiedDays <= 0 ||
          statement.rentCentavos != 0 ||
          statement.adjustmentCentavos != 0 ||
          statement.currentChargesCentavos !=
              statement.electricityCentavos + statement.waterCentavos ||
          statement.currentChargesCentavos < 0) {
        throw const MonthlyBillingRepositoryException(
          'A room statement is invalid.',
          code: 'invalid-room-statement',
        );
      }
      for (final range in statement.occupiedRanges) {
        if (range.startDate.isBefore(result.startDate) ||
            range.endDateExclusive.isAfter(result.endDateExclusive) ||
            !range.startDate.isBefore(range.endDateExclusive)) {
          throw const MonthlyBillingRepositoryException(
            'A room occupied range is invalid.',
            code: 'invalid-room-occupied-range',
          );
        }
      }
      total += statement.currentChargesCentavos;
    }
    if (total != result.totalBilledCentavos ||
        total < 0 ||
        total > _maximumAmountCentavos ||
        result.totalUnallocatedCentavos < 0 ||
        result.totalUnallocatedCentavos > _maximumAmountCentavos) {
      throw const MonthlyBillingRepositoryException(
        'The room billing totals do not reconcile.',
        code: 'room-billing-totals-do-not-reconcile',
      );
    }
  }

  void _validateUtilityResult(UtilityBillingResult result) {
    for (final id in [result.electricityBatchId, result.waterBatchId]) {
      _validateId(id, 'Utility batch');
    }
    if (result.issuedOn.isAfter(BusinessDate.todayInManila()) ||
        !result.electricityMeasurementStart.isBefore(
          result.electricityMeasurementEnd,
        ) ||
        !result.waterPeriodStart.isBefore(result.waterPeriodEndExclusive) ||
        result.statements.isEmpty ||
        result.statements.length > 500 ||
        result.sourceReadingIds.length > 2000 ||
        result.warnings.length > 100 ||
        result.adjustmentTotalCentavos != 0) {
      throw const MonthlyBillingRepositoryException(
        'The combined utility bill is outside the supported limits.',
        code: 'invalid-utility-billing-result',
      );
    }
    final roomIds = <String>{};
    var electricityTotal = 0;
    var waterTotal = 0;
    var grandTotal = 0;
    for (final statement in result.statements) {
      _validateId(statement.roomId, 'Room');
      if (!roomIds.add(statement.roomId) ||
          statement.roomName.trim().isEmpty ||
          statement.roomName.length > 120 ||
          statement.electricityCentavos < 0 ||
          statement.waterCentavos < 0 ||
          statement.adjustmentCentavos != 0 ||
          statement.totalCentavos !=
              statement.electricityCentavos + statement.waterCentavos ||
          statement.totalCentavos <= 0) {
        throw const MonthlyBillingRepositoryException(
          'A room utility statement is invalid.',
          code: 'invalid-room-utility-statement',
        );
      }
      electricityTotal += statement.electricityCentavos;
      waterTotal += statement.waterCentavos;
      grandTotal += statement.totalCentavos;
    }
    if (electricityTotal != result.electricityTotalCentavos ||
        waterTotal != result.waterTotalCentavos ||
        grandTotal != result.totalBilledCentavos ||
        result.totalBilledCentavos !=
            result.electricityTotalCentavos + result.waterTotalCentavos ||
        result.totalBilledCentavos < 0 ||
        result.totalBilledCentavos > _maximumAmountCentavos ||
        result.totalUnallocatedCentavos < 0 ||
        result.totalUnallocatedCentavos > _maximumAmountCentavos ||
        (result.hasDifferentWaterReference !=
            result.associationMismatchConfirmed)) {
      throw const MonthlyBillingRepositoryException(
        'The combined utility totals or source confirmation do not reconcile.',
        code: 'utility-billing-totals-do-not-reconcile',
      );
    }
  }

  void _validateUtilitySources({
    required UtilityBillingResult result,
    required Map<String, dynamic> electricity,
    required Map<String, dynamic> water,
  }) {
    final entries = _list(electricity['entries'], 'entries')
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['status'] == 'recorded')
        .toList();
    final readingIds = entries
        .map((item) => item['readingId'])
        .whereType<String>()
        .toSet();
    final suppliedReadingIds = result.sourceReadingIds.toSet();
    final starts = entries
        .map(
          (item) =>
              _businessDate(item['previousReadingDate'], 'previousReadingDate'),
        )
        .toList();
    final measurementStart = starts.isEmpty
        ? result.electricityMeasurementEnd
        : starts.reduce((a, b) => a.isBefore(b) ? a : b);
    final waterReferenceId = _optionalString(
      water['electricityBatchId'],
      'electricityBatchId',
    );
    final differentReference =
        waterReferenceId != null &&
        waterReferenceId != result.electricityBatchId;
    if (_string(electricity['batchId'], 'batchId') !=
            result.electricityBatchId ||
        _string(electricity['batchReference'], 'batchReference') !=
            result.electricityBatchReference ||
        _businessDate(electricity['effectiveDate'], 'effectiveDate') !=
            result.electricityMeasurementEnd ||
        measurementStart != result.electricityMeasurementStart ||
        _integer(electricity['rateMicropesosPerKwh'], 'rateMicropesosPerKwh') !=
            result.electricityRateMicropesosPerKwh ||
        _integer(electricity['totalChargeCentavos'], 'totalChargeCentavos') !=
            result.electricityTotalCentavos ||
        readingIds.length != suppliedReadingIds.length ||
        !readingIds.containsAll(suppliedReadingIds) ||
        _string(water['batchId'], 'batchId') != result.waterBatchId ||
        _string(water['batchReference'], 'batchReference') !=
            result.waterBatchReference ||
        _businessDate(water['startDate'], 'startDate') !=
            result.waterPeriodStart ||
        _businessDate(water['endDateExclusive'], 'endDateExclusive') !=
            result.waterPeriodEndExclusive ||
        _businessDate(water['receiptDate'], 'receiptDate') !=
            result.waterReceiptDate ||
        water['method'] != result.waterMethod.name ||
        water['summerBasis'] != result.waterSummerBasis.name ||
        waterReferenceId != result.waterReferenceElectricityBatchId ||
        _optionalString(
              water['electricityBatchReference'],
              'electricityBatchReference',
            ) !=
            result.waterReferenceElectricityBatchReference ||
        _integer(water['totalAllocatedCentavos'], 'totalAllocatedCentavos') !=
            result.waterTotalCentavos ||
        _integer(
              water['totalUnallocatedCentavos'],
              'totalUnallocatedCentavos',
            ) !=
            result.totalUnallocatedCentavos ||
        differentReference != result.associationMismatchConfirmed) {
      throw const MonthlyBillingRepositoryException(
        'A utility source changed after review. Refresh and review the latest snapshots.',
        code: 'utility-source-conflict',
        isConflict: true,
      );
    }
  }

  Timestamp _date(BusinessDate value) => Timestamp.fromDate(value.value);

  BusinessDate _businessDate(Object? value, String field) {
    if (value is! Timestamp) throw _schema('$field must be a date.');
    try {
      return BusinessDate.fromUtcDateTime(value.toDate());
    } catch (_) {
      throw _schema('$field must be a calendar date.');
    }
  }

  DateTime _dateTime(Object? value, String field) {
    if (value is! Timestamp) throw _schema('$field must be a timestamp.');
    return value.toDate();
  }

  DateTime? _optionalDateTime(Object? value, String field) =>
      value == null ? null : _dateTime(value, field);

  bool _boolean(Object? value, String field) {
    if (value is! bool) throw _schema('$field must be true or false.');
    return value;
  }

  String _matchingId(Map<String, dynamic> data, String id, String field) {
    final value = _string(data[field], field);
    if (value != id) throw _schema('$field does not match its document.');
    return value;
  }

  String _string(Object? value, String field) {
    if (value is! String || value.isEmpty) {
      throw _schema('$field must be a non-empty string.');
    }
    return value;
  }

  String _utilityBatchReference(BusinessDate issuedOn, String documentId) {
    final suffix = documentId
        .replaceAll(RegExp('[^A-Za-z0-9]'), '')
        .toUpperCase();
    final short = suffix.substring(0, suffix.length.clamp(0, 6));
    return 'UB-${issuedOn.year}-${issuedOn.month.toString().padLeft(2, '0')}-$short';
  }

  String? _optionalString(Object? value, String field) =>
      value == null ? null : _string(value, field);

  int _integer(Object? value, String field) {
    if (value is! int) throw _schema('$field must be an integer.');
    return value;
  }

  List<dynamic> _list(Object? value, String field) {
    if (value is! List) throw _schema('$field must be a list.');
    return value;
  }

  List<String> _stringList(Object? value, String field) {
    final list = _list(value, field);
    if (list.any((item) => item is! String)) {
      throw _schema('$field must contain strings.');
    }
    return List<String>.from(list);
  }

  T _enumValue<T extends Enum>(List<T> values, Object? raw, String field) {
    if (raw is! String) throw _schema('$field is invalid.');
    return values.where((value) => value.name == raw).firstOrNull ??
        (throw _schema('$field is invalid.'));
  }

  void _validateId(String value, String label) {
    if (value.trim().isEmpty || value.length > 300 || value.contains('/')) {
      throw MonthlyBillingRepositoryException(
        '$label identifier is invalid.',
        code: 'invalid-identifier',
      );
    }
  }

  MonthlyBillingRepositoryException _schema(String message) =>
      MonthlyBillingRepositoryException(message, code: 'invalid-schema');

  MonthlyBillingRepositoryException _notFound(String message) =>
      MonthlyBillingRepositoryException(message, code: 'not-found');

  Stream<T> _mapped<T>(Stream<T> stream) => stream.transform(
    StreamTransformer<T, T>.fromHandlers(
      handleError: (error, stack, sink) =>
          sink.addError(_mapError(error), stack),
    ),
  );

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      throw _mapError(error);
    }
  }

  Object _mapError(Object error) {
    if (error is MonthlyBillingRepositoryException) return error;
    if (error is FirebaseException) {
      final offline =
          error.code == 'unavailable' || error.code == 'deadline-exceeded';
      return MonthlyBillingRepositoryException(
        offline
            ? 'The billing service is unavailable. Check the connection and try again.'
            : error.code == 'permission-denied'
            ? 'This account cannot access these billing records.'
            : 'Billing could not be updated. Please try again.',
        code: error.code,
        isOffline: offline,
        isConflict: error.code == 'already-exists' || error.code == 'aborted',
      );
    }
    return const MonthlyBillingRepositoryException(
      'Billing data could not be read because it is malformed.',
      code: 'invalid-schema',
    );
  }
}
