import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_library_repository.dart';
import 'package:northstar_health/features/workouts/data/workout_entities.dart';
import 'package:northstar_health/features/workouts/domain/workout_library_models.dart';
import 'package:northstar_health/objectbox.g.dart';

void main() {
  late Directory directory;
  late Store store;
  late ObjectBoxWorkoutLibraryRepository library;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('northstar-library-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    library = ObjectBoxWorkoutLibraryRepository(store);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  PlanExerciseRecord part(String uuid, String exerciseId, int position) =>
      PlanExerciseRecord(
        uuid: uuid,
        exerciseUuid: exerciseId,
        position: position,
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 12,
        restSeconds: 90,
      );

  test(
    'seeding is idempotent across reopen and never duplicates definitions',
    () {
      library.ensureCatalogSeeded();
      final names = library.listExercises();
      expect(names, hasLength(18));
      expect(names.every((e) => e.isBuiltIn), isTrue);
      expect(names.map((e) => e.uuid).toSet(), hasLength(names.length));
      library.ensureCatalogSeeded();
      expect(library.listExercises(), hasLength(18));
      store.close();
      store = Store(getObjectBoxModel(), directory: directory.path);
      library = ObjectBoxWorkoutLibraryRepository(store);
      library.ensureCatalogSeeded();
      expect(library.listExercises(), hasLength(18));
      expect(
        () => library.archiveCustomExercise('builtin.v1.squat'),
        throwsStateError,
      );
    },
  );

  test(
    'custom definition persists after edit/reopen and archive is soft only',
    () {
      library.ensureCatalogSeeded();
      final created = library.saveCustomExercise(
        uuid: 'custom-1',
        name: 'Machine chest press',
        muscleGroup: 'Chest',
        equipment: 'Machine',
      );
      expect(created.isBuiltIn, isFalse);
      expect(
        () => library.saveCustomExercise(
          uuid: 'custom-2',
          name: 'machine CHEST press',
          muscleGroup: 'Chest',
          equipment: 'Machine',
        ),
        throwsStateError,
      );
      final updated = library.saveCustomExercise(
        uuid: 'custom-1',
        name: 'Machine incline press',
        muscleGroup: 'Chest',
        equipment: 'Machine',
        expectedUpdatedAtMs: created.updatedAtMs,
      );
      expect(updated.updatedAtMs, greaterThan(created.updatedAtMs));
      expect(
        () => library.saveCustomExercise(
          uuid: 'custom-1',
          name: 'Older update',
          muscleGroup: 'Chest',
          equipment: 'Machine',
          expectedUpdatedAtMs: created.updatedAtMs,
        ),
        throwsStateError,
      );
      store.close();
      store = Store(getObjectBoxModel(), directory: directory.path);
      library = ObjectBoxWorkoutLibraryRepository(store);
      expect(
        library.listExercises().singleWhere((e) => e.uuid == 'custom-1').name,
        'Machine incline press',
      );
      library.archiveCustomExercise('custom-1');
      expect(
        library.listExercises().where((e) => e.uuid == 'custom-1'),
        isEmpty,
      );
      expect(
        library
            .listExercises(includeArchived: true)
            .singleWhere((e) => e.uuid == 'custom-1')
            .archivedAtMs,
        isNotNull,
      );
    },
  );

  test(
    'plan template keeps contiguous ordered instructions after edit and reopen',
    () {
      library.ensureCatalogSeeded();
      final created = library.savePlan(
        uuid: 'plan-a',
        name: 'Full body A',
        description: 'Strength training',
        exercises: [
          part('item-a', 'builtin.v1.squat', 0),
          part('item-b', 'builtin.v1.bench-press', 1),
        ],
      );
      expect(created.exercises.map((e) => e.position), [0, 1]);
      final revised = library.savePlan(
        uuid: 'plan-a',
        name: 'Full body A — revised',
        description: '',
        expectedUpdatedAtMs: created.updatedAtMs,
        exercises: [
          part('item-b', 'builtin.v1.bench-press', 0),
          part('item-a', 'builtin.v1.squat', 1),
        ],
      );
      expect(revised.updatedAtMs, greaterThan(created.updatedAtMs));
      store.close();
      store = Store(getObjectBoxModel(), directory: directory.path);
      library = ObjectBoxWorkoutLibraryRepository(store);
      final loaded = library.getPlan('plan-a')!;
      expect(loaded.name, 'Full body A — revised');
      expect(loaded.exercises.map((e) => e.uuid), ['item-b', 'item-a']);
      expect(loaded.exercises.first.targetRepsMin, 8);
      expect(library.listPlans(), hasLength(1));
    },
  );

  test(
    'stale plan editor and validation errors cannot partially edit template',
    () {
      library.ensureCatalogSeeded();
      final created = library.savePlan(
        uuid: 'plan-a',
        name: 'Original',
        description: '',
        exercises: [part('item-a', 'builtin.v1.squat', 0)],
      );
      final newer = library.savePlan(
        uuid: 'plan-a',
        name: 'Changed',
        description: '',
        expectedUpdatedAtMs: created.updatedAtMs,
        exercises: [part('item-a', 'builtin.v1.squat', 0)],
      );
      expect(
        () => library.savePlan(
          uuid: 'plan-a',
          name: 'Late write',
          description: '',
          expectedUpdatedAtMs: created.updatedAtMs,
          exercises: [],
        ),
        throwsA(isA<PlanEditConflict>()),
      );
      expect(
        () => library.savePlan(
          uuid: 'plan-a',
          name: 'Invalid position',
          description: '',
          expectedUpdatedAtMs: newer.updatedAtMs,
          exercises: [part('item-x', 'builtin.v1.squat', 5)],
        ),
        throwsArgumentError,
      );
      final stable = library.getPlan('plan-a')!;
      expect(stable.name, 'Changed');
      expect(stable.exercises.single.uuid, 'item-a');
    },
  );

  test(
    'uniqueness violation after writing a plan header rolls back transaction',
    () {
      library.ensureCatalogSeeded();
      library.savePlan(
        uuid: 'plan-a',
        name: 'A',
        description: '',
        exercises: [part('shared-uuid', 'builtin.v1.squat', 0)],
      );
      expect(
        () => library.savePlan(
          uuid: 'plan-b',
          name: 'B should roll back',
          description: '',
          exercises: [
            part('different-uuid', 'builtin.v1.bench-press', 0),
            part('shared-uuid', 'builtin.v1.squat', 1),
          ],
        ),
        throwsA(anything),
      );
      expect(library.getPlan('plan-b'), isNull);
      expect(store.box<PlanExerciseEntity>().count(), 1);
      expect(library.getPlan('plan-a')!.exercises.single.uuid, 'shared-uuid');
    },
  );

  test(
    'archived custom exercise remains available to existing plan snapshots',
    () {
      library.ensureCatalogSeeded();
      library.saveCustomExercise(
        uuid: 'custom-1',
        name: 'My home cable row',
        muscleGroup: 'Back',
        equipment: 'Cable',
      );
      library.savePlan(
        uuid: 'plan-a',
        name: 'Upper',
        description: '',
        exercises: [part('item-a', 'custom-1', 0)],
      );
      library.archiveCustomExercise('custom-1');
      expect(
        library.getPlan('plan-a')!.exercises.single.exerciseUuid,
        'custom-1',
      );
      expect(
        library
            .listExercises(includeArchived: true)
            .singleWhere((e) => e.uuid == 'custom-1')
            .name,
        'My home cable row',
      );
      library.archivePlan(
        'plan-a',
        expectedUpdatedAtMs: library.getPlan('plan-a')!.updatedAtMs,
      );
      expect(library.listPlans(), isEmpty);
      expect(library.getPlan('plan-a'), isNull);
      expect(store.box<PlanExerciseEntity>().count(), 1);
    },
  );

  test(
    'rejects missing exercise, duplicate item UUIDs and bad prescriptions',
    () {
      library.ensureCatalogSeeded();
      expect(
        () => library.savePlan(
          uuid: 'bad',
          name: 'Bad',
          description: '',
          exercises: [part('item-a', 'missing', 0)],
        ),
        throwsStateError,
      );
      expect(
        () => library.savePlan(
          uuid: 'bad',
          name: 'Bad',
          description: '',
          exercises: [
            part('item-a', 'builtin.v1.squat', 0),
            part('item-a', 'builtin.v1.squat', 1),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => library.savePlan(
          uuid: 'bad',
          name: 'Bad',
          description: '',
          exercises: [
            const PlanExerciseRecord(
              uuid: 'item-a',
              exerciseUuid: 'builtin.v1.squat',
              position: 0,
              targetSets: 3,
              targetRepsMin: 12,
              targetRepsMax: 8,
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(library.listPlans(), isEmpty);
    },
  );

  test('archived exercise may be retained but never newly attached', () {
    library.ensureCatalogSeeded();
    library.saveCustomExercise(
      uuid: 'custom-row',
      name: 'Cable row custom',
      muscleGroup: 'Back',
      equipment: 'Cable',
    );
    final existing = library.savePlan(
      uuid: 'old-plan',
      name: 'Old',
      description: '',
      exercises: [part('original-row', 'custom-row', 0)],
    );
    library.archiveCustomExercise('custom-row');
    final retained = library.savePlan(
      uuid: 'old-plan',
      name: 'Retained',
      description: '',
      expectedUpdatedAtMs: existing.updatedAtMs,
      exercises: [part('original-row', 'custom-row', 0)],
    );
    expect(retained.exercises.single.uuid, 'original-row');

    expect(
      () => library.savePlan(
        uuid: 'new-plan',
        name: 'Bad',
        description: '',
        exercises: [part('new-row', 'custom-row', 0)],
      ),
      throwsA(isA<ArchivedExercisePlanConflict>()),
    );
    expect(library.getPlan('new-plan'), isNull);
    expect(
      () => library.savePlan(
        uuid: 'old-plan',
        name: 'Should roll back',
        description: '',
        expectedUpdatedAtMs: retained.updatedAtMs,
        exercises: [
          part('original-row', 'custom-row', 0),
          part('added-row', 'custom-row', 1),
        ],
      ),
      throwsA(isA<ArchivedExercisePlanConflict>()),
    );
    expect(library.getPlan('old-plan')!.name, 'Retained');
    expect(library.getPlan('old-plan')!.exercises, hasLength(1));
  });

  test('removing a plan exercise never removes another plan row', () {
    library.ensureCatalogSeeded();
    final a = library.savePlan(
      uuid: 'plan-a',
      name: 'A',
      description: '',
      exercises: [
        part('a-1', 'builtin.v1.squat', 0),
        part('a-2', 'builtin.v1.bench-press', 1),
      ],
    );
    library.savePlan(
      uuid: 'plan-b',
      name: 'B',
      description: '',
      exercises: [part('b-1', 'builtin.v1.squat', 0)],
    );
    library.savePlan(
      uuid: 'plan-a',
      name: 'A',
      description: '',
      expectedUpdatedAtMs: a.updatedAtMs,
      exercises: [part('a-1', 'builtin.v1.squat', 0)],
    );
    expect(library.getPlan('plan-a')!.exercises.map((e) => e.uuid), ['a-1']);
    expect(library.getPlan('plan-b')!.exercises.map((e) => e.uuid), ['b-1']);
    expect(store.box<PlanExerciseEntity>().count(), 2);
  });

  test('stale archive rejects updates and does not hide the edited plan', () {
    library.ensureCatalogSeeded();
    final original = library.savePlan(
      uuid: 'plan-a',
      name: 'First',
      description: '',
      exercises: [part('a-1', 'builtin.v1.squat', 0)],
    );
    final edited = library.savePlan(
      uuid: 'plan-a',
      name: 'Updated',
      description: '',
      exercises: [part('a-1', 'builtin.v1.squat', 0)],
      expectedUpdatedAtMs: original.updatedAtMs,
    );
    expect(
      () => library.archivePlan(
        'plan-a',
        expectedUpdatedAtMs: original.updatedAtMs,
      ),
      throwsA(isA<PlanEditConflict>()),
    );
    expect(library.getPlan('plan-a')!.name, 'Updated');
    library.archivePlan('plan-a', expectedUpdatedAtMs: edited.updatedAtMs);
    expect(library.getPlan('plan-a'), isNull);
  });
}
