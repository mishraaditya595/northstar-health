import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/objectbox_store_provider.dart';
import '../../../core/units/load_units.dart';
import '../../../objectbox.g.dart';
import '../domain/workout_models.dart';
import '../domain/workout_repository.dart';
import '../domain/workout_status_codec.dart';
import 'unfinished_workout_query.dart';
import 'objectbox_workout_outbox.dart';
import 'workout_entities.dart';

final workoutRepositoryProvider = Provider<WorkoutRepository>(
  (ref) => ObjectBoxWorkoutRepository(
    ref.watch(objectBoxStoreProvider),
    outbox: ref.watch(workoutOutboxProvider),
  ),
);

class ObjectBoxWorkoutRepository implements WorkoutRepository {
  ObjectBoxWorkoutRepository(this._store, {this.outbox})
    : _sessions = _store.box<WorkoutSessionEntity>(),
      _exercises = _store.box<WorkoutExerciseEntity>(),
      _sets = _store.box<WorkoutSetEntity>(),
      _checkpoints = _store.box<WorkoutSessionStateEntity>();

  final Store _store;
  final ObjectBoxWorkoutOutbox? outbox;
  final Box<WorkoutSessionEntity> _sessions;
  final Box<WorkoutExerciseEntity> _exercises;
  final Box<WorkoutSetEntity> _sets;
  final Box<WorkoutSessionStateEntity> _checkpoints;

  T? _one<T>(Box<T> box, QueryStringProperty<T> property, String value) {
    final query = box.query(property.equals(value)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  List<T> _matching<T>(
    Box<T> box,
    QueryStringProperty<T> property,
    String value,
  ) {
    final query = box.query(property.equals(value)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  WorkoutSessionRecord createSession({
    required String uuid,
    required String name,
    DateTime? startedAtUtc,
    String? planUuid,
    int? originalOffsetMinutes,
  }) {
    if (uuid.isEmpty || name.trim().isEmpty || name.length > 160) {
      throw ArgumentError('Session requires UUID and valid name');
    }
    final localNow = DateTime.now();
    final at = (startedAtUtc ?? localNow).toUtc();
    final offset = originalOffsetMinutes ?? localNow.timeZoneOffset.inMinutes;
    if (offset < -840 || offset > 840) {
      throw ArgumentError.value(offset, 'originalOffsetMinutes');
    }
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    _store.runInTransaction(TxMode.write, () {
      final existing = _one(_sessions, WorkoutSessionEntity_.uuid, uuid);
      if (existing != null) {
        if (existing.deletedAtMs != null ||
            existing.name != name.trim() ||
            existing.planUuid != planUuid ||
            (startedAtUtc != null &&
                existing.startedAtMs != at.millisecondsSinceEpoch) ||
            (originalOffsetMinutes != null &&
                existing.originalOffsetMinutes != offset)) {
          throw StateError('Conflicting session UUID');
        }
        return; // Duplicate create command is idempotent.
      }
      // All call paths must honor a single unfinished workout. This older
      // primitive remains for tests; production starts use LiveWorkoutEngine.
      if (queryUnfinishedWorkoutSessions(_sessions).isNotEmpty) {
        throw StateError('Finish or discard the existing workout first');
      }
      _sessions.put(
        WorkoutSessionEntity(
          uuid: uuid,
          name: name.trim(),
          planUuid: planUuid,
          startedAtMs: at.millisecondsSinceEpoch,
          updatedAtMs: nowMs,
          originalOffsetMinutes: offset,
        ),
      );
      _checkpoints.put(
        WorkoutSessionStateEntity(sessionUuid: uuid, savedAtMs: nowMs),
      );
    });
    return getSession(uuid)!;
  }

  @override
  WorkoutSessionRecord? getSession(String uuid) {
    return _store.runInTransaction(TxMode.read, () {
      final s = _one(_sessions, WorkoutSessionEntity_.uuid, uuid);
      if (s == null || s.deletedAtMs != null) return null;
      final children = _matching(
        _exercises,
        WorkoutExerciseEntity_.sessionUuid,
        uuid,
      )..sort((a, b) => a.position.compareTo(b.position));
      final exercises = children
          .map(
            (e) => WorkoutExerciseRecord(
              uuid: e.uuid,
              sessionUuid: e.sessionUuid,
              definitionUuid: e.definitionUuid,
              nameSnapshot: e.nameSnapshot,
              muscleSnapshot: e.muscleSnapshot,
              equipmentSnapshot: e.equipmentSnapshot,
              position: e.position,
            ),
          )
          .toList(growable: false);
      final sets = <WorkoutSetRecord>[];
      for (final child in children) {
        final entries = _matching(
          _sets,
          WorkoutSetEntity_.exerciseUuid,
          child.uuid,
        )..sort((a, b) => a.position.compareTo(b.position));
        for (final entry in entries) {
          sets.add(
            WorkoutSetRecord(
              uuid: entry.uuid,
              exerciseUuid: entry.exerciseUuid,
              position: entry.position,
              kind: workoutSetKindFromStorage(entry.kind),
              status: workoutSetStatusFromStorage(entry.status),
              reps: entry.reps,
              loadGrams: entry.loadGrams,
              inputUnit: loadUnitFromStorage(entry.inputUnit),
              rpe: entry.rpe,
              completedAtUtc: entry.completedAtMs == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      entry.completedAtMs!,
                      isUtc: true,
                    ),
            ),
          );
        }
      }
      return WorkoutSessionRecord(
        uuid: s.uuid,
        name: s.name,
        status: workoutStatusFromStorage(s.status),
        startedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          s.startedAtMs,
          isUtc: true,
        ),
        originalOffsetMinutes: s.originalOffsetMinutes,
        revision: s.revision,
        planUuid: s.planUuid,
        completedAtUtc: s.completedAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                s.completedAtMs!,
                isUtc: true,
              ),
        exercises: exercises,
        sets: sets,
      );
    });
  }

  @override
  void addExercise(WorkoutExerciseRecord exercise) {
    if (exercise.uuid.isEmpty ||
        exercise.nameSnapshot.trim().isEmpty ||
        exercise.position < 0) {
      throw ArgumentError('Invalid exercise');
    }
    _store.runInTransaction(TxMode.write, () {
      final session = _one(
        _sessions,
        WorkoutSessionEntity_.uuid,
        exercise.sessionUuid,
      );
      if (session == null || session.deletedAtMs != null) {
        throw StateError('Session does not exist or was deleted');
      }
      final previous = _one(
        _exercises,
        WorkoutExerciseEntity_.uuid,
        exercise.uuid,
      );
      if (previous != null) {
        if (previous.sessionUuid == exercise.sessionUuid &&
            previous.nameSnapshot == exercise.nameSnapshot.trim() &&
            previous.definitionUuid == exercise.definitionUuid &&
            previous.position == exercise.position &&
            previous.muscleSnapshot == exercise.muscleSnapshot &&
            previous.equipmentSnapshot == exercise.equipmentSnapshot) {
          return; // Exact retransmission.
        }
        throw StateError('Conflicting exercise UUID');
      }
      if (session.status != WorkoutStatus.inProgress.name &&
          session.status != WorkoutStatus.paused.name) {
        throw StateError('No editable session');
      }
      if (_matching(
        _exercises,
        WorkoutExerciseEntity_.sessionUuid,
        exercise.sessionUuid,
      ).any((e) => e.position == exercise.position)) {
        throw StateError('Exercise position is already occupied');
      }
      final checkpoint = _one(
        _checkpoints,
        WorkoutSessionStateEntity_.sessionUuid,
        exercise.sessionUuid,
      );
      if (checkpoint == null) throw StateError('Missing checkpoint');
      _exercises.put(
        WorkoutExerciseEntity(
          uuid: exercise.uuid,
          sessionUuid: exercise.sessionUuid,
          definitionUuid: exercise.definitionUuid,
          nameSnapshot: exercise.nameSnapshot.trim(),
          muscleSnapshot: exercise.muscleSnapshot,
          equipmentSnapshot: exercise.equipmentSnapshot,
          position: exercise.position,
        ),
      );
      _touch(session);
      checkpoint.checkpointRevision = session.revision;
      checkpoint.savedAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      _checkpoints.put(checkpoint);
    });
  }

  @override
  void saveSet({
    required String sessionUuid,
    required WorkoutSetRecord set,
    required int expectedRevision,
    int? restSeconds,
  }) {
    if (expectedRevision < 1) throw ArgumentError.value(expectedRevision);
    if (restSeconds != null && (restSeconds < 0 || restSeconds > 1800)) {
      throw ArgumentError.value(restSeconds, 'restSeconds');
    }
    set.validate();
    _store.runInTransaction(TxMode.write, () {
      final session = _one(_sessions, WorkoutSessionEntity_.uuid, sessionUuid);
      if (session == null || session.deletedAtMs != null) {
        throw StateError('Session does not exist or was deleted');
      }
      final exercise = _one(
        _exercises,
        WorkoutExerciseEntity_.uuid,
        set.exerciseUuid,
      );
      if (exercise == null || exercise.sessionUuid != sessionUuid) {
        throw StateError('Set exercise does not belong to session');
      }
      final prior = _one(_sets, WorkoutSetEntity_.uuid, set.uuid);
      if (prior != null && prior.exerciseUuid != set.exerciseUuid) {
        throw StateError('Set UUID already belongs to another exercise');
      }
      final same =
          prior != null &&
          prior.position == set.position &&
          prior.kind == set.kind.name &&
          prior.status == set.status.name &&
          prior.reps == set.reps &&
          prior.loadGrams == set.loadGrams &&
          prior.inputUnit == set.inputUnit.name &&
          prior.rpe == set.rpe &&
          prior.completedAtMs ==
              set.completedAtUtc?.toUtc().millisecondsSinceEpoch;
      if (same) return; // Exact retry after a committed save.
      if (session.status != WorkoutStatus.inProgress.name &&
          session.status != WorkoutStatus.paused.name) {
        throw StateError('No editable session');
      }
      if (session.revision != expectedRevision) {
        throw WorkoutRevisionConflict(expectedRevision, session.revision);
      }
      if (_matching(
        _sets,
        WorkoutSetEntity_.exerciseUuid,
        set.exerciseUuid,
      ).any((e) => e.position == set.position && e.uuid != set.uuid)) {
        throw StateError('Set position is already occupied');
      }
      _sets.put(
        WorkoutSetEntity(
          id: prior?.id ?? 0,
          uuid: set.uuid,
          exerciseUuid: set.exerciseUuid,
          position: set.position,
          kind: set.kind.name,
          status: set.status.name,
          reps: set.reps,
          loadGrams: set.loadGrams,
          inputUnit: set.inputUnit.name,
          rpe: set.rpe,
          completedAtMs: set.completedAtUtc?.toUtc().millisecondsSinceEpoch,
          updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        ),
      );
      _touch(session);
      // If the checkpoint is missing, this late guard throws after writes:
      // ObjectBox must roll back the set AND session revision together.
      final checkpoint = _one(
        _checkpoints,
        WorkoutSessionStateEntity_.sessionUuid,
        sessionUuid,
      );
      if (checkpoint == null) throw StateError('Missing checkpoint');
      checkpoint.selectedExerciseUuid = set.exerciseUuid;
      checkpoint.selectedSetUuid = set.uuid;
      checkpoint.checkpointRevision = session.revision;
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      if (set.status == WorkoutSetStatus.completed &&
          restSeconds != null &&
          restSeconds > 0 &&
          session.status == WorkoutStatus.inProgress.name) {
        checkpoint.restState = 'running';
        checkpoint.restDeadlineUtcMs = now + restSeconds * 1000;
        checkpoint.restRemainingMsWhenPaused = null;
      }
      checkpoint.savedAtMs = now > checkpoint.savedAtMs
          ? now
          : checkpoint.savedAtMs + 1;
      _checkpoints.put(checkpoint);
    });
  }

  @override
  void finishSession(
    String uuid, {
    required int expectedRevision,
    required DateTime finishedAtUtc,
  }) {
    if (expectedRevision < 1) throw ArgumentError.value(expectedRevision);
    _store.runInTransaction(TxMode.write, () {
      final session = _one(_sessions, WorkoutSessionEntity_.uuid, uuid);
      if (session == null || session.deletedAtMs != null) {
        throw StateError('Session does not exist or was deleted');
      }
      // This deprecated entry point must never bypass the same
      // optimistic-concurrency contract enforced by LiveWorkoutEngine.
      if (session.revision != expectedRevision) {
        throw WorkoutRevisionConflict(expectedRevision, session.revision);
      }
      if (session.status != WorkoutStatus.inProgress.name &&
          session.status != WorkoutStatus.paused.name) {
        throw StateError('Session is not active');
      }
      final endMs = finishedAtUtc.toUtc().millisecondsSinceEpoch;
      if (endMs < session.startedAtMs) {
        throw ArgumentError('End before start');
      }
      final checkpoint = _one(
        _checkpoints,
        WorkoutSessionStateEntity_.sessionUuid,
        uuid,
      );
      if (checkpoint == null ||
          checkpoint.checkpointRevision != session.revision) {
        throw StateError('Missing or outdated checkpoint');
      }
      session.status = WorkoutStatus.completed.name;
      session.completedAtMs = endMs;
      _touch(session);
      _checkpoints.remove(checkpoint.id);
      outbox?.enqueueCompletedInTransaction(uuid);
    });
  }

  @override
  void removeSet({
    required String sessionUuid,
    required String setUuid,
    required int expectedRevision,
  }) {
    if (expectedRevision < 1) throw ArgumentError.value(expectedRevision);
    _store.runInTransaction(TxMode.write, () {
      final session = _one(_sessions, WorkoutSessionEntity_.uuid, sessionUuid);
      if (session == null || session.deletedAtMs != null) {
        throw StateError('Session does not exist or was deleted');
      }
      final prior = _one(_sets, WorkoutSetEntity_.uuid, setUuid);
      if (prior == null) return; // Exact retry after a committed removal.
      final exercise = _one(
        _exercises,
        WorkoutExerciseEntity_.uuid,
        prior.exerciseUuid,
      );
      if (exercise == null || exercise.sessionUuid != sessionUuid) {
        throw StateError('Set does not belong to session');
      }
      if (session.status != WorkoutStatus.inProgress.name &&
          session.status != WorkoutStatus.paused.name) {
        throw StateError('No editable session');
      }
      if (session.revision != expectedRevision) {
        throw WorkoutRevisionConflict(expectedRevision, session.revision);
      }
      _sets.remove(prior.id);
      final siblings = _matching(
        _sets,
        WorkoutSetEntity_.exerciseUuid,
        prior.exerciseUuid,
      )..sort((a, b) => a.position.compareTo(b.position));
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      for (var i = 0; i < siblings.length; i++) {
        if (siblings[i].position == i) continue;
        siblings[i].position = i;
        siblings[i].updatedAtMs = now;
        _sets.put(siblings[i]);
      }
      _touch(session);
      final checkpoint = _one(
        _checkpoints,
        WorkoutSessionStateEntity_.sessionUuid,
        sessionUuid,
      );
      if (checkpoint == null) throw StateError('Missing checkpoint');
      if (checkpoint.selectedSetUuid == setUuid) {
        checkpoint.selectedSetUuid = null;
      }
      checkpoint.checkpointRevision = session.revision;
      checkpoint.savedAtMs = now > checkpoint.savedAtMs
          ? now
          : checkpoint.savedAtMs + 1;
      _checkpoints.put(checkpoint);
    });
  }

  void _touch(WorkoutSessionEntity session) {
    session.revision += 1;
    session.updatedAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    _sessions.put(session);
  }
}
