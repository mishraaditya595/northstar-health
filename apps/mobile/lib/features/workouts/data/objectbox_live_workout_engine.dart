import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ids/uuid_factory.dart';
import '../../../core/storage/objectbox_store_provider.dart';
import '../../../objectbox.g.dart';
import '../domain/live_workout_engine.dart';
import '../domain/workout_models.dart';
import '../domain/workout_repository.dart';
import 'objectbox_workout_repository.dart';
import 'workout_entities.dart';

final liveWorkoutEngineProvider = Provider<LiveWorkoutEngine>(
  (ref) => ObjectBoxLiveWorkoutEngine(ref.watch(objectBoxStoreProvider)),
);

/// Coordinates the full local workout lifecycle without changing ObjectBox's
/// committed v1 schema or leaking persistence entities into presentation.
///
/// The existing workout repository remains responsible for revision-checked
/// individual set writes; this engine handles one atomic plan-to-session
/// materialization and the session lifecycle.
class ObjectBoxLiveWorkoutEngine implements LiveWorkoutEngine {
  ObjectBoxLiveWorkoutEngine(Store store, {UuidFactory? uuidFactory})
    : _store = store,
      _ids = uuidFactory ?? SecureUuidFactory(),
      _reader = ObjectBoxWorkoutRepository(store),
      _sessions = store.box<WorkoutSessionEntity>(),
      _exercises = store.box<WorkoutExerciseEntity>(),
      _sets = store.box<WorkoutSetEntity>(),
      _checkpoints = store.box<WorkoutSessionStateEntity>(),
      _plans = store.box<WorkoutPlanEntity>(),
      _planExercises = store.box<PlanExerciseEntity>(),
      _definitions = store.box<ExerciseDefinitionEntity>();

  final Store _store;
  final UuidFactory _ids;
  final ObjectBoxWorkoutRepository _reader;
  final Box<WorkoutSessionEntity> _sessions;
  final Box<WorkoutExerciseEntity> _exercises;
  final Box<WorkoutSetEntity> _sets;
  final Box<WorkoutSessionStateEntity> _checkpoints;
  final Box<WorkoutPlanEntity> _plans;
  final Box<PlanExerciseEntity> _planExercises;
  final Box<ExerciseDefinitionEntity> _definitions;

  T? _one<T>(Box<T> box, QueryStringProperty<T> property, String uuid) {
    final query = box.query(property.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  List<PlanExerciseEntity> _templateRows(String uuid) {
    final query = _planExercises
        .query(PlanExerciseEntity_.planUuid.equals(uuid))
        .build();
    try {
      return query.find()..sort((a, b) => a.position.compareTo(b.position));
    } finally {
      query.close();
    }
  }

  bool _isUnfinished(WorkoutSessionEntity session) =>
      session.deletedAtMs == null &&
      session.status != WorkoutStatus.completed.name &&
      session.status != WorkoutStatus.discarded.name;

  WorkoutSessionEntity? _singleUnfinished() {
    final pending = _sessions.getAll().where(_isUnfinished).toList();
    if (pending.length > 1) {
      throw StateError('Multiple unfinished sessions require recovery review');
    }
    return pending.isEmpty ? null : pending.single;
  }

  @override
  WorkoutSessionRecord startWorkout({
    required String sessionUuid,
    String? planUuid,
    String? quickName,
    required DateTime startedAtUtc,
    required int originalOffsetMinutes,
  }) {
    if (sessionUuid.isEmpty ||
        (planUuid == null) == (quickName == null) ||
        (planUuid != null && planUuid.isEmpty) ||
        originalOffsetMinutes < -840 ||
        originalOffsetMinutes > 840) {
      throw ArgumentError('Choose exactly one valid workout source and offset');
    }
    if (quickName != null &&
        (quickName.trim().isEmpty || quickName.trim().length > 160)) {
      throw ArgumentError.value(quickName, 'quickName');
    }
    final atMs = startedAtUtc.toUtc().millisecondsSinceEpoch;
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    _store.runInTransaction(TxMode.write, () {
      final prior = _one(_sessions, WorkoutSessionEntity_.uuid, sessionUuid);
      if (prior != null) {
        if (prior.deletedAtMs != null ||
            prior.planUuid != planUuid ||
            prior.startedAtMs != atMs ||
            prior.originalOffsetMinutes != originalOffsetMinutes ||
            (quickName != null && prior.name != quickName.trim())) {
          throw StateError('Conflicting session UUID');
        }
        // Idempotent replay: status may now be completed; do not resurrect it.
        return;
      }
      final active = _singleUnfinished();
      if (active != null) {
        throw StateError('Finish or discard the existing workout first');
      }
      final plan = planUuid == null
          ? null
          : _one(_plans, WorkoutPlanEntity_.uuid, planUuid);
      if (planUuid != null && (plan == null || plan.archivedAtMs != null)) {
        throw StateError('Source training plan is missing or archived');
      }
      final children = plan == null
          ? <PlanExerciseEntity>[]
          : _templateRows(plan.uuid);
      final template = <(PlanExerciseEntity, ExerciseDefinitionEntity)>[];
      for (var i = 0; i < children.length; i++) {
        final row = children[i];
        if (row.position != i || row.targetSets < 1 || row.targetSets > 30) {
          throw StateError('Plan ordering or target sets are invalid');
        }
        final definition = _one(
          _definitions,
          ExerciseDefinitionEntity_.uuid,
          row.exerciseUuid,
        );
        if (definition == null) {
          throw StateError('Training plan references a missing exercise');
        }
        // Archived definitions may be retained in a previously saved plan;
        // use their stored names, not a mutable future lookup.
        template.add((row, definition));
      }
      final label = plan?.name ?? quickName!.trim();
      if (label.isEmpty || label.length > 160) {
        throw StateError('Invalid workout name');
      }
      _sessions.put(
        WorkoutSessionEntity(
          uuid: sessionUuid,
          name: label,
          planUuid: planUuid,
          startedAtMs: atMs,
          originalOffsetMinutes: originalOffsetMinutes,
          updatedAtMs: nowMs,
        ),
      );
      String? firstExerciseUuid;
      for (final (row, definition) in template) {
        final exerciseUuid = _ids.newId();
        firstExerciseUuid ??= exerciseUuid;
        _exercises.put(
          WorkoutExerciseEntity(
            uuid: exerciseUuid,
            sessionUuid: sessionUuid,
            definitionUuid: definition.uuid,
            nameSnapshot: definition.name,
            muscleSnapshot: definition.muscleGroup,
            equipmentSnapshot: definition.equipment,
            position: row.position,
          ),
        );
        for (var position = 0; position < row.targetSets; position++) {
          // Targets are prescriptions, not performed reps/loads. Never
          // populate completed workout metrics with plan guesses.
          _sets.put(
            WorkoutSetEntity(
              uuid: _ids.newId(),
              exerciseUuid: exerciseUuid,
              position: position,
              updatedAtMs: nowMs,
            ),
          );
        }
      }
      _checkpoints.put(
        WorkoutSessionStateEntity(
          sessionUuid: sessionUuid,
          selectedExerciseUuid: firstExerciseUuid,
          checkpointRevision: 1,
          savedAtMs: nowMs,
        ),
      );
    });
    return _reader.getSession(sessionUuid)!;
  }

  @override
  WorkoutSessionRecord? recoverActiveWorkout() {
    final sessionUuid = _store.runInTransaction(TxMode.read, () {
      final active = _singleUnfinished();
      if (active == null) return null;
      if (active.status != WorkoutStatus.inProgress.name &&
          active.status != WorkoutStatus.paused.name) {
        throw StateError('Unsupported unfinished workout state');
      }
      if (_one(
            _checkpoints,
            WorkoutSessionStateEntity_.sessionUuid,
            active.uuid,
          ) ==
          null) {
        throw StateError('Unfinished workout checkpoint is missing');
      }
      return active.uuid;
    });
    return sessionUuid == null ? null : _reader.getSession(sessionUuid);
  }

  @override
  WorkoutRecoveryCheckpoint? readCheckpoint(String sessionUuid) {
    return _store.runInTransaction(TxMode.read, () {
      final saved = _one(
        _checkpoints,
        WorkoutSessionStateEntity_.sessionUuid,
        sessionUuid,
      );
      return saved == null
          ? null
          : WorkoutRecoveryCheckpoint(
              sessionUuid: saved.sessionUuid,
              checkpointRevision: saved.checkpointRevision,
              selectedExerciseUuid: saved.selectedExerciseUuid,
              selectedSetUuid: saved.selectedSetUuid,
            );
    });
  }

  @override
  WorkoutSessionRecord pauseWorkout(
    String sessionUuid, {
    required int expectedRevision,
  }) => _changeStatus(
    sessionUuid,
    expectedRevision: expectedRevision,
    from: WorkoutStatus.inProgress,
    to: WorkoutStatus.paused,
  );

  @override
  WorkoutSessionRecord resumeWorkout(
    String sessionUuid, {
    required int expectedRevision,
  }) => _changeStatus(
    sessionUuid,
    expectedRevision: expectedRevision,
    from: WorkoutStatus.paused,
    to: WorkoutStatus.inProgress,
  );

  WorkoutSessionRecord _changeStatus(
    String uuid, {
    required int expectedRevision,
    required WorkoutStatus from,
    required WorkoutStatus to,
  }) {
    if (expectedRevision < 1) throw ArgumentError.value(expectedRevision);
    _store.runInTransaction(TxMode.write, () {
      final session = _one(_sessions, WorkoutSessionEntity_.uuid, uuid);
      if (session == null || session.deletedAtMs != null) {
        throw StateError('Workout is missing or deleted');
      }
      if (session.status == to.name &&
          session.revision == expectedRevision + 1) {
        return; // Acknowledged retry of the same state transition.
      }
      if (session.revision != expectedRevision) {
        throw WorkoutRevisionConflict(expectedRevision, session.revision);
      }
      if (session.status != from.name)
        throw StateError('Illegal workout transition');
      final checkpoint = _requireCheckpoint(uuid);
      session.status = to.name;
      _touch(session);
      _touchCheckpoint(checkpoint, session.revision);
    });
    return _reader.getSession(uuid)!;
  }

  @override
  WorkoutSessionRecord finishWorkout(
    String uuid, {
    required int expectedRevision,
    required DateTime finishedAtUtc,
  }) {
    if (expectedRevision < 1) throw ArgumentError.value(expectedRevision);
    final atMs = finishedAtUtc.toUtc().millisecondsSinceEpoch;
    _store.runInTransaction(TxMode.write, () {
      final s = _one(_sessions, WorkoutSessionEntity_.uuid, uuid);
      if (s == null || s.deletedAtMs != null) {
        throw StateError('Workout is missing or deleted');
      }
      if (s.status == WorkoutStatus.completed.name &&
          s.completedAtMs == atMs &&
          s.revision == expectedRevision + 1) {
        return; // Exact replay of finish after an ACK was lost.
      }
      if (s.revision != expectedRevision) {
        throw WorkoutRevisionConflict(expectedRevision, s.revision);
      }
      if (s.status != WorkoutStatus.inProgress.name &&
          s.status != WorkoutStatus.paused.name) {
        throw StateError('Workout cannot be finished');
      }
      if (atMs < s.startedAtMs) {
        throw ArgumentError('End precedes start');
      }
      final checkpoint = _requireCheckpoint(uuid);
      s.status = WorkoutStatus.completed.name;
      s.completedAtMs = atMs;
      _touch(s);
      _checkpoints.remove(checkpoint.id);
    });
    return _reader.getSession(uuid)!;
  }

  @override
  WorkoutSessionRecord discardWorkout(
    String uuid, {
    required int expectedRevision,
  }) {
    if (expectedRevision < 1) throw ArgumentError.value(expectedRevision);
    _store.runInTransaction(TxMode.write, () {
      final s = _one(_sessions, WorkoutSessionEntity_.uuid, uuid);
      if (s == null || s.deletedAtMs != null) {
        throw StateError('Workout is missing or deleted');
      }
      if (s.status == WorkoutStatus.discarded.name &&
          s.revision == expectedRevision + 1) {
        return; // Idempotent retry after durable discard.
      }
      if (s.revision != expectedRevision) {
        throw WorkoutRevisionConflict(expectedRevision, s.revision);
      }
      if (s.status != WorkoutStatus.inProgress.name &&
          s.status != WorkoutStatus.paused.name) {
        throw StateError('Workout cannot be discarded');
      }
      final checkpoint = _requireCheckpoint(uuid);
      s.status = WorkoutStatus.discarded.name;
      _touch(s);
      _checkpoints.remove(checkpoint.id);
    });
    return _reader.getSession(uuid)!;
  }

  WorkoutSessionStateEntity _requireCheckpoint(String uuid) {
    final checkpoint = _one(
      _checkpoints,
      WorkoutSessionStateEntity_.sessionUuid,
      uuid,
    );
    if (checkpoint == null) throw StateError('Workout checkpoint is missing');
    return checkpoint;
  }

  void _touch(WorkoutSessionEntity session) {
    session.revision++;
    session.updatedAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    _sessions.put(session);
  }

  void _touchCheckpoint(WorkoutSessionStateEntity checkpoint, int revision) {
    checkpoint.checkpointRevision = revision;
    checkpoint.savedAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    _checkpoints.put(checkpoint);
  }
}
