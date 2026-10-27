import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids/uuid_factory.dart';
import '../../core/storage/account_store.dart';
import '../../core/storage/objectbox_store_provider.dart';
import '../../objectbox.g.dart';
import '../workouts/data/workout_entities.dart';
import '../workouts/data/objectbox_workout_outbox.dart';
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

enum WorkoutResolutionAction {
  useCloud,
  retryLocal,
  finishDeletion,
  keepLocalOnly,
}

class WorkoutConflictCandidate {
  const WorkoutConflictCandidate({
    required this.workoutUuid,
    required this.name,
    required this.localRevision,
    required this.deletedLocally,
    required this.hasLocalWorkout,
    required this.exerciseCount,
    required this.setCount,
    required this.canKeepLocalOnly,
  });
  final String workoutUuid;
  final String name;
  final int localRevision;
  final bool deletedLocally;
  final bool hasLocalWorkout;
  final int exerciseCount;
  final int setCount;
  final bool canKeepLocalOnly;
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
    UuidFactory? uuidFactory,
  }) : accountId = validAccountId(accountId),
       _clock = clock ?? DateTime.now,
       _ids = uuidFactory ?? SecureUuidFactory(),
       _cursors = _store.box<WorkoutRestoreCursorEntity>(),
       _remote = _store.box<WorkoutRemoteStateEntity>(),
       _sessions = _store.box<WorkoutSessionEntity>(),
       _exercises = _store.box<WorkoutExerciseEntity>(),
       _sets = _store.box<WorkoutSetEntity>(),
       _outbox = _store.box<WorkoutSyncOutboxEntity>(),
       _skips = _store.box<WorkoutRestoreSkipEntity>();

  final Store _store;
  final String accountId;
  final String? Function() activeAccountId;
  final DateTime Function() _clock;
  final UuidFactory _ids;
  final Box<WorkoutRestoreCursorEntity> _cursors;
  final Box<WorkoutRemoteStateEntity> _remote;
  final Box<WorkoutSessionEntity> _sessions;
  final Box<WorkoutExerciseEntity> _exercises;
  final Box<WorkoutSetEntity> _sets;
  final Box<WorkoutSyncOutboxEntity> _outbox;
  final Box<WorkoutRestoreSkipEntity> _skips;

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
  bool clearBlocked({required int afterSeq, required String? requestedEpoch}) =>
      _store.runInTransaction(TxMode.write, () {
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
  }) => _applyPage(page, afterSeq: afterSeq, requestedEpoch: requestedEpoch);

  /// Fault injection for native tests, never part of production applyPage.
  @visibleForTesting
  RestoreApplyResult applyPageForTesting(
    WorkoutRestorePage page, {
    required int afterSeq,
    required String? requestedEpoch,
    required void Function() beforeCommit,
  }) => _applyPage(
    page,
    afterSeq: afterSeq,
    requestedEpoch: requestedEpoch,
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
    if (operations.any((op) => op.state == 'pending')) {
      throw const RestoreImportException('local_outbox_unresolved');
    }
    if (operations.any(
      (op) => op.state != 'acknowledged' && op.state != 'superseded',
    )) {
      // A conflicted/blocked local upload keeps its copy. Record the skipped
      // remote change so one workout never stops the rest of the feed.
      final existing = _one(
        _skips,
        WorkoutRestoreSkipEntity_.workoutUuid,
        change.workoutId,
      );
      if (existing != null && existing.ownerAccountId != accountId) {
        throw const RestoreImportException('owner_store_mismatch');
      }
      final skip =
          existing ??
          WorkoutRestoreSkipEntity(
            workoutUuid: change.workoutId,
            ownerAccountId: accountId,
            serverChangeSeq: change.changeSeq,
            cursorEpoch: epoch,
            skippedAtMs: 0,
          );
      skip.serverChangeSeq = change.changeSeq;
      skip.cursorEpoch = epoch;
      skip.deleted = change.deleted;
      skip.skippedAtMs = _clock().toUtc().millisecondsSinceEpoch;
      _skips.put(skip);
      return false;
    }
    final acknowledged =
        operations.where((op) => op.state == 'acknowledged').toList()
          ..sort((a, b) => b.localRevision.compareTo(a.localRevision));
    final latestAck = acknowledged.isEmpty ? null : acknowledged.first;

    if (remote != null && remote.cursorEpoch == epoch) {
      // A user-reviewed per-workout lookup can advance the known baseline
      // ahead of the shared cursor. The later page replay of that SAME or an
      // older change must not block the entire account or overwrite review.
      if (change.changeSeq <= remote.serverChangeSeq) {
        if (change.changeSeq == remote.serverChangeSeq &&
            (change.serverRevision != remote.serverRevision ||
                change.deleted != remote.deleted)) {
          throw const RestoreImportException('remote_sequence_inconsistent');
        }
        return false;
      }
      if (change.serverRevision < remote.serverRevision) {
        throw const RestoreImportException('server_revision_regressed');
      }
      if (change.serverRevision == remote.serverRevision) {
        throw const RestoreImportException('duplicate_remote_sequence');
      }
    }
    if (remote != null && remote.deleted && !change.deleted) {
      throw const RestoreImportException('tombstone_resurrection');
    }
    if (remote != null &&
        remote.cursorEpoch != epoch &&
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
      // The device may be receiving its own just-ACKed delete. Its local
      // tombstone revision advanced before the network call, whereas the
      // previously imported metadata still holds the earlier local version.
      // Trust a matching *durable server ACK*, never an unacknowledged edit.
      final knownRevision = latestAck?.serverRevision == change.serverRevision
          ? latestAck!.localRevision
          : (remote?.localRevisionAtImport ?? latestAck?.localRevision);
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
      // A deletion observed from another device also redacts old, already
      // acknowledged local outbox snapshots in this same import transaction.
      // Keep UUID, revision, change sequence and owner CAS evidence intact.
      for (final op in operations) {
        if (op.state == 'acknowledged' &&
            op.action == 'upsert' &&
            op.payloadJson != 'null') {
          op.payloadJson = 'null';
          _outbox.put(op);
        }
      }
      if (local != null) {
        // Tombstones must remove the original workout details on *every*
        // signed-in device, not merely hide them from the Progress query.
        // Keep minimal UUID/revision metadata to guard against resurrection.
        for (final exercise in _matching(
          _exercises,
          WorkoutExerciseEntity_.sessionUuid,
          local.uuid,
        )) {
          for (final set in _matching(
            _sets,
            WorkoutSetEntity_.exerciseUuid,
            exercise.uuid,
          )) {
            _sets.remove(set.id);
          }
          _exercises.remove(exercise.id);
        }
        if (local.deletedAtMs == null) {
          local.deletedAtMs = _clock().toUtc().millisecondsSinceEpoch;
          local.revision++;
        }
        local.updatedAtMs = local.deletedAtMs!;
        local.name = 'Deleted workout';
        local.planUuid = null;
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
          latestAck?.serverChangeSeq == change.changeSeq &&
          latestAck?.localRevision == local.revision;
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

  /// Durable, owner-bound review queue. Only terminal/blocked operations and
  /// explicit skipped remote changes require user choices; never expose
  /// pending network requests as resolvable conflicts.
  List<WorkoutConflictCandidate> readConflictCandidates() =>
      _store.runInTransaction(TxMode.read, () {
        _checkAccount();
        _cursorEntity();
        final ids = <String>{};
        for (final op in _outbox.getAll()) {
          if (op.state == 'conflict' || op.state == 'blocked') {
            ids.add(op.sessionUuid);
          }
        }
        for (final skip in _skips.getAll()) {
          if (skip.ownerAccountId != accountId) {
            throw const RestoreImportException('owner_store_mismatch');
          }
          ids.add(skip.workoutUuid);
        }
        final results = <WorkoutConflictCandidate>[];
        for (final id in ids) {
          final session = _one(_sessions, WorkoutSessionEntity_.uuid, id);
          final operations = _matching(
            _outbox,
            WorkoutSyncOutboxEntity_.sessionUuid,
            id,
          );
          final baseline = _one(
            _remote,
            WorkoutRemoteStateEntity_.workoutUuid,
            id,
          );
          final skip = _one(_skips, WorkoutRestoreSkipEntity_.workoutUuid, id);
          if (baseline != null && baseline.ownerAccountId != accountId) {
            throw const RestoreImportException('owner_store_mismatch');
          }
          final keepLocalOnly =
              baseline == null &&
              skip == null &&
              ObjectBoxWorkoutOutbox.entirelyUnsentLocalValidations(operations);
          final exercises = session == null
              ? <WorkoutExerciseEntity>[]
              : _matching(
                  _exercises,
                  WorkoutExerciseEntity_.sessionUuid,
                  session.uuid,
                );
          final setCount = exercises.fold<int>(
            0,
            (sum, exercise) =>
                sum +
                _matching(
                  _sets,
                  WorkoutSetEntity_.exerciseUuid,
                  exercise.uuid,
                ).length,
          );
          results.add(
            WorkoutConflictCandidate(
              workoutUuid: id,
              name: session?.deletedAtMs != null
                  ? 'Deleted workout'
                  : (session?.name ?? 'Unavailable workout'),
              localRevision: session?.revision ?? 0,
              deletedLocally: session?.deletedAtMs != null,
              hasLocalWorkout: session != null,
              exerciseCount: exercises.length,
              setCount: setCount,
              canKeepLocalOnly: keepLocalOnly,
            ),
          );
        }
        results.sort((a, b) => a.workoutUuid.compareTo(b.workoutUuid));
        return List.unmodifiable(results);
      });

  /// Called only AFTER an authenticated point lookup and an explicit user
  /// decision. The read may have raced with another server write; retries
  /// continue to use normal server CAS and will conflict rather than
  /// overwriting a newer version. All local changes and skip removal commit
  /// atomically, including a new outbox dependency baseline.
  bool resolveReviewedWorkout({
    required String workoutUuid,
    required int expectedLocalRevision,
    required WorkoutRemoteReview review,
    required WorkoutResolutionAction action,
  }) => _store.runInTransaction(TxMode.write, () {
    _checkAccount();
    final cursor = _cursorEntity();
    // A blocked page cursor must not prevent an independent, owner-checked
    // per-workout reviewed resolution. The cursor itself remains blocked
    // until an explicit retry; no shared sequence is skipped here.
    if (cursor?.cursorEpoch != null &&
        cursor!.cursorEpoch != review.cursorEpoch) {
      throw const RestoreImportException('resolution_epoch_changed');
    }
    if (review.change != null && review.change!.workoutId != workoutUuid) {
      throw const RestoreImportException('resolution_workout_mismatch');
    }
    final local = _one(_sessions, WorkoutSessionEntity_.uuid, workoutUuid);
    if ((local?.revision ?? 0) != expectedLocalRevision) {
      throw const RestoreImportException('resolution_local_changed');
    }
    if (local != null &&
        (local.origin != 'northstar_phone' ||
            local.status != 'completed' ||
            local.completedAtMs == null)) {
      throw const RestoreImportException('resolution_not_phone_history');
    }
    final oldRemote = _one(
      _remote,
      WorkoutRemoteStateEntity_.workoutUuid,
      workoutUuid,
    );
    if (oldRemote != null && oldRemote.ownerAccountId != accountId) {
      throw const RestoreImportException('owner_store_mismatch');
    }
    final operations = _matching(
      _outbox,
      WorkoutSyncOutboxEntity_.sessionUuid,
      workoutUuid,
    );
    // A pending request may already have reached the server; never abandon
    // it on the strength of a read-only lookup.
    if (operations.any((op) => op.state == 'pending')) {
      throw const RestoreImportException('resolution_upload_pending');
    }
    if (operations.any(
      (op) =>
          op.state != 'acknowledged' &&
          op.state != 'superseded' &&
          op.state != 'conflict' &&
          op.state != 'blocked' &&
          op.state != 'dependency_paused',
    )) {
      throw const RestoreImportException('resolution_unknown_operation');
    }
    final skip = _one(
      _skips,
      WorkoutRestoreSkipEntity_.workoutUuid,
      workoutUuid,
    );
    if (skip != null && skip.ownerAccountId != accountId) {
      throw const RestoreImportException('owner_store_mismatch');
    }
    if (skip == null &&
        !operations.any(
          (op) => op.state == 'conflict' || op.state == 'blocked',
        )) {
      throw const RestoreImportException('resolution_already_handled');
    }
    final remoteChange = review.change;
    // The foreground importer may have skipped a NEWER server change while
    // the user was reading a conflict preview. Local revision is unchanged
    // for skips, so the optimistic local check alone is insufficient.
    // Never clear a newer skip from an older reviewed point lookup.
    if (skip != null &&
        (skip.cursorEpoch != review.cursorEpoch ||
            remoteChange == null ||
            remoteChange.changeSeq < skip.serverChangeSeq)) {
      throw const RestoreImportException('resolution_stale_skip');
    }
    if (oldRemote != null &&
        oldRemote.cursorEpoch == review.cursorEpoch &&
        (remoteChange == null ||
            remoteChange.serverRevision < oldRemote.serverRevision ||
            remoteChange.changeSeq < oldRemote.serverChangeSeq)) {
      throw const RestoreImportException('resolution_stale_server');
    }
    final localOnlyAllowed = action == WorkoutResolutionAction.keepLocalOnly &&
        local != null &&
        local.deletedAtMs == null &&
        remoteChange == null &&
        oldRemote == null &&
        skip == null &&
        ObjectBoxWorkoutOutbox.entirelyUnsentLocalValidations(operations);
    if (action == WorkoutResolutionAction.keepLocalOnly &&
        !localOnlyAllowed) {
      throw const RestoreImportException('resolution_cannot_keep_local');
    }
    if (action == WorkoutResolutionAction.useCloud && remoteChange == null) {
      throw const RestoreImportException('resolution_cloud_missing');
    }
    // A user-initiated local tombstone is irreversible. Even a reviewed
    // older live server snapshot cannot resurrect the deleted UUID.
    if (action == WorkoutResolutionAction.useCloud &&
        local?.deletedAtMs != null &&
        remoteChange?.deleted == false) {
      throw const RestoreImportException('local_tombstone_sticky');
    }
    if (action == WorkoutResolutionAction.retryLocal &&
        (local == null ||
            local.deletedAtMs != null ||
            local.origin != 'northstar_phone' ||
            local.status != 'completed' ||
            local.completedAtMs == null ||
            remoteChange?.deleted == true)) {
      throw const RestoreImportException('resolution_cannot_upload');
    }
    if (action == WorkoutResolutionAction.finishDeletion &&
        (local == null || local.deletedAtMs == null)) {
      throw const RestoreImportException('resolution_not_deleted');
    }
    // These states never have an uncertain in-flight server mutation:
    // conflict means explicit server CAS rejection; blocked is a terminal
    // local/server validation; dependency_paused has never been sent.
    for (final op in operations) {
      if (op.state == 'conflict' ||
          op.state == 'blocked' ||
          op.state == 'dependency_paused') {
        op.state = 'superseded';
        op.errorCode = 'reviewed_resolution';
        op.payloadJson = 'null';
        _outbox.put(op);
      }
    }
    final before = local?.revision ?? 0;
    var importedRevision = before;
    if (action == WorkoutResolutionAction.useCloud) {
      if (remoteChange!.deleted) {
        if (local != null) {
          _redactSession(local);
          if (local.deletedAtMs == null) {
            local.deletedAtMs = _clock().toUtc().millisecondsSinceEpoch;
            local.revision++;
          }
          local.updatedAtMs = local.deletedAtMs!;
          local.name = 'Deleted workout';
          local.planUuid = null;
          _sessions.put(local);
          importedRevision = local.revision;
        }
        // Discard known ACKed workout snapshots after an explicit tombstone.
        for (final op in operations) {
          if (op.state == 'acknowledged' &&
              op.action == 'upsert' &&
              op.payloadJson != 'null') {
            op.payloadJson = 'null';
            _outbox.put(op);
          }
        }
      } else {
        importedRevision = _materialize(remoteChange.snapshot!, local);
      }
    } else if (action == WorkoutResolutionAction.keepLocalOnly) {
      // Preserve full workout details and the terminal superseded marker,
      // preventing future automatic backfill of this UUID.
    } else if (action == WorkoutResolutionAction.retryLocal) {
      local!.revision++;
      local.updatedAtMs = _clock().toUtc().millisecondsSinceEpoch;
      _sessions.put(local);
      ObjectBoxWorkoutOutbox(_store).enqueueCompletedInTransaction(workoutUuid);
      final fresh = _matching(
        _outbox,
        WorkoutSyncOutboxEntity_.sessionUuid,
        workoutUuid,
      ).where((op) => op.localRevision == local.revision).toList();
      if (fresh.length != 1 || fresh.single.state != 'pending') {
        // No circular blocked operations for an invalid immutable snapshot.
        throw const RestoreImportException('resolution_invalid_snapshot');
      }
    } else if (remoteChange != null && !remoteChange.deleted) {
      local!.revision++;
      local.updatedAtMs = _clock().toUtc().millisecondsSinceEpoch;
      _sessions.put(local);
      _outbox.put(
        WorkoutSyncOutboxEntity(
          operationUuid: _ids.newId(),
          sessionUuid: workoutUuid,
          localRevision: local.revision,
          action: 'delete',
          payloadJson: 'null',
          createdAtMs: local.updatedAtMs,
        ),
      );
    }
    if (remoteChange != null) {
      final baseline = action == WorkoutResolutionAction.useCloud
          ? importedRevision
          : before;
      final state =
          oldRemote ??
          WorkoutRemoteStateEntity(
            workoutUuid: workoutUuid,
            ownerAccountId: accountId,
            serverRevision: remoteChange.serverRevision,
            serverChangeSeq: remoteChange.changeSeq,
            cursorEpoch: review.cursorEpoch,
            localRevisionAtImport: baseline,
          );
      state.serverRevision = remoteChange.serverRevision;
      state.serverChangeSeq = remoteChange.changeSeq;
      state.cursorEpoch = review.cursorEpoch;
      state.localRevisionAtImport = baseline;
      state.deleted = remoteChange.deleted;
      _remote.put(state);
    }
    if (skip != null) _skips.remove(skip.id);
    _checkAccount();
    return true;
  });

  void _redactSession(WorkoutSessionEntity session) {
    for (final exercise in _matching(
      _exercises,
      WorkoutExerciseEntity_.sessionUuid,
      session.uuid,
    )) {
      for (final set in _matching(
        _sets,
        WorkoutSetEntity_.exerciseUuid,
        exercise.uuid,
      )) {
        _sets.remove(set.id);
      }
      _exercises.remove(exercise.id);
    }
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

/// Owner-bound repository factory mounted by the authenticated foreground
/// sync coordinator. Constructing it does not start any RPC or import.
final workoutRestoreImporterProvider =
    Provider<
      ObjectBoxWorkoutRestoreImporter Function(String, String? Function())
    >((ref) {
      // Capture the owner-bound Store while Riverpod builds this provider;
      // never call ref.watch later from the returned callback.
      final store = ref.watch(objectBoxStoreProvider);
      return (owner, activeOwner) => ObjectBoxWorkoutRestoreImporter(
        store,
        accountId: owner,
        activeAccountId: activeOwner,
      );
    });
