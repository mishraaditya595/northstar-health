import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ids/uuid_factory.dart';
import '../../../core/storage/objectbox_store_provider.dart';
import '../../../objectbox.g.dart';
import 'workout_entities.dart';

final workoutOutboxProvider = Provider<ObjectBoxWorkoutOutbox>(
  (ref) => ObjectBoxWorkoutOutbox(ref.watch(objectBoxStoreProvider)),
);

/// Presentation-only count; production account scope overrides this with
/// its bound ObjectBox store. Standalone previews need no native Store.
final blockedWorkoutCountProvider = Provider<int>((ref) => 0);

/// Workouts whose cloud copy differs from this phone. Absent means synced.
enum WorkoutSyncFlag {
  /// Waiting to upload, conflicted, or a remote change was skipped.
  notSynced('Not synced'),

  /// Can never be uploaded as it is (blocked); stays on this phone only.
  localOnly('Local only');

  const WorkoutSyncFlag(this.label);
  final String label;
}

/// Presentation-only, overridden in account scope like the blocked count.
final workoutSyncFlagsProvider = Provider<Map<String, WorkoutSyncFlag>>(
  (ref) => const {},
);

/// These are durable queued *local* operations, not network acknowledgements.
/// A server worker in a later PR must send them in localRevision order and
/// supply the server's latest acknowledged revision to each RPC call.
class WorkoutSyncOperation {
  const WorkoutSyncOperation({
    required this.operationUuid,
    required this.sessionUuid,
    required this.localRevision,
    required this.action,
    required this.payloadJson,
    required this.createdAtMs,
  });

  final String operationUuid;
  final String sessionUuid;
  final int localRevision;
  final String action;
  final String payloadJson;
  final int createdAtMs;
}

/// Immutable request captured before a network call; the retry uses the
/// same operation UUID and the same server expected revision.
class ReservedWorkoutUpload {
  const ReservedWorkoutUpload({
    required this.operation,
    required this.expectedServerRevision,
  });

  final WorkoutSyncOperation operation;
  final int expectedServerRevision;
}

class ObjectBoxWorkoutOutbox {
  ObjectBoxWorkoutOutbox(Store store, {UuidFactory? uuidFactory})
    : _store = store,
      _ids = uuidFactory ?? SecureUuidFactory(),
      _operations = store.box<WorkoutSyncOutboxEntity>(),
      _sessions = store.box<WorkoutSessionEntity>(),
      _remote = store.box<WorkoutRemoteStateEntity>(),
      _exercises = store.box<WorkoutExerciseEntity>(),
      _sets = store.box<WorkoutSetEntity>();

  final Store _store;
  final UuidFactory _ids;
  final Box<WorkoutSyncOutboxEntity> _operations;
  final Box<WorkoutSessionEntity> _sessions;
  final Box<WorkoutRemoteStateEntity> _remote;
  final Box<WorkoutExerciseEntity> _exercises;
  final Box<WorkoutSetEntity> _sets;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String _requireUuid(String value) {
    if (!_uuid.hasMatch(value)) {
      throw StateError('A cloud workout requires a UUID identifier');
    }
    return value.toLowerCase();
  }

  List<T> _find<T>(Box<T> box, QueryStringProperty<T> property, String key) {
    final query = box.query(property.equals(key)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// MUST be called in the same ObjectBox write transaction which changes
  /// the session to completed. A failing snapshot rolls back the finish.
  /// No network and no health-platform data are accessed by this function.
  void enqueueCompletedInTransaction(String workoutUuid) {
    final sessions = _find(_sessions, WorkoutSessionEntity_.uuid, workoutUuid);
    if (sessions.length != 1) throw StateError('Workout missing');
    final workout = sessions.single;
    if (workout.status != 'completed' ||
        workout.completedAtMs == null ||
        workout.deletedAtMs != null ||
        workout.origin != 'northstar_phone') {
      throw StateError('Only finished NorthStar phone workouts may be queued');
    }
    // IDs may be from older offline sessions; never block a local finish
    // merely because the completed snapshot cannot be uploaded.
    final existing = _find(
      _operations,
      WorkoutSyncOutboxEntity_.sessionUuid,
      workout.uuid.toLowerCase(),
    );
    if (existing.any((op) => op.localRevision == workout.revision)) return;
    if (existing.any((op) => op.localRevision > workout.revision)) {
      throw StateError('Outbox revision exceeds workout revision');
    }

    String payload = '';
    String? validationError;
    try {
      payload = _createPayload(workout);
    } on StateError catch (error) {
      // Only predictable DTO validation exceptions are recoverable.
      // A failed ObjectBox write still aborts the completion transaction.
      validationError =
          error.message == 'Workout exceeds the cloud DTO size limit'
          ? 'payload_too_large'
          : 'invalid_snapshot';
    }
    _operations.put(
      WorkoutSyncOutboxEntity(
        operationUuid: _requireUuid(_ids.newId()),
        sessionUuid: workout.uuid.toLowerCase(),
        localRevision: workout.revision,
        action: 'upsert',
        payloadJson: payload,
        state: validationError == null ? 'pending' : 'blocked',
        errorCode: validationError,
        createdAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      ),
    );
  }

  /// Validate an immutable snapshot separately from persistence. This may
  /// reject cloud compatibility; it must never prevent local completion.
  String _createPayload(WorkoutSessionEntity workout) {
    final normalizedWorkoutUuid = _requireUuid(workout.uuid);
    final exercises = _find(
      _exercises,
      WorkoutExerciseEntity_.sessionUuid,
      workout.uuid,
    )..sort((a, b) => a.position.compareTo(b.position));
    if (exercises.length > 120) throw StateError('Too many exercises');
    final seenExercises = <String>{};
    final seenSets = <String>{};
    final items = <Map<String, Object?>>[];
    for (final exercise in exercises) {
      final exerciseId = _requireUuid(exercise.uuid);
      if (!seenExercises.add(exerciseId) ||
          exercise.position < 0 ||
          exercise.position > 10000 ||
          exercise.nameSnapshot.isEmpty ||
          exercise.nameSnapshot.runes.length > 160 ||
          exercise.muscleSnapshot.runes.length > 160 ||
          exercise.equipmentSnapshot.runes.length > 160) {
        throw StateError('Invalid exercise for cloud backup');
      }
      final sets = _find(_sets, WorkoutSetEntity_.exerciseUuid, exercise.uuid)
        ..sort((a, b) => a.position.compareTo(b.position));
      if (sets.length > 300) throw StateError('Too many sets');
      final setRows = <Map<String, Object?>>[];
      for (final set in sets) {
        final setId = _requireUuid(set.uuid);
        if (!seenSets.add(setId) ||
            set.position < 0 ||
            set.position > 10000 ||
            !const ['working', 'warmup'].contains(set.kind) ||
            !const ['planned', 'completed', 'skipped'].contains(set.status) ||
            !const ['kg', 'lb'].contains(set.inputUnit) ||
            (set.reps != null && (set.reps! < 0 || set.reps! > 10000)) ||
            (set.loadGrams != null &&
                (set.loadGrams! < 0 || set.loadGrams! > 100000000)) ||
            (set.rpe != null &&
                (!set.rpe!.isFinite ||
                    set.rpe! < 0 ||
                    set.rpe! > 10 ||
                    (set.rpe! * 2) % 1 != 0)) ||
            (set.status == 'completed' &&
                (set.reps == null || set.completedAtMs == null)) ||
            (set.completedAtMs != null &&
                set.completedAtMs! < workout.startedAtMs)) {
          throw StateError('Invalid set for cloud backup');
        }
        setRows.add({
          'id': setId,
          'position': set.position,
          'kind': set.kind,
          'status': set.status,
          'reps': set.reps,
          'load_grams': set.loadGrams,
          'input_unit': set.inputUnit,
          'rpe': set.rpe,
          'completed_at_utc': set.completedAtMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  set.completedAtMs!,
                  isUtc: true,
                ).toIso8601String(),
        });
      }
      items.add({
        'id': exerciseId,
        'name': exercise.nameSnapshot,
        'muscle': exercise.muscleSnapshot,
        'equipment': exercise.equipmentSnapshot,
        'position': exercise.position,
        'sets': setRows,
      });
    }
    if (workout.name.isEmpty ||
        workout.name.runes.length > 160 ||
        workout.originalOffsetMinutes < -840 ||
        workout.originalOffsetMinutes > 840 ||
        workout.completedAtMs! < workout.startedAtMs) {
      throw StateError('Invalid workout for cloud backup');
    }
    final payload = jsonEncode({
      'schema_version': 1,
      'workout_id': normalizedWorkoutUuid,
      'origin': 'northstar_phone',
      'status': 'completed',
      'name': workout.name,
      'started_at_utc': DateTime.fromMillisecondsSinceEpoch(
        workout.startedAtMs,
        isUtc: true,
      ).toIso8601String(),
      'completed_at_utc': DateTime.fromMillisecondsSinceEpoch(
        workout.completedAtMs!,
        isUtc: true,
      ).toIso8601String(),
      'original_offset_minutes': workout.originalOffsetMinutes,
      'exercises': items,
    });
    // PostgreSQL measures octet_length(jsonb::text), which adds a space
    // after every object colon and array/object comma. Add a 1024-byte
    // safety margin for any escaping/normalization differences.
    final jsonValue = jsonDecode(payload);
    if (utf8.encode(payload).length + _jsonbSpacing(jsonValue) + 1024 > 65536) {
      throw StateError('Workout exceeds the cloud DTO size limit');
    }
    return payload;
  }

  static int _jsonbSpacing(Object? value) {
    if (value is Map) {
      var total = value.length * 2 - (value.isEmpty ? 0 : 1);
      for (final entry in value.entries) {
        total += _jsonbSpacing(entry.value);
      }
      return total;
    }
    if (value is List) {
      var total = value.isEmpty ? 0 : value.length - 1;
      for (final element in value) {
        total += _jsonbSpacing(element);
      }
      return total;
    }
    return 0;
  }

  /// Snapshot reads are durable across restarts. Do not dequeue upon send;
  /// only a positively matched server ACK can mark a row acknowledged.
  List<WorkoutSyncOperation> pending({int limit = 100}) =>
      _store.runInTransaction(TxMode.read, () {
        if (limit < 1 || limit > 500) {
          throw ArgumentError.value(limit, 'limit');
        }
        final query = _operations
            .query(WorkoutSyncOutboxEntity_.state.equals('pending'))
            .order(WorkoutSyncOutboxEntity_.createdAtMs)
            .order(WorkoutSyncOutboxEntity_.localRevision)
            .order(WorkoutSyncOutboxEntity_.sessionUuid)
            .order(WorkoutSyncOutboxEntity_.operationUuid)
            .build();
        try {
          query.limit = limit;
          final rows = query.find()
            ..sort((a, b) {
              final time = a.createdAtMs.compareTo(b.createdAtMs);
              if (time != 0) return time;
              final revision = a.localRevision.compareTo(b.localRevision);
              if (revision != 0) return revision;
              final session = a.sessionUuid.compareTo(b.sessionUuid);
              if (session != 0) return session;
              return a.operationUuid.compareTo(b.operationUuid);
            });
          return [
            for (final op in rows)
              WorkoutSyncOperation(
                operationUuid: op.operationUuid,
                sessionUuid: op.sessionUuid,
                localRevision: op.localRevision,
                action: op.action,
                payloadJson: op.payloadJson,
                createdAtMs: op.createdAtMs,
              ),
          ];
        } finally {
          query.close();
        }
      });

  /// Per-workout sync state for UI tags. Blocked wins over not synced.
  Map<String, WorkoutSyncFlag> syncFlags() => _store.runInTransaction(
    TxMode.read,
    () {
      final flags = <String, WorkoutSyncFlag>{};
      final query = _operations
          .query(WorkoutSyncOutboxEntity_.state.notEquals('acknowledged'))
          .build();
      try {
        for (final op in query.find()) {
          if (op.state == 'blocked') {
            flags[op.sessionUuid] = WorkoutSyncFlag.localOnly;
          } else {
            flags.putIfAbsent(op.sessionUuid, () => WorkoutSyncFlag.notSynced);
          }
        }
      } finally {
        query.close();
      }
      for (final skip in _store.box<WorkoutRestoreSkipEntity>().getAll()) {
        flags.putIfAbsent(skip.workoutUuid, () => WorkoutSyncFlag.notSynced);
      }
      return flags;
    },
  );

  /// A local-only blocked record stays durable and never reaches the RPC.
  int blockedCount() {
    final query = _operations
        .query(WorkoutSyncOutboxEntity_.state.equals('blocked'))
        .build();
    try {
      return query.count();
    } finally {
      query.close();
    }
  }

  bool isBlocked(String workoutUuid) => _find(
    _operations,
    WorkoutSyncOutboxEntity_.sessionUuid,
    workoutUuid.toLowerCase(),
  ).any((op) => op.state == 'blocked');

  /// Reconcile already completed, account-bound sessions created before
  /// this outbox existed. Only completed native phone logs are eligible.
  /// Does not touch prior root/guest stores or upload anything itself.
  int backfillCompleted() => _store.runInTransaction(TxMode.write, () {
    final query = _sessions
        .query(WorkoutSessionEntity_.status.equals('completed'))
        .build();
    try {
      var added = 0;
      for (final session in query.find()) {
        if (session.deletedAtMs != null ||
            session.completedAtMs == null ||
            session.origin != 'northstar_phone') {
          continue;
        }
        try {
          if (_find(
                _operations,
                WorkoutSyncOutboxEntity_.sessionUuid,
                session.uuid.toLowerCase(),
              ).isNotEmpty ||
              _find(
                _remote,
                WorkoutRemoteStateEntity_.workoutUuid,
                session.uuid.toLowerCase(),
              ).isNotEmpty) {
            // Imported server rows must never become new outgoing uploads,
            // including across process restarts and historical backfills.
            continue;
          }
          // A malformed historical session must never starve a newer
          // completed session already waiting in the same owner's outbox.
          // Only predictable, per-session validation errors are skipped.
          enqueueCompletedInTransaction(session.uuid);
          added++;
        } on StateError {
          continue;
        } on FormatException {
          continue;
        }
      }
      return added;
    } finally {
      query.close();
    }
  });

  /// Durable dequeue/reservation in an account-specific transaction.
  /// A pending attempt is never deleted. We record the attempt *before*
  /// networking so a process crash repeats the same operation after backoff.
  /// Previous revisions of the same workout must be acknowledged first.
  ReservedWorkoutUpload? reserveNext({
    required int nowMs,
    void Function()? onBlocked,
  }) {
    var blockedAny = false;
    final reserved = _store.runInTransaction(TxMode.write, () {
      final query = _operations
          .query(WorkoutSyncOutboxEntity_.state.equals('pending'))
          .order(WorkoutSyncOutboxEntity_.createdAtMs)
          .order(WorkoutSyncOutboxEntity_.localRevision)
          .order(WorkoutSyncOutboxEntity_.sessionUuid)
          .order(WorkoutSyncOutboxEntity_.operationUuid)
          .build();
      try {
        query.limit = 500;
        for (final op in query.find()) {
          if (op.action != 'upsert' ||
              op.payloadJson.isEmpty ||
              op.localRevision < 1) {
            // Corrupt legacy operations never reach the network.
            _transition(op, 'blocked', 'invalid_queue');
            blockedAny = true;
            continue;
          }
          final lastAttempt = op.attemptedAtMs;
          if (lastAttempt != null &&
              lastAttempt <= nowMs &&
              nowMs < lastAttempt + retryDelayMs(op.attempts)) {
            continue;
          }
          final sameWorkout = _find(
            _operations,
            WorkoutSyncOutboxEntity_.sessionUuid,
            op.sessionUuid,
          );
          final predecessors = sameWorkout
              .where((other) => other.localRevision < op.localRevision)
              .toList();
          // Never send a later edit past a pending, rejected or conflicting
          // earlier revision, or a lower revision after a newer ACK.
          if (predecessors.any((prev) => prev.state != 'acknowledged') ||
              sameWorkout.any(
                (other) =>
                    other.localRevision > op.localRevision &&
                    other.state == 'acknowledged',
              )) {
            continue;
          }
          final acknowledgements =
              predecessors
                  .where(
                    (other) =>
                        other.state == 'acknowledged' &&
                        other.serverRevision != null,
                  )
                  .toList()
                ..sort((a, b) => b.localRevision.compareTo(a.localRevision));
          final remote = _find(
            _remote,
            WorkoutRemoteStateEntity_.workoutUuid,
            op.sessionUuid,
          );
          if (remote.length > 1) {
            _transition(op, 'blocked', 'invalid_remote_state');
            blockedAny = true;
            continue;
          }
          final tracked = remote.isEmpty ? null : remote.single;
          if (tracked != null &&
              (tracked.deleted ||
                  op.localRevision <= tracked.localRevisionAtImport)) {
            // Never resurrect a remote tombstone or upload a revision that
            // was already imported at a later local watermark.
            _transition(
              op,
              'blocked',
              tracked.deleted ? 'remote_tombstone' : 'stale_local_revision',
            );
            blockedAny = true;
            continue;
          }
          final lastAckRevision = acknowledgements.isEmpty
              ? 0
              : acknowledgements.first.serverRevision!;
          // A restored workout may have no local ACK at all; its imported
          // server CAS baseline is authoritative. An ACK newer than that
          // baseline still wins for a subsequent local operation.
          final remoteRevision = tracked?.serverRevision ?? 0;
          final expected = remoteRevision > lastAckRevision
              ? remoteRevision
              : lastAckRevision;
          op.attemptedAtMs = nowMs;
          op.attempts++;
          _operations.put(op);
          return ReservedWorkoutUpload(
            operation: WorkoutSyncOperation(
              operationUuid: op.operationUuid,
              sessionUuid: op.sessionUuid,
              localRevision: op.localRevision,
              action: op.action,
              payloadJson: op.payloadJson,
              createdAtMs: op.createdAtMs,
            ),
            expectedServerRevision: expected,
          );
        }
        return null;
      } finally {
        query.close();
      }
    });
    // Notify after commit, never inside ObjectBox's write transaction.
    if (blockedAny) onBlocked?.call();
    return reserved;
  }

  /// Exponential retry delay after a potentially failed/uncertain request.
  /// Bounded: 5 seconds, 10 seconds, ... up to 10 minutes.
  static int retryDelayMs(int attempts) {
    if (attempts <= 0) return 0;
    final exponent = attempts > 8 ? 8 : attempts - 1;
    final milliseconds = 5000 * (1 << exponent);
    return milliseconds > 600000 ? 600000 : milliseconds;
  }

  bool markConflict({
    required String operationUuid,
    required int localRevision,
  }) => _finalize(
    operationUuid: operationUuid,
    localRevision: localRevision,
    state: 'conflict',
    reason: 'revision_conflict',
  );

  bool markBlocked({
    required String operationUuid,
    required int localRevision,
    required String code,
  }) => _finalize(
    operationUuid: operationUuid,
    localRevision: localRevision,
    state: 'blocked',
    reason: code,
  );

  bool _finalize({
    required String operationUuid,
    required int localRevision,
    required String state,
    required String reason,
  }) => _store.runInTransaction(TxMode.write, () {
    final rows = _find(
      _operations,
      WorkoutSyncOutboxEntity_.operationUuid,
      operationUuid,
    );
    if (rows.length != 1) return false;
    final row = rows.single;
    if (row.localRevision != localRevision || row.state != 'pending') {
      return false;
    }
    _transition(row, state, reason);
    return true;
  });

  void _transition(WorkoutSyncOutboxEntity op, String state, String code) {
    op.state = state;
    op.errorCode = code;
    _operations.put(op);
  }

  /// Designed for P2-04 worker integration; a late ACK cannot accidentally
  /// acknowledge a newer operation or discard its snapshot.
  bool acknowledge({
    required String operationUuid,
    required int localRevision,
    required int serverRevision,
    required int serverChangeSeq,
  }) => _store.runInTransaction(TxMode.write, () {
    if (serverRevision < 1 || serverChangeSeq < 1) {
      throw ArgumentError('Invalid server acknowledgement');
    }
    final hits = _find(
      _operations,
      WorkoutSyncOutboxEntity_.operationUuid,
      _requireUuid(operationUuid),
    );
    if (hits.length != 1) return false;
    final op = hits.single;
    if (op.localRevision != localRevision) return false;
    if (op.state == 'acknowledged') {
      return op.serverRevision == serverRevision &&
          op.serverChangeSeq == serverChangeSeq;
    }
    if (op.state != 'pending') return false;
    op.state = 'acknowledged';
    op.serverRevision = serverRevision;
    op.serverChangeSeq = serverChangeSeq;
    _operations.put(op);
    return true;
  });
}
