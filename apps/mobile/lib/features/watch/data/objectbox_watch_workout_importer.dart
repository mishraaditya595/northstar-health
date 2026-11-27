import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/account_store.dart';
import '../../../core/storage/objectbox_store_provider.dart';
import '../../../objectbox.g.dart';
import '../../sync/completed_snapshot_writer.dart';
import '../../sync/objectbox_workout_restore_importer.dart'
    show RestoreImportException;
import '../../sync/workout_restore_feed.dart';
import '../../workouts/data/objectbox_workout_outbox.dart';
import '../../workouts/data/workout_entities.dart';
import '../../workouts/domain/workout_models.dart';
import 'watch_workout_receipt_entity.dart';

enum WatchImportResult { stored, duplicate, invalid }

/// Rolls the import transaction back; never leaves the importer.
class _InvalidImport implements Exception {
  const _InvalidImport();
}

/// Imports one completed Apple Watch workout: session, exercises, sets, the
/// inbox receipt and the cloud outbox entry commit in ONE ObjectBox write
/// transaction. The caller acknowledges the watch only after this returns.
class ObjectBoxWatchWorkoutImporter {
  ObjectBoxWatchWorkoutImporter(
    this._store, {
    required String accountId,
    required this.activeAccountId,
    ObjectBoxWorkoutOutbox? outbox,
    DateTime Function()? clock,
  }) : accountId = validAccountId(accountId),
       _outbox = outbox ?? ObjectBoxWorkoutOutbox(_store),
       _clock = clock ?? DateTime.now,
       _sessions = _store.box<WorkoutSessionEntity>(),
       _plans = _store.box<WorkoutPlanEntity>(),
       _receipts = _store.box<WatchWorkoutReceiptEntity>();

  final Store _store;
  final String accountId;
  final String? Function() activeAccountId;
  final ObjectBoxWorkoutOutbox _outbox;
  final DateTime Function() _clock;
  final Box<WorkoutSessionEntity> _sessions;
  final Box<WorkoutPlanEntity> _plans;
  final Box<WatchWorkoutReceiptEntity> _receipts;

  void _checkAccount() {
    final current = activeAccountId();
    if (current == null || validAccountId(current) != accountId) {
      throw StateError('account_changed');
    }
  }

  T? _one<T>(Box<T> box, QueryStringProperty<T> property, String key) {
    final query = box.query(property.equals(key)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  /// Throws `StateError('account_changed')` when the signed-in account is not
  /// the one this importer is bound to, before or during the transaction.
  WatchImportResult importCompleted({
    required String messageId,
    required RemoteWorkoutSnapshot snapshot,
    String? platformWorkoutUuid,
    ({String planId, String programId, String localDate})? programDay,
  }) {
    final message = messageId.toLowerCase();
    final workoutUuid = snapshot.uuid;
    _checkAccount();
    try {
      return _store.runInTransaction(TxMode.write, () {
        final byMessage = _one(
          _receipts,
          WatchWorkoutReceiptEntity_.messageId,
          message,
        );
        final byWorkout = _one(
          _receipts,
          WatchWorkoutReceiptEntity_.workoutUuid,
          workoutUuid,
        );
        if (byMessage != null && byMessage.workoutUuid != workoutUuid) {
          return WatchImportResult.invalid;
        }
        if (byMessage != null || byWorkout != null) {
          return WatchImportResult.duplicate;
        }
        final existing = _one(
          _sessions,
          WorkoutSessionEntity_.uuid,
          workoutUuid,
        );
        if (existing != null) {
          final restoredWatch =
              existing.origin == WorkoutOrigin.watch.wire &&
              existing.status == 'completed';
          return existing.deletedAtMs != null || restoredWatch
              ? WatchImportResult.duplicate
              : WatchImportResult.invalid;
        }
        final nowMs = _clock().toUtc().millisecondsSinceEpoch;
        try {
          writeCompletedSnapshot(_store, snapshot, null, nowMs: nowMs);
        } on RestoreImportException {
          throw const _InvalidImport();
        }
        _recordProgramDay(workoutUuid, programDay);
        _receipts.put(
          WatchWorkoutReceiptEntity(
            workoutUuid: workoutUuid,
            messageId: message,
            platformWorkoutUuid: platformWorkoutUuid?.toLowerCase(),
            receivedAtMs: nowMs,
          ),
        );
        try {
          _outbox.enqueueCompletedInTransaction(
            workoutUuid,
            requireValid: true,
          );
        } on InvalidCloudSnapshot {
          throw const _InvalidImport();
        }
        _checkAccount();
        return WatchImportResult.stored;
      });
    } on _InvalidImport {
      return WatchImportResult.invalid;
    }
  }

  /// Only when the plan exists here and belongs to that program; otherwise the
  /// workout is imported without a program day.
  void _recordProgramDay(
    String workoutUuid,
    ({String planId, String programId, String localDate})? day,
  ) {
    if (day == null) return;
    final plan = _one(_plans, WorkoutPlanEntity_.uuid, day.planId);
    if (plan == null || plan.programUuid != day.programId) return;
    final session = _one(_sessions, WorkoutSessionEntity_.uuid, workoutUuid)!;
    session
      ..planUuid = day.planId
      ..programUuid = day.programId
      ..programDayLocalDate = day.localDate;
    _sessions.put(session);
  }

  /// Lowercase HKWorkout UUIDs of imported watch workouts. Platform record
  /// references only, never workout values.
  Set<String> platformWorkoutUuids() => {
    for (final receipt in _receipts.getAll())
      if (receipt.platformWorkoutUuid != null) receipt.platformWorkoutUuid!,
  };
}

/// Owner-bound importer factory, built from the account's Store.
final watchWorkoutImporterProvider =
    Provider<
      ObjectBoxWatchWorkoutImporter Function(String, String? Function())
    >((ref) {
      final store = ref.watch(objectBoxStoreProvider);
      return (accountId, active) => ObjectBoxWatchWorkoutImporter(
        store,
        accountId: accountId,
        activeAccountId: active,
      );
    });
