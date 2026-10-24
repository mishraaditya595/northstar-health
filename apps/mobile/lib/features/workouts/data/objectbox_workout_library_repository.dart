import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/objectbox_store_provider.dart';
import '../../../objectbox.g.dart';
import '../domain/workout_library_models.dart';
import '../domain/workout_library_repository.dart';
import 'built_in_exercises.dart';
import 'workout_entities.dart';

final workoutLibraryRepositoryProvider = Provider<WorkoutLibraryRepository>((
  ref,
) {
  return ObjectBoxWorkoutLibraryRepository(ref.watch(objectBoxStoreProvider));
});

/// Only uses existing PR1 entities: deliberately no ObjectBox UID/schema change.
class ObjectBoxWorkoutLibraryRepository implements WorkoutLibraryRepository {
  ObjectBoxWorkoutLibraryRepository(this._store)
    : _catalog = _store.box<ExerciseDefinitionEntity>(),
      _plans = _store.box<WorkoutPlanEntity>(),
      _items = _store.box<PlanExerciseEntity>();

  final Store _store;
  final Box<ExerciseDefinitionEntity> _catalog;
  final Box<WorkoutPlanEntity> _plans;
  final Box<PlanExerciseEntity> _items;

  T? _byUuid<T>(Box<T> box, QueryStringProperty<T> prop, String uuid) {
    final query = box.query(prop.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  List<PlanExerciseEntity> _planItems(String planUuid) {
    final query = _items
        .query(PlanExerciseEntity_.planUuid.equals(planUuid))
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  @override
  void ensureCatalogSeeded() {
    _store.runInTransaction(TxMode.write, () {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      for (final item in builtInExercises) {
        final uuid = 'builtin.v1.${item.id}';
        if (_byUuid(_catalog, ExerciseDefinitionEntity_.uuid, uuid) != null) {
          continue;
        }
        _catalog.put(
          ExerciseDefinitionEntity(
            uuid: uuid,
            name: item.name,
            muscleGroup: item.muscle,
            equipment: item.equipment,
            movementCategory: item.category,
            inputMode: item.mode,
            isBuiltIn: true,
            catalogVersion: 1,
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );
      }
    });
  }

  ExerciseRecord _exercise(ExerciseDefinitionEntity e) => ExerciseRecord(
    uuid: e.uuid,
    name: e.name,
    muscleGroup: e.muscleGroup,
    equipment: e.equipment,
    movementCategory: e.movementCategory,
    inputMode: e.inputMode,
    isBuiltIn: e.isBuiltIn,
    updatedAtMs: e.updatedAtMs,
    archivedAtMs: e.archivedAtMs,
  );

  @override
  List<ExerciseRecord> listExercises({bool includeArchived = false}) {
    final entries = _catalog.getAll()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(
      entries
          .where((e) => includeArchived || e.archivedAtMs == null)
          .map(_exercise),
    );
  }

  @override
  ExerciseRecord saveCustomExercise({
    required String uuid,
    required String name,
    required String muscleGroup,
    required String equipment,
    int? expectedUpdatedAtMs,
  }) {
    final label = name.trim();
    if (uuid.isEmpty ||
        uuid.startsWith('builtin.') ||
        label.isEmpty ||
        label.length > 80 ||
        muscleGroup.trim().length > 60 ||
        equipment.trim().length > 60) {
      throw ArgumentError('Provide a valid custom exercise name');
    }
    return _store.runInTransaction(TxMode.write, () {
      final previous = _byUuid(_catalog, ExerciseDefinitionEntity_.uuid, uuid);
      if (previous?.isBuiltIn == true ||
          previous?.archivedAtMs != null ||
          (previous == null && expectedUpdatedAtMs != null) ||
          (previous != null && previous.updatedAtMs != expectedUpdatedAtMs)) {
        throw StateError('Exercise changed, was removed or is built in');
      }
      final duplicate = _catalog.getAll().any(
        (e) =>
            e.archivedAtMs == null &&
            e.uuid != uuid &&
            e.name.trim().toLowerCase() == label.toLowerCase(),
      );
      if (duplicate) {
        throw StateError('An exercise with this name already exists');
      }
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final next =
          previous ??
          ExerciseDefinitionEntity(
            uuid: uuid,
            name: label,
            createdAtMs: now,
            updatedAtMs: now,
          );
      next.name = label;
      next.muscleGroup = muscleGroup.trim();
      next.equipment = equipment.trim();
      next.updatedAtMs = previous == null
          ? now
          : (now > previous.updatedAtMs ? now : previous.updatedAtMs + 1);
      _catalog.put(next);
      return _exercise(next);
    });
  }

  @override
  void archiveCustomExercise(String uuid) {
    _store.runInTransaction(TxMode.write, () {
      final e = _byUuid(_catalog, ExerciseDefinitionEntity_.uuid, uuid);
      if (e == null || e.isBuiltIn) {
        throw StateError('Cannot archive built-in/unknown exercise');
      }
      if (e.archivedAtMs != null) return;
      e.archivedAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      _catalog.put(e); // Keep existing plans and workout snapshots readable.
    });
  }

  WorkoutPlanRecord _plan(WorkoutPlanEntity plan) {
    final exercises = _planItems(plan.uuid)
      ..sort((a, b) => a.position.compareTo(b.position));
    return WorkoutPlanRecord(
      uuid: plan.uuid,
      name: plan.name,
      description: plan.description,
      updatedAtMs: plan.updatedAtMs,
      archivedAtMs: plan.archivedAtMs,
      exercises: List.unmodifiable(
        exercises.map(
          (e) => PlanExerciseRecord(
            uuid: e.uuid,
            exerciseUuid: e.exerciseUuid,
            position: e.position,
            targetSets: e.targetSets,
            targetRepsMin: e.targetRepsMin,
            targetRepsMax: e.targetRepsMax,
            restSeconds: e.restSeconds,
            notes: e.notes,
          ),
        ),
      ),
    );
  }

  @override
  List<WorkoutPlanRecord> listPlans() {
    return _store.runInTransaction(TxMode.read, () {
      final list = _plans.getAll()
        ..removeWhere((e) => e.archivedAtMs != null)
        ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      return List.unmodifiable(list.map(_plan));
    });
  }

  @override
  WorkoutPlanRecord? getPlan(String uuid) {
    return _store.runInTransaction(TxMode.read, () {
      final plan = _byUuid(_plans, WorkoutPlanEntity_.uuid, uuid);
      return plan == null || plan.archivedAtMs != null ? null : _plan(plan);
    });
  }

  @override
  WorkoutPlanRecord savePlan({
    required String uuid,
    required String name,
    required String description,
    required List<PlanExerciseRecord> exercises,
    int? expectedUpdatedAtMs,
  }) {
    final label = name.trim();
    if (uuid.isEmpty ||
        label.isEmpty ||
        label.length > 100 ||
        description.length > 1000 ||
        exercises.length > 100) {
      throw ArgumentError('Invalid plan name or size');
    }
    final ids = <String>{};
    for (var i = 0; i < exercises.length; i++) {
      final item = exercises[i];
      item.validate();
      if (item.position != i || !ids.add(item.uuid)) {
        throw ArgumentError(
          'Plan items require unique UUIDs and contiguous order',
        );
      }
    }
    return _store.runInTransaction(TxMode.write, () {
      final original = _byUuid(_plans, WorkoutPlanEntity_.uuid, uuid);
      if (original?.archivedAtMs != null ||
          (original == null && expectedUpdatedAtMs != null) ||
          (original != null && original.updatedAtMs != expectedUpdatedAtMs)) {
        throw const PlanEditConflict();
      }
      // Reusing an already-saved row is allowed after its definition is
      // archived. Adding a fresh row referencing that definition is not.
      // The check lives inside the same write transaction as the plan save.
      final prior = original == null
          ? <PlanExerciseEntity>[]
          : _planItems(uuid);
      for (final item in exercises) {
        final definition = _byUuid(
          _catalog,
          ExerciseDefinitionEntity_.uuid,
          item.exerciseUuid,
        );
        if (definition == null) {
          throw StateError('Plan refers to an unknown exercise');
        }
        if (definition.archivedAtMs != null &&
            !prior.any(
              (saved) =>
                  saved.uuid == item.uuid &&
                  saved.exerciseUuid == item.exerciseUuid,
            )) {
          throw StateError('Archived exercise cannot be added to a plan');
        }
      }
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final next =
          original ??
          WorkoutPlanEntity(
            uuid: uuid,
            name: label,
            createdAtMs: now,
            updatedAtMs: now,
          );
      next.name = label;
      next.description = description.trim();
      next.updatedAtMs = original == null
          ? now
          : (now > original.updatedAtMs ? now : original.updatedAtMs + 1);
      _plans.put(next);
      // All child replacement occurs in the same transaction as the header.
      // An ObjectBox uniqueness error must roll back the header and children.
      if (prior.isNotEmpty) _items.removeMany(prior.map((e) => e.id).toList());
      for (final item in exercises) {
        _items.put(
          PlanExerciseEntity(
            uuid: item.uuid,
            planUuid: uuid,
            exerciseUuid: item.exerciseUuid,
            position: item.position,
            targetSets: item.targetSets,
            targetRepsMin: item.targetRepsMin,
            targetRepsMax: item.targetRepsMax,
            restSeconds: item.restSeconds,
            notes: item.notes.trim(),
          ),
        );
      }
      return _plan(next);
    });
  }

  @override
  void archivePlan(String uuid, {required int expectedUpdatedAtMs}) {
    _store.runInTransaction(TxMode.write, () {
      final plan = _byUuid(_plans, WorkoutPlanEntity_.uuid, uuid);
      if (plan == null) throw StateError('Unknown plan');
      if (plan.updatedAtMs != expectedUpdatedAtMs) {
        throw const PlanEditConflict();
      }
      if (plan.archivedAtMs != null) return;
      plan.archivedAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      _plans.put(plan); // Never delete history or referenced exercises.
    });
  }
}
