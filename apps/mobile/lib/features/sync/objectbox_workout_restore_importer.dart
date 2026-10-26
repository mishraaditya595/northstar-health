import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/account_store.dart';
import '../../core/storage/objectbox_store_provider.dart';
import '../../objectbox.g.dart';
import '../workouts/data/workout_entities.dart';
import 'workout_restore_feed.dart';

/// Does not contain a raw server response, account ID, workout ID or note.
class RestoreImportException implements Exception {
  const RestoreImportException(this.code);
  final String code;
  @override
  String toString() => 'Restore import blocked';
}

/// Cursor state belongs to one authenticated owner's physical ObjectBox Store.
class WorkoutRestoreCursor {
  const WorkoutRestoreCursor({
    required this.epoch,
    required this.nextCursor,
    this.blockedCode,
  });
  final String? epoch;
  final int nextCursor;
  final String? blockedCode;
}

class RestoreApplyResult {
  const RestoreApplyResult({
    required this.cursor,
    required this.imported,
    required this.tombstones,
    required this.alreadyApplied,
  });
  final WorkoutRestoreCursor cursor;
  final int imported;
  final int tombstones;
  final bool alreadyApplied;
}

/// Injected per-account importer; *not* an app background service.
///
/// A validated page, session/exercise/set changes, tombstone metadata and its
/// epoch+cursor commit in the SAME ObjectBox transaction. Any failure rolls
/// them all back. Never creates an outbox operation, and never trusts server
/// revision as a local optimistic-lock revision.
class ObjectBoxWorkoutRestoreImporter {
  ObjectBoxWorkoutRestoreImporter(
    this._store, {
    required String accountId,
    required this.activeAccountId,
    DateTime Function()? clock,
  }) : accountId = validAccountId(accountId),
       _clock = clock ?? DateTime.now,
       _cursors = _store.box<WorkoutRestoreCursorEntity>(),
       _remote = _store.box<WorkoutRemoteStateEntity>(),
       _sessions = _store.box<WorkoutSessionEntity>(),
       _exercises = _store.box<WorkoutExerciseEntity>(),
       _sets = _store.box<WorkoutSetEntity>(),
       _outbox = _store.box<WorkoutSyncOutboxEntity>();

  final Store _store;
  final String accountId;
  final String? Function() activeAccountId;
  final DateTime Function() _clock;
  final Box<WorkoutRestoreCursorEntity> _cursors;
  final Box<WorkoutRemoteStateEntity> _remote;
  final Box<WorkoutSessionEntity> _sessions;
  final Box<WorkoutExerciseEntity> _exercises;
  final Box<WorkoutSetEntity> _sets;
  final Box<WorkoutSyncOutboxEntity> _outbox;

  void _checkAccount() {
    final current = activeAccountId();
    if (current == null || validAccountId(current) != accountId) {
      throw const RestoreImportException('account_changed');
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

  List<T> _matching<T>(
    Box<T> box,
    QueryStringProperty<T> property,
    String key,
  ) {
    final query = box.query(property.equals(key)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  WorkoutRestoreCursorEntity? _cursorEntity() {
    // A bound account store must never become writable by another identity.
    final owners = _cursors.getAll();
    if (owners.length > 1 ||
        (owners.isNotEmpty && owners.single.ownerAccountId != accountId)) {
      throw const RestoreImportException('owner_store_mismatch');
    }
    return owners.isEmpty ? null : owners.single;
  }

  WorkoutRestoreCursor _cursorValue(WorkoutRestoreCursorEntity? c) =>
      WorkoutRestoreCursor(
        epoch: c?.cursorEpoch,
        nextCursor: c?.nextCursor ?? 0,
        blockedCode: c?.blockedCode,
      );

  WorkoutRestoreCursor readCursor() => _store.runInTransaction(TxMode.read, () {
    _checkAccount();
    return _cursorValue(_cursorEntity());
  });

  /// For failures raised by the *decoder* before an importer page exists.
  /// Records only a bounded code against the unchanged expected cursor.
  /// Never stores a raw error, payload or identifier in the blocked state.
  bool recordBlocked({
    required int afterSeq,
    required String? requestedEpoch,
    required String code,
  }) {
    if (!RegExp(r'^[a-z][a-z0-9_]{1,63}$').hasMatch(code)) {
      throw const RestoreImportException('invalid_reason_code');
    }
    return _store.runInTransaction(TxMode.write, () {
      _checkAccount();
      final state = _cursorEntity();
      if ((state?.nextCursor ?? 0) != afterSeq ||
          state?.cursorEpoch != requestedEpoch ||
          state?.blockedCode != null) {
        return false;
      }
      final row =
          state ?? WorkoutRestoreCursorEntity(ownerAccountId: accountId);
      row.blockedCode = code;
      row.blockedAtMs = _clock().toUtc().millisecondsSinceEpoch;
      _cursors.put(row);
      return true;
    });
  }

  /// Explicit recovery after a reviewed correction or user-approved action.
  /// Ordinary applyPage retries cannot clear a durable blocked reason.
  bool clearBlocked({
    required int afterSeq,
    required String? requestedEpoch,
  }) => _store.runInTransaction(TxMode.write, () {
    _checkAccount();
    final state = _cursorEntity();
    if (state == null ||
        state.nextCursor != afterSeq ||
        state.cursorEpoch != requestedEpoch ||
        state.blockedCode == null) {
      return false;
    }
    state.blockedCode = null;
    state.blockedAtMs = null;
    _cursors.put(state);
    return true;
  });

  /// [afterSeq] and [requestedEpoch] MUST be the arguments used for fetchPage.
  /// The only mutable input is a validated WorkoutRestorePage. This method
  /// never performs HTTP, UI work, upload outbox enqueues or polling.
  ///
  RestoreApplyResult applyPage(
    WorkoutRestorePage page, {
    required int afterSeq,
    required String? requestedEpoch,
  }) => _applyPage(
    page, afterSeq: afterSeq, requestedEpoch: requestedEpoch,
  );

  /// Fault injection for native tests, never part of production applyPage.
  @visibleForTesting
  RestoreApplyResult applyPageForTesting(
    WorkoutRestorePage page, {
    required int afterSeq,
    required String? requestedEpoch,
    required void Function() beforeCommit,
  }) => _applyPage(
    page, afterSeq: afterSeq, requestedEpoch: requestedEpoch,
    beforeCommitForTest: beforeCommit,
  );

  RestoreApplyResult _applyPage(
    WorkoutRestorePage page, {
    required int afterSeq,
    required String? requestedEpoch,
    void Function()? beforeCommitForTest,
  }) {
    WorkoutRestorePage.validateRequest(
      afterSeq: afterSeq,
      limit: 200,
      requestedEpoch: requestedEpoch,
    );
    _checkAccount();
    try {
      return _store.runInTransaction(TxMode.write, () {
        _checkAccount();
        final state = _cursorEntity();
        final current = _cursorValue(state);
        if (current.blockedCode != null) {
          throw const RestoreImportException('restore_blocked');
        }
        // A page which was durably applied before a process restart is a
        // strict no-op. Do not report it as fresh work.
        if (!page.cursorReset &&
            current.epoch == page.cursorEpoch &&
            page.nextCursor <= current.nextCursor &&
            afterSeq < current.nextCursor) {
          return RestoreApplyResult(
            cursor: current,
            imported: 0,
            tombstones: 0,
            alreadyApplied: true,
          );
        }
        // Duplicate reset replies must not rewind a cursor after progress.
        if (page.cursorReset &&
            current.epoch == page.cursorEpoch &&
            current.nextCursor == 0 &&
            page.nextCursor == 0 &&
            !page.hasMore &&
            page.changes.isEmpty) {
          return RestoreApplyResult(
            cursor: current,
            imported: 0,
            tombstones: 0,
            alreadyApplied: true,
          );
        }
        if (current.nextCursor != afterSeq || current.epoch != requestedEpoch) {
          throw const RestoreImportException('cursor_mismatch');
        }

        final cursor =
            state ?? WorkoutRestoreCursorEntity(ownerAccountId: accountId);
        if (page.cursorReset) {
          if (page.nextCursor != 0 || page.hasMore || page.changes.isNotEmpty) {
            throw const RestoreImportException('invalid_cursor_reset');
          }
          cursor.cursorEpoch = page.cursorEpoch;
          cursor.nextCursor = 0;
          cursor.blockedCode = null;
          cursor.blockedAtMs = null;
          _cursors.put(cursor);
          beforeCommitForTest?.call();
          _checkAccount(); // Do not commit when a test simulates a switch.
          return RestoreApplyResult(
            cursor: _cursorValue(cursor),
            imported: 0,
            tombstones: 0,
            alreadyApplied: false,
          );
        }
        if (requestedEpoch != null && page.cursorEpoch != requestedEpoch) {
          throw const RestoreImportException('epoch_mismatch');
        }
        if (page.nextCursor < afterSeq ||
            page.changes.length > 200 ||
            (page.changes.isEmpty &&
                (page.nextCursor != afterSeq || page.hasMore)) ||
            (page.changes.isNotEmpty &&
                page.changes.last.changeSeq != page.nextCursor)) {
          throw const RestoreImportException('invalid_page_cursor');
        }
        var seq = afterSeq;
        final seen = <String>{};
        for (final change in page.changes) {
          if (change.changeSeq <= seq ||
              change.serverRevision < 1 ||
              !seen.add(change.workoutId) ||
              (change.deleted != (change.snapshot == null)) ||
              (change.snapshot != null &&
                  change.snapshot!.uuid != change.workoutId)) {
            throw const RestoreImportException('invalid_page_change');
          }
          seq = change.changeSeq;
        }

        var applied = 0;
        var deletions = 0;
        for (final change in page.changes) {
          _checkAccount();
          if (_applyChange(change, page.cursorEpoch)) {
            if (change.deleted) {
              deletions++;
            } else {
              applied++;
            }
          }
        }
        cursor.cursorEpoch = page.cursorEpoch;
        cursor.nextCursor = page.nextCursor;
        cursor.blockedCode = null;
        cursor.blockedAtMs = null;
        _cursors.put(cursor);
        beforeCommitForTest?.call();
        _checkAccount();
        return RestoreApplyResult(
          cursor: _cursorValue(cursor),
          imported: applied,
          tombstones: deletions,
          alreadyApplied: false,
        );
      });
    } on RestoreImportException catch (error) {
      // A stale concurrent page or identity switch must not poison the
      // current owner's progress. Other deterministic failures are durable.
      if (error.code != 'account_changed' &&
          error.code != 'owner_store_mismatch' &&
          error.code != 'cursor_mismatch' &&
          error.code != 'restore_blocked') {
        recordBlocked(
          afterSeq: afterSeq,
          requestedEpoch: requestedEpoch,
          code: error.code,
        );
      }
      rethrow;
    }
  }

  bool _applyChange(RemoteWorkoutChange change, String epoch) {
    final local = _one(_sessions, WorkoutSessionEntity_.uuid, change.workoutId);
    final remote = _one(
      _remote,
      WorkoutRemoteStateEntity_.workoutUuid,
      change.workoutId,
    );
    if (remote != null && remote.ownerAccountId != accountId) {
      throw const RestoreImportException('owner_store_mismatch');
    }
    final operations = _matching(
      _outbox,
      WorkoutSyncOutboxEntity_.sessionUuid,
      change.workoutId,
    );
    if (operations.any((op) => op.state != 'acknowledged')) {
      throw const RestoreImportException('local_outbox_unresolved');
    }
    final acknowledged =
        operations.where((op) => op.state == 'acknowledged').toList()
          ..sort((a, b) => b.localRevision.compareTo(a.localRevision));
    final latestAck = acknowledged.isEmpty ? null : acknowledged.first;

    if (remote != null && remote.deleted && !change.deleted) {
      throw const RestoreImportException('tombstone_resurrection');
    }
    if (remote != null && remote.cursorEpoch == epoch) {
      if (change.serverRevision < remote.serverRevision) {
        throw const RestoreImportException('server_revision_regressed');
      }
      if (change.serverRevision == remote.serverRevision) {
        // P2-01 increments revision alongside the change sequence on each
        // successful write. A new sequence with identical revision is
        // inconsistent, not a permitted unchanged re-emission.
        throw const RestoreImportException('duplicate_remote_sequence');
      }
    } else if (remote != null &&
        change.serverRevision < remote.serverRevision) {
      // PITR may roll the server back while the device still has newer
      // acknowledged material. Never silently overwrite that local copy.
      throw const RestoreImportException('restore_epoch_rewind_conflict');
    }
    if (local != null) {
      if (local.deletedAtMs != null && !change.deleted) {
        throw const RestoreImportException('local_deletion_conflict');
      }
      if (local.origin != 'northstar_phone' ||
          local.status != 'completed' ||
          local.completedAtMs == null) {
        throw const RestoreImportException('local_workout_conflict');
      }
      final knownRevision =
          remote?.localRevisionAtImport ?? latestAck?.localRevision;
      if (knownRevision == null) {
        throw const RestoreImportException('untracked_local_workout');
      }
      if (local.revision != knownRevision) {
        throw const RestoreImportException('local_revision_changed');
      }
      if (remote == null &&
          latestAck != null &&
          latestAck.serverRevision != null &&
          change.serverRevision < latestAck.serverRevision!) {
        throw const RestoreImportException('server_revision_regressed');
      }
    } else if (remote != null && !remote.deleted) {
      // A previously restored nondeleted workout disappearing from local
      // storage is ambiguous (possible user deletion). Never resurrect it.
      throw const RestoreImportException('missing_tracked_workout');
    } else if (latestAck != null) {
      // A locally deleted row with a prior upload receipt is ambiguous.
      throw const RestoreImportException('missing_acknowledged_workout');
    }

    var localRevision = local?.revision ?? 0;
    if (change.deleted) {
      if (local != null && local.deletedAtMs == null) {
        local.deletedAtMs = _clock().toUtc().millisecondsSinceEpoch;
        local.updatedAtMs = local.deletedAtMs!;
        local.revision++;
        _sessions.put(local);
        localRevision = local.revision;
      }
    } else {
      final snapshot = change.snapshot!;
      // A matching acknowledged local snapshot needs no reconstruction.
      // The existing remote same-revision case is rejected above because
      // the server never emits the same revision at a new sequence.
      final unchangedAck =
          local != null &&
          latestAck?.serverRevision == change.serverRevision &&
          (remote == null || remote.serverRevision == change.serverRevision);
      if (!unchangedAck) {
        localRevision = _materialize(snapshot, local);
      }
    }
    final metadata =
        remote ??
        WorkoutRemoteStateEntity(
          ownerAccountId: accountId,
          workoutUuid: change.workoutId,
          serverRevision: change.serverRevision,
          serverChangeSeq: change.changeSeq,
          cursorEpoch: epoch,
          localRevisionAtImport: localRevision,
        );
    metadata.serverRevision = change.serverRevision;
    metadata.serverChangeSeq = change.changeSeq;
    metadata.cursorEpoch = epoch;
    metadata.localRevisionAtImport = localRevision;
    metadata.deleted = change.deleted;
    _remote.put(metadata);
    return true;
  }

  int _materialize(
    RemoteWorkoutSnapshot snapshot,
    WorkoutSessionEntity? existing,
  ) {
    // Global Unique IDs on exercises and sets must not be stolen from a
    // different local workout. Check first, then write everything atomically.
    final oldExercises = _matching(
      _exercises,
      WorkoutExerciseEntity_.sessionUuid,
      snapshot.uuid,
    );
    final oldIds = oldExercises.map((e) => e.uuid).toSet();
    for (final exercise in snapshot.exercises) {
      final prior = _one(
        _exercises,
        WorkoutExerciseEntity_.uuid,
        exercise.uuid,
      );
      if (prior != null && prior.sessionUuid != snapshot.uuid) {
        throw const RestoreImportException('exercise_uuid_collision');
      }
    }
    for (final set in snapshot.sets) {
      final prior = _one(_sets, WorkoutSetEntity_.uuid, set.uuid);
      if (prior != null && !oldIds.contains(prior.exerciseUuid)) {
        throw const RestoreImportException('set_uuid_collision');
      }
    }
    for (final exercise in oldExercises) {
      for (final set in _matching(
        _sets,
        WorkoutSetEntity_.exerciseUuid,
        exercise.uuid,
      )) {
        _sets.remove(set.id);
      }
      _exercises.remove(exercise.id);
    }
    final now = _clock().toUtc().millisecondsSinceEpoch;
    final session =
        existing ??
        WorkoutSessionEntity(
          uuid: snapshot.uuid,
          name: snapshot.name,
          startedAtMs: snapshot.startedAtUtc.millisecondsSinceEpoch,
          originalOffsetMinutes: snapshot.originalOffsetMinutes,
          updatedAtMs: now,
        );
    session.name = snapshot.name;
    session.status = 'completed';
    session.origin = 'northstar_phone';
    session.planUuid = null; // Plans are never transported in the DTO.
    session.startedAtMs = snapshot.startedAtUtc.millisecondsSinceEpoch;
    session.completedAtMs = snapshot.completedAtUtc.millisecondsSinceEpoch;
    session.originalOffsetMinutes = snapshot.originalOffsetMinutes;
    session.updatedAtMs = now;
    session.deletedAtMs = null;
    session.revision = existing == null ? 1 : existing.revision + 1;
    _sessions.put(session);
    for (final ex in snapshot.exercises) {
      _exercises.put(
        WorkoutExerciseEntity(
          uuid: ex.uuid,
          sessionUuid: snapshot.uuid,
          nameSnapshot: ex.nameSnapshot,
          muscleSnapshot: ex.muscleSnapshot,
          equipmentSnapshot: ex.equipmentSnapshot,
          position: ex.position,
        ),
      );
    }
    for (final set in snapshot.sets) {
      _sets.put(
        WorkoutSetEntity(
          uuid: set.uuid,
          exerciseUuid: set.exerciseUuid,
          position: set.position,
          kind: set.kind.name,
          status: set.status.name,
          reps: set.reps,
          loadGrams: set.loadGrams,
          inputUnit: set.inputUnit.name,
          rpe: set.rpe,
          completedAtMs: set.completedAtUtc?.millisecondsSinceEpoch,
          updatedAtMs: now,
        ),
      );
    }
    return session.revision;
  }
}

/// Opt-in repository factory for a *later* single-owner foreground pull
/// coordinator. Merely obtaining this provider starts no RPC or importer.
final workoutRestoreImporterProvider =
    Provider<
      ObjectBoxWorkoutRestoreImporter Function(String, String? Function())
    >(
      (ref) =>
          (owner, activeOwner) => ObjectBoxWorkoutRestoreImporter(
            ref.watch(objectBoxStoreProvider),
            accountId: owner,
            activeAccountId: activeOwner,
          ),
    );
