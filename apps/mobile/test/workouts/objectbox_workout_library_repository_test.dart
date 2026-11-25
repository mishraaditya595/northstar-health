import 'dart:io';

import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_library_repository.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:beyondrep/objectbox.g.dart';

class _FixedIds implements UuidFactory {
  _FixedIds(this.values);
  final List<String> values;
  var next = 0;

  @override
  String newId() => values[next++];
}

void main() {
  late Directory directory;
  late Store store;
  late ObjectBoxWorkoutLibraryRepository library;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-library-');
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
        throwsA(isA<UniqueViolationException>()),
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

  group('materializeCatalogExercise', () {
    ExerciseRecord materialize({
      String id = 'builtin.v1.row',
      String name = 'Barbell row',
      String muscleGroup = 'Back',
      String equipment = 'Barbell',
      String category = 'pull_horizontal',
      String mode = 'reps_load',
      int release = 1,
      List<String> primaryMuscles = const [],
      List<String> secondaryMuscles = const [],
    }) => library.materializeCatalogExercise(
      id: id,
      name: name,
      muscleGroup: muscleGroup,
      equipment: equipment,
      category: category,
      mode: mode,
      release: release,
      primaryMuscles: primaryMuscles,
      secondaryMuscles: secondaryMuscles,
    );

    ExerciseDefinitionEntity stored(String id) => store
        .box<ExerciseDefinitionEntity>()
        .query(ExerciseDefinitionEntity_.uuid.equals(id))
        .build()
        .findFirst()!;

    test('inserts a new catalogue exercise', () {
      final record = materialize(release: 3);
      expect(record.uuid, 'builtin.v1.row');
      expect(record.name, 'Barbell row');
      expect(record.muscleGroup, 'Back');
      expect(record.equipment, 'Barbell');
      expect(record.movementCategory, 'pull_horizontal');
      expect(record.inputMode, 'reps_load');
      expect(record.isBuiltIn, isTrue);
      expect(stored('builtin.v1.row').catalogVersion, 3);
      expect(library.listExercises().map((e) => e.uuid), contains(record.uuid));
    });

    test('is idempotent for the same release', () {
      final first = materialize(release: 2);
      final again = materialize(release: 2, name: 'Renamed but same release');
      expect(again.updatedAtMs, first.updatedAtMs);
      expect(again.name, 'Barbell row');
      expect(store.box<ExerciseDefinitionEntity>().count(), 1);
    });

    test('updates display fields for a newer release', () {
      final first = materialize(release: 1);
      final next = materialize(
        release: 2,
        name: 'Bent-over row',
        muscleGroup: 'Arms',
        equipment: 'Cable',
        category: 'isolation',
      );
      expect(next.name, 'Bent-over row');
      expect(next.muscleGroup, 'Arms');
      expect(next.equipment, 'Cable');
      expect(next.movementCategory, 'isolation');
      expect(next.updatedAtMs, greaterThanOrEqualTo(first.updatedAtMs));
      expect(stored('builtin.v1.row').catalogVersion, 2);
    });

    test('ignores an older release', () {
      materialize(release: 5);
      final again = materialize(release: 4, name: 'Old name');
      expect(again.name, 'Barbell row');
      expect(stored('builtin.v1.row').catalogVersion, 5);
    });

    test('never changes mode', () {
      materialize(release: 1);
      expect(
        () => materialize(release: 2, mode: 'duration', name: 'Changed'),
        throwsStateError,
      );
      final after = stored('builtin.v1.row');
      expect(after.inputMode, 'reps_load');
      expect(after.name, 'Barbell row');
      expect(after.catalogVersion, 1);
    });

    test('rejects a non-catalogue id', () {
      expect(() => materialize(id: 'custom-1'), throwsArgumentError);
      expect(() => materialize(id: 'builtin.v2.row'), throwsArgumentError);
      expect(store.box<ExerciseDefinitionEntity>().count(), 0);
    });

    test('rejects a catalogue id held by a custom exercise', () {
      store.box<ExerciseDefinitionEntity>().put(
        ExerciseDefinitionEntity(
          uuid: 'builtin.v1.row',
          name: 'Mine',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      );
      expect(() => materialize(release: 2), throwsStateError);
      expect(stored('builtin.v1.row').name, 'Mine');
    });

    test('legacy seeded squat is upgraded from catalogVersion 1 only by a '
        'newer release', () {
      library.ensureCatalogSeeded();
      final seeded = library.listExercises().firstWhere(
        (e) => e.uuid == 'builtin.v1.squat',
      );
      final same = materialize(
        id: 'builtin.v1.squat',
        name: 'Back squat',
        muscleGroup: seeded.muscleGroup,
        equipment: seeded.equipment,
        category: seeded.movementCategory,
        mode: seeded.inputMode,
        release: 1,
        primaryMuscles: const ['quads'],
        secondaryMuscles: const ['glutes'],
      );
      expect(same.name, seeded.name);
      final newer = materialize(
        id: 'builtin.v1.squat',
        name: 'Back squat',
        muscleGroup: seeded.muscleGroup,
        equipment: seeded.equipment,
        category: seeded.movementCategory,
        mode: seeded.inputMode,
        release: 2,
        primaryMuscles: const ['quads'],
        secondaryMuscles: const ['glutes'],
      );
      expect(newer.name, 'Back squat');
      expect(stored('builtin.v1.squat').catalogVersion, 2);
      expect(library.listExercises(), hasLength(18));
    });

    test('fills muscles on a seeded squat at the same release', () {
      library.ensureCatalogSeeded();
      expect(stored('builtin.v1.squat').primaryMuscles, isEmpty);
      final record = materialize(
        id: 'builtin.v1.squat',
        name: 'Squat',
        muscleGroup: 'Legs',
        category: 'Squat',
        release: 1,
        primaryMuscles: const ['quads', 'glutes'],
        secondaryMuscles: const ['hamstrings'],
      );
      expect(record.primaryMuscles, ['quads', 'glutes']);
      expect(record.secondaryMuscles, ['hamstrings']);
      expect(stored('builtin.v1.squat').primaryMuscles, ['quads', 'glutes']);
      expect(stored('builtin.v1.squat').catalogVersion, 1);
    });

    test('same release with muscles already set writes nothing', () {
      final first = materialize(
        release: 2,
        primaryMuscles: const ['lats'],
        secondaryMuscles: const ['biceps'],
      );
      final again = materialize(
        release: 2,
        name: 'Renamed',
        primaryMuscles: const ['lats', 'traps'],
      );
      expect(again.updatedAtMs, first.updatedAtMs);
      expect(again.primaryMuscles, ['lats']);
      expect(again.name, 'Barbell row');
    });

    test('invalid catalogue muscles are stored as empty lists', () {
      for (final (primary, secondary) in [
        (['adductors'], <String>[]),
        (['quads', 'quads'], <String>[]),
        (['quads'], ['quads']),
        (<String>[], ['glutes']),
      ]) {
        final record = materialize(
          id: 'builtin.v1.bad-${primary.join()}-${secondary.join()}',
          primaryMuscles: primary,
          secondaryMuscles: secondary,
        );
        expect(record.primaryMuscles, isEmpty, reason: '$primary/$secondary');
        expect(record.secondaryMuscles, isEmpty);
      }
    });

    test('a newer release replaces the muscles', () {
      materialize(release: 1, primaryMuscles: const ['lats']);
      final next = materialize(
        release: 2,
        primaryMuscles: const ['lats', 'traps'],
        secondaryMuscles: const ['biceps'],
      );
      expect(next.primaryMuscles, ['lats', 'traps']);
      expect(next.secondaryMuscles, ['biceps']);
    });

    test('plans referencing the exercise are untouched', () {
      materialize(release: 1);
      final plan = library.savePlan(
        uuid: 'plan-a',
        name: 'Pull',
        description: '',
        exercises: [part('part-1', 'builtin.v1.row', 0)],
      );
      materialize(release: 2, name: 'Bent-over row');
      final after = library.getPlan('plan-a')!;
      expect(after.updatedAtMs, plan.updatedAtMs);
      expect(after.exercises.single.exerciseUuid, 'builtin.v1.row');
      expect(after.exercises.single.targetSets, 3);
    });
  });
  group('syncCatalogDefinitions', () {
    CatalogDefinitionInput item(
      String id, {
      String mode = 'reps_load',
      List<String> primary = const ['quads'],
      List<String> secondary = const ['glutes'],
    }) => (
      id: id,
      name: 'Name of $id',
      muscleGroup: 'Legs',
      equipment: 'Barbell',
      category: 'Squat',
      mode: mode,
      primaryMuscles: primary,
      secondaryMuscles: secondary,
    );

    ExerciseDefinitionEntity stored(String id) => store
        .box<ExerciseDefinitionEntity>()
        .query(ExerciseDefinitionEntity_.uuid.equals(id))
        .build()
        .findFirst()!;

    test('updates seeded rows only', () {
      library.ensureCatalogSeeded();
      final count = library.syncCatalogDefinitions([
        item('builtin.v1.squat'),
        item('builtin.v1.not-local'),
      ], 1);
      expect(count, 1);
      expect(stored('builtin.v1.squat').primaryMuscles, ['quads']);
      expect(stored('builtin.v1.squat').secondaryMuscles, ['glutes']);
      expect(library.listExercises(), hasLength(18), reason: 'no inserts');
    });

    test('ignores custom rows even when the id looks like a catalogue id', () {
      store.box<ExerciseDefinitionEntity>().put(
        ExerciseDefinitionEntity(
          uuid: 'builtin.v1.mine',
          name: 'Mine',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      );
      store.box<ExerciseDefinitionEntity>().put(
        ExerciseDefinitionEntity(
          uuid: 'custom-1',
          name: 'Custom',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      );
      final count = library.syncCatalogDefinitions([
        item('builtin.v1.mine'),
        item('custom-1'),
      ], 1);
      expect(count, 0);
      expect(stored('builtin.v1.mine').primaryMuscles, isEmpty);
      expect(stored('builtin.v1.mine').name, 'Mine');
      expect(stored('custom-1').primaryMuscles, isEmpty);
    });

    test('skips a row whose mode differs and changes no mode', () {
      library.ensureCatalogSeeded();
      final count = library.syncCatalogDefinitions([
        item('builtin.v1.squat', mode: 'duration'),
      ], 2);
      expect(count, 0);
      expect(stored('builtin.v1.squat').inputMode, 'reps_load');
      expect(stored('builtin.v1.squat').primaryMuscles, isEmpty);
      expect(stored('builtin.v1.squat').catalogVersion, 1);
    });

    test('is idempotent', () {
      library.ensureCatalogSeeded();
      final items = [item('builtin.v1.squat'), item('builtin.v1.deadlift')];
      expect(library.syncCatalogDefinitions(items, 1), 2);
      final before = stored('builtin.v1.squat').updatedAtMs;
      expect(library.syncCatalogDefinitions(items, 1), 0);
      expect(stored('builtin.v1.squat').updatedAtMs, before);
    });

    test('invalid muscles update display fields but store empty lists', () {
      library.ensureCatalogSeeded();
      final count = library.syncCatalogDefinitions([
        item('builtin.v1.squat', primary: const ['adductors']),
      ], 2);
      expect(count, 1, reason: 'newer release still refreshes the row');
      expect(stored('builtin.v1.squat').primaryMuscles, isEmpty);
      expect(stored('builtin.v1.squat').secondaryMuscles, isEmpty);
      expect(
        library.syncCatalogDefinitions([
          item('builtin.v1.deadlift', primary: const ['adductors']),
        ], 1),
        0,
        reason: 'same release, nothing valid to fill',
      );
    });

    test('items without muscles never write', () {
      library.ensureCatalogSeeded();
      expect(
        library.syncCatalogDefinitions([
          item('builtin.v1.squat', primary: const [], secondary: const []),
        ], 1),
        0,
      );
    });

    test('a newer release refreshes display fields and muscles', () {
      library.ensureCatalogSeeded();
      library.syncCatalogDefinitions([item('builtin.v1.squat')], 1);
      expect(
        library.syncCatalogDefinitions([
          item(
            'builtin.v1.squat',
            primary: const ['glutes'],
            secondary: const [],
          ),
        ], 2),
        1,
      );
      final row = stored('builtin.v1.squat');
      expect(row.primaryMuscles, ['glutes']);
      expect(row.name, 'Name of builtin.v1.squat');
      expect(row.catalogVersion, 2);
    });
  });

  group('timed plan rows', () {
    PlanExerciseRecord row(String exerciseId, {int? seconds, int? reps}) =>
        PlanExerciseRecord(
          uuid: 'item-a',
          exerciseUuid: exerciseId,
          position: 0,
          targetSets: 3,
          targetRepsMin: reps,
          targetRepsMax: reps,
          targetDurationSeconds: seconds,
        );

    test('a plank row targeting seconds saves', () {
      library.ensureCatalogSeeded();
      final plan = library.savePlan(
        uuid: 'plan-a',
        name: 'Core',
        description: '',
        exercises: [row('builtin.v1.plank', seconds: 45)],
      );
      expect(plan.exercises.single.targetDurationSeconds, 45);
      expect(
        library.getPlan('plan-a')!.exercises.single.targetDurationSeconds,
        45,
      );
    });

    test('a plank row with reps targets throws and writes nothing', () {
      library.ensureCatalogSeeded();
      expect(
        () => library.savePlan(
          uuid: 'plan-a',
          name: 'Core',
          description: '',
          exercises: [row('builtin.v1.plank', reps: 8)],
        ),
        throwsArgumentError,
      );
      expect(library.getPlan('plan-a'), isNull);
    });

    test('a squat row with seconds throws', () {
      library.ensureCatalogSeeded();
      expect(
        () => library.savePlan(
          uuid: 'plan-a',
          name: 'Legs',
          description: '',
          exercises: [row('builtin.v1.squat', seconds: 45)],
        ),
        throwsArgumentError,
      );
      expect(library.getPlan('plan-a'), isNull);
    });
  });

  group('copyCatalogTemplate', () {
    CatalogDefinitionInput def(
      String id, {
      String mode = 'reps_load',
      List<String> primary = const ['chest'],
    }) => (
      id: id,
      name: 'Name of $id',
      muscleGroup: 'Chest',
      equipment: 'Barbell',
      category: 'push_horizontal',
      mode: mode,
      primaryMuscles: primary,
      secondaryMuscles: const ['triceps'],
    );

    TemplateRowInput row(
      String id, {
      String mode = 'reps_load',
      String note = '',
    }) => (
      exercise: def(id, mode: mode),
      sets: 3,
      repsMin: mode == 'duration' ? null : 6,
      repsMax: mode == 'duration' ? null : 8,
      durationSeconds: mode == 'duration' ? 45 : null,
      restSeconds: 90,
      note: note,
    );

    WorkoutPlanRecord copy(
      String request, {
      String name = 'Push day',
      String description = 'Synthetic description.',
      List<TemplateRowInput>? rows,
      int release = 3,
    }) => library.copyCatalogTemplate(
      requestUuid: request,
      name: name,
      description: description,
      rows:
          rows ??
          [
            row('builtin.v1.synthetic-press', note: 'Slow lowering'),
            row('builtin.v1.synthetic-plank', mode: 'duration'),
          ],
      release: release,
    );

    int definitionCount() => store.box<ExerciseDefinitionEntity>().count();
    int rowCount() => store.box<PlanExerciseEntity>().count();

    test('creates a plan with rows, targets and materialized exercises', () {
      final plan = copy('req-1');
      expect(plan.uuid, 'req-1');
      expect(plan.name, 'Push day');
      expect(plan.description, 'Synthetic description.');
      expect(plan.exercises, hasLength(2));
      expect(plan.exercises.map((e) => e.position), [0, 1]);
      expect(plan.exercises.map((e) => e.uuid).toSet(), hasLength(2));
      final a = plan.exercises[0];
      expect(a.exerciseUuid, 'builtin.v1.synthetic-press');
      expect([a.targetSets, a.targetRepsMin, a.targetRepsMax], [3, 6, 8]);
      expect(a.targetDurationSeconds, isNull);
      expect(a.restSeconds, 90);
      expect(a.notes, 'Slow lowering');
      final b = plan.exercises[1];
      expect(b.targetDurationSeconds, 45);
      expect(b.targetRepsMin, isNull);
      expect(library.getPlan('req-1'), isNotNull);
      final press = library.listExercises().firstWhere(
        (e) => e.uuid == 'builtin.v1.synthetic-press',
      );
      expect(press.primaryMuscles, ['chest']);
      expect(press.secondaryMuscles, ['triceps']);
      expect(
        library
            .listExercises()
            .firstWhere((e) => e.uuid == 'builtin.v1.synthetic-plank')
            .inputMode,
        'duration',
      );
    });

    test('the same request returns the same plan without a second one', () {
      final first = copy('req-1');
      final again = copy('req-1');
      expect(again.uuid, first.uuid);
      expect(again.name, 'Push day');
      expect(library.listPlans(), hasLength(1));
      expect(rowCount(), 2);
    });

    test('new requests number the name; archived plans do not count', () {
      expect(copy('req-1').name, 'Push day');
      expect(copy('req-2').name, 'Push day (2)');
      final third = copy('req-3');
      expect(third.name, 'Push day (3)');
      library.archivePlan(
        'req-2',
        expectedUpdatedAtMs: library.getPlan('req-2')!.updatedAtMs,
      );
      expect(copy('req-4').name, 'Push day (2)');
    });

    test('row ids come from the uuid factory and look like UUIDs', () {
      final plan = copy('req-1');
      final uuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
        r'[0-9a-f]{12}$',
      );
      for (final row in plan.exercises) {
        expect(row.uuid, matches(uuid));
      }
      final seeded = ObjectBoxWorkoutLibraryRepository(
        store,
        uuidFactory: _FixedIds(['row-x', 'row-y']),
      );
      final other = seeded.copyCatalogTemplate(
        requestUuid: 'req-2',
        name: 'Other',
        description: '',
        rows: [
          row('builtin.v1.synthetic-press'),
          row('builtin.v1.synthetic-plank', mode: 'duration'),
        ],
        release: 3,
      );
      expect(other.exercises.map((e) => e.uuid), ['row-x', 'row-y']);
    });

    test('a numbered name stays within the plan name limit', () {
      final long = 'n' * 100;
      expect(copy('req-1', name: long).name, long);
      final second = copy('req-2', name: long).name;
      expect(second.length, lessThanOrEqualTo(100));
      expect(second, endsWith(' (2)'));
      expect(second, '${'n' * 96} (2)');
      final third = copy('req-3', name: long).name;
      expect(third, '${'n' * 96} (3)');
    });

    test('a description is cut by characters, not inside a pair', () {
      final plan = copy('req-1', description: '${'x' * 999}😀tail');
      // The limit is 1000 UTF-16 units; the pair would make it 1001.
      expect(plan.description, 'x' * 999);
      final kept = copy('req-2', description: '${'x' * 998}😀tail');
      expect(kept.description, 'x' * 998 + '😀');
    });

    test('a long description is cut to the plan limit', () {
      final plan = copy('req-1', description: 'x' * 1500);
      expect(plan.description, hasLength(1000));
    });

    for (final step in ['exercises', 'plan', 'rows']) {
      test('a failure after "$step" leaves nothing behind', () {
        library.ensureCatalogSeeded();
        library.materializeCatalogExercise(
          id: 'builtin.v1.synthetic-press',
          name: 'Old name',
          muscleGroup: 'Chest',
          equipment: 'Barbell',
          category: 'push_horizontal',
          mode: 'reps_load',
          release: 3,
          primaryMuscles: const ['chest'],
          secondaryMuscles: const [],
        );
        final definitions = definitionCount();
        library.debugCopyHook = (reached) {
          if (reached == step) throw StateError('boom');
        };
        expect(() => copy('req-1'), throwsStateError);
        library.debugCopyHook = null;
        expect(library.getPlan('req-1'), isNull);
        expect(library.listPlans(), isEmpty);
        expect(rowCount(), 0);
        expect(definitionCount(), definitions);
        expect(
          library.listExercises().any(
            (e) => e.uuid == 'builtin.v1.synthetic-plank',
          ),
          isFalse,
        );
        // The existing definition is unchanged.
        expect(
          library
              .listExercises()
              .firstWhere((e) => e.uuid == 'builtin.v1.synthetic-press')
              .name,
          'Old name',
        );
      });
    }

    test('an invalid row writes nothing', () {
      expect(
        () => copy(
          'req-1',
          rows: [
            row('builtin.v1.synthetic-press'),
            (
              exercise: def('builtin.v1.synthetic-plank', mode: 'duration'),
              sets: 3,
              repsMin: 6,
              repsMax: 8,
              durationSeconds: null,
              restSeconds: 60,
              note: '',
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(library.listPlans(), isEmpty);
      expect(definitionCount(), 0);
    });

    test('editing the copy and a newer sync leave the rows unchanged', () {
      final plan = copy('req-1');
      final edited = library.savePlan(
        uuid: plan.uuid,
        name: 'Mine',
        description: plan.description,
        exercises: [plan.exercises.first],
        expectedUpdatedAtMs: plan.updatedAtMs,
      );
      library.syncCatalogDefinitions([
        def('builtin.v1.synthetic-press', primary: const ['triceps']),
      ], 9);
      final after = library.getPlan('req-1')!;
      expect(after.name, 'Mine');
      expect(after.exercises, hasLength(1));
      expect(after.exercises.single.uuid, edited.exercises.single.uuid);
      expect(after.exercises.single.targetRepsMax, 8);
    });
  });
}
