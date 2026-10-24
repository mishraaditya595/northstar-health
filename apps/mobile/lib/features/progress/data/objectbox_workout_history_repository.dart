import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/objectbox_store_provider.dart';
import '../../../core/units/load_units.dart';
import '../../../objectbox.g.dart';
import '../../workouts/data/workout_entities.dart';
import '../../workouts/domain/workout_models.dart';
import '../../workouts/domain/workout_status_codec.dart';
import '../domain/workout_history_models.dart';

abstract interface class WorkoutHistoryRepository {
  WorkoutHistorySnapshot readCompleted();
  Future<WorkoutHistorySnapshot> readCompletedAsync();
}

final workoutHistoryRepositoryProvider = Provider<WorkoutHistoryRepository>(
  (ref) => ObjectBoxWorkoutHistoryRepository(ref.watch(objectBoxStoreProvider)),
);

/// Read-only completed-session projection. Query and child hydration execute
/// together in one transaction, off the UI isolate for async consumers.
class ObjectBoxWorkoutHistoryRepository implements WorkoutHistoryRepository {
  ObjectBoxWorkoutHistoryRepository(Store store)
    : _store = store,
      _sessions = store.box<WorkoutSessionEntity>(),
      _exercises = store.box<WorkoutExerciseEntity>(),
      _sets = store.box<WorkoutSetEntity>();

  static const int _batchSize = 200;
  final Store _store;
  final Box<WorkoutSessionEntity> _sessions;
  final Box<WorkoutExerciseEntity> _exercises;
  final Box<WorkoutSetEntity> _sets;

  @override
  Future<WorkoutHistorySnapshot> readCompletedAsync() =>
      _store.runInTransactionAsync(TxMode.read, readHistoryOnWorker, 0);

  List<WorkoutExerciseEntity> _getExercises(List<String> uuids) {
    final result = <WorkoutExerciseEntity>[];
    for (var i = 0; i < uuids.length; i += _batchSize) {
      final end = i + _batchSize < uuids.length ? i + _batchSize : uuids.length;
      final query = _exercises
          .query(
            WorkoutExerciseEntity_.sessionUuid.oneOf(uuids.sublist(i, end)),
          )
          .build();
      try {
        result.addAll(query.find());
      } finally {
        query.close();
      }
    }
    return result;
  }

  List<WorkoutSetEntity> _getSets(List<String> uuids) {
    final result = <WorkoutSetEntity>[];
    for (var i = 0; i < uuids.length; i += _batchSize) {
      final end = i + _batchSize < uuids.length ? i + _batchSize : uuids.length;
      final query = _sets
          .query(WorkoutSetEntity_.exerciseUuid.oneOf(uuids.sublist(i, end)))
          .build();
      try {
        result.addAll(query.find());
      } finally {
        query.close();
      }
    }
    return result;
  }

  @override
  WorkoutHistorySnapshot readCompleted() => _store.runInTransaction(
    TxMode.read,
    () {
      final query = _sessions
          .query(
            WorkoutSessionEntity_.status.equals(WorkoutStatus.completed.name) &
                WorkoutSessionEntity_.origin.equals('northstar_phone') &
                WorkoutSessionEntity_.deletedAtMs.isNull() &
                WorkoutSessionEntity_.completedAtMs.notNull(),
          )
          .build();
      late final List<WorkoutSessionEntity> rows;
      try {
        rows = query.find()
          ..sort((a, b) {
            final diff = b.completedAtMs!.compareTo(a.completedAtMs!);
            return diff != 0 ? diff : a.uuid.compareTo(b.uuid);
          });
      } finally {
        query.close();
      }
      if (rows.isEmpty) {
        return const WorkoutHistorySnapshot(sessions: []);
      }
      final exercises = _getExercises([for (final s in rows) s.uuid]);
      final setsByExercise = <String, List<WorkoutSetRecord>>{};
      final loadedSets = _getSets([for (final e in exercises) e.uuid]);
      for (final set in loadedSets) {
        setsByExercise
            .putIfAbsent(set.exerciseUuid, () => [])
            .add(
              WorkoutSetRecord(
                uuid: set.uuid,
                exerciseUuid: set.exerciseUuid,
                position: set.position,
                kind: workoutSetKindFromStorage(set.kind),
                status: workoutSetStatusFromStorage(set.status),
                reps: set.reps,
                loadGrams: set.loadGrams,
                inputUnit: loadUnitFromStorage(set.inputUnit),
                rpe: set.rpe,
                completedAtUtc: set.completedAtMs == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(
                        set.completedAtMs!,
                        isUtc: true,
                      ),
              ),
            );
      }
      final exercisesBySession = <String, List<WorkoutExerciseEntity>>{};
      for (final e in exercises) {
        exercisesBySession.putIfAbsent(e.sessionUuid, () => []).add(e);
      }
      final sessions = <WorkoutSessionRecord>[];
      for (final s in rows) {
        final children = exercisesBySession[s.uuid] ?? [];
        children.sort((a, b) {
          final position = a.position.compareTo(b.position);
          return position != 0 ? position : a.uuid.compareTo(b.uuid);
        });
        final workoutExercises = <WorkoutExerciseRecord>[];
        final workoutSets = <WorkoutSetRecord>[];
        for (final e in children) {
          workoutExercises.add(
            WorkoutExerciseRecord(
              uuid: e.uuid,
              sessionUuid: s.uuid,
              definitionUuid: e.definitionUuid,
              nameSnapshot: e.nameSnapshot,
              muscleSnapshot: e.muscleSnapshot,
              equipmentSnapshot: e.equipmentSnapshot,
              position: e.position,
            ),
          );
          final childSets = setsByExercise[e.uuid] ?? [];
          childSets.sort((a, b) {
            final position = a.position.compareTo(b.position);
            return position != 0 ? position : a.uuid.compareTo(b.uuid);
          });
          workoutSets.addAll(childSets);
        }
        sessions.add(
          WorkoutSessionRecord(
            uuid: s.uuid,
            name: s.name,
            status: WorkoutStatus.completed,
            startedAtUtc: DateTime.fromMillisecondsSinceEpoch(
              s.startedAtMs,
              isUtc: true,
            ),
            completedAtUtc: DateTime.fromMillisecondsSinceEpoch(
              s.completedAtMs!,
              isUtc: true,
            ),
            originalOffsetMinutes: s.originalOffsetMinutes,
            revision: s.revision,
            planUuid: s.planUuid,
            exercises: List.unmodifiable(workoutExercises),
            sets: List.unmodifiable(workoutSets),
          ),
        );
      }
      return WorkoutHistorySnapshot(sessions: List.unmodifiable(sessions));
    },
  );
}

/// Worker-isolate callback contains only a native Store handle and a primitive.
WorkoutHistorySnapshot readHistoryOnWorker(Store store, int _) =>
    ObjectBoxWorkoutHistoryRepository(store).readCompleted();
