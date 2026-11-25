import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/programs/data/objectbox_program_repository.dart';
import 'package:beyondrep/features/programs/domain/program_models.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_library_repository.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:beyondrep/objectbox.g.dart';

class _CountingIds implements UuidFactory {
  var next = 0;
  @override
  String newId() => 'id-${next++}';
}

CatalogDefinitionInput def(String id, {String mode = 'reps_load'}) => (
  id: id,
  name: 'Name of $id',
  muscleGroup: 'Chest',
  equipment: 'Barbell',
  category: 'push_horizontal',
  mode: mode,
  primaryMuscles: const ['chest'],
  secondaryMuscles: const ['triceps'],
);

TemplateRowInput row(String id, {String mode = 'reps_load'}) => (
  exercise: def(id, mode: mode),
  sets: 3,
  repsMin: mode == 'duration' ? null : 6,
  repsMax: mode == 'duration' ? null : 8,
  durationSeconds: mode == 'duration' ? 45 : null,
  restSeconds: 150,
  note: 'Slow',
);

CatalogProgram catalogProgram(String id, List<String?> week) => CatalogProgram(
  id: id,
  name: 'Synthetic split',
  description: 'Synthetic description.',
  goals: const ['general'],
  level: 'beginner',
  daysPerWeek: week.whereType<String>().length,
  estimatedMinutes: 45,
  equipment: const ['barbell'],
  week: week,
);

void main() {
  late Directory directory;
  late Store store;
  late ObjectBoxWorkoutLibraryRepository library;
  late ObjectBoxProgramRepository programs;

  final week = <String?>['tpl.a', 'tpl.b', null, 'tpl.a', null, null, null];
  final today = DateTime(2026, 11, 25);

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-programs-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    library = ObjectBoxWorkoutLibraryRepository(store);
    programs = ObjectBoxProgramRepository(store, uuidFactory: _CountingIds());
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  TrainingProgramRecord import(
    String request, {
    List<String?>? days,
    bool makeActive = false,
    int firstDayWeekday = 3,
    int release = 4,
  }) => programs.importProgram(
    requestUuid: request,
    program: catalogProgram('prog.synthetic', days ?? week),
    templateRows: {
      'tpl.a': [
        row('builtin.v1.synthetic-press'),
        row('builtin.v1.synthetic-plank', mode: 'duration'),
      ],
      'tpl.b': [row('builtin.v1.synthetic-row')],
    },
    templateNames: const {'tpl.a': 'Day A', 'tpl.b': 'Day B'},
    release: release,
    firstDayWeekday: firstDayWeekday,
    makeActive: makeActive,
    localToday: today,
  );

  int count<T>() => store.box<T>().count();

  group('importProgram', () {
    test('one plan per distinct template, shared by two days', () {
      final p = import('prog-1');
      expect(p.uuid, 'prog-1');
      expect(p.days, hasLength(7));
      expect(p.days.map((d) => d.dayIndex), [0, 1, 2, 3, 4, 5, 6]);
      expect(p.days[0].planUuid, isNotNull);
      expect(p.days[0].planUuid, p.days[3].planUuid);
      expect(p.days[1].planUuid, isNot(p.days[0].planUuid));
      expect([
        p.days[2].planUuid,
        p.days[4].planUuid,
        p.days[6].planUuid,
      ], everyElement(isNull));
      expect(count<WorkoutPlanEntity>(), 2);
      expect(count<ProgramDayEntity>(), 7);
      expect(p.sourceId, 'prog.synthetic');
      expect(p.sourceRelease, 4);
      expect(p.firstDayWeekday, 3);
      expect(p.isActive, isFalse);
    });

    test('plan rows carry targets, rest and program ownership', () {
      final p = import('prog-1');
      final plan = library.getPlan(p.days[0].planUuid!)!;
      expect(plan.name, 'Day A');
      expect(plan.programUuid, 'prog-1');
      expect(plan.exercises, hasLength(2));
      final first = plan.exercises[0];
      expect(
        [first.targetSets, first.targetRepsMin, first.targetRepsMax],
        [3, 6, 8],
      );
      expect(first.restSeconds, 150);
      expect(first.notes, 'Slow');
      expect(plan.exercises[1].targetDurationSeconds, 45);
      expect(
        library.listExercises().map((e) => e.uuid),
        containsAll([
          'builtin.v1.synthetic-press',
          'builtin.v1.synthetic-plank',
          'builtin.v1.synthetic-row',
        ]),
      );
    });

    test('replay returns the same program; a new request gets (2)', () {
      final first = import('prog-1');
      final again = import('prog-1');
      expect(again.uuid, first.uuid);
      expect(count<TrainingProgramEntity>(), 1);
      expect(count<WorkoutPlanEntity>(), 2);
      final second = import('prog-2');
      expect(second.name, 'Synthetic split (2)');
      expect(count<TrainingProgramEntity>(), 2);
      expect(count<WorkoutPlanEntity>(), 4);
    });

    for (final step in ['exercises', 'plans', 'rows', 'program', 'days']) {
      test('a failure after "$step" leaves nothing behind', () {
        programs.debugImportHook = (s) {
          if (s == step) throw StateError('boom');
        };
        expect(() => import('prog-1', makeActive: true), throwsStateError);
        expect(count<TrainingProgramEntity>(), 0);
        expect(count<ProgramDayEntity>(), 0);
        expect(count<WorkoutPlanEntity>(), 0);
        expect(count<PlanExerciseEntity>(), 0);
        expect(count<ExerciseDefinitionEntity>(), 0);
        programs.debugImportHook = null;
        expect(import('prog-1').uuid, 'prog-1');
      });
    }

    test('a week naming a template without rows writes nothing', () {
      expect(
        () => import(
          'prog-1',
          days: ['tpl.zzz', null, null, null, null, null, null],
        ),
        throwsArgumentError,
      );
      expect(count<WorkoutPlanEntity>(), 0);
      expect(count<ExerciseDefinitionEntity>(), 0);
    });

    test('makeActive sets the activation date', () {
      final p = import('prog-1', makeActive: true);
      expect(p.isActive, isTrue);
      expect(p.activatedLocalDate, '2026-11-25');
      expect(programs.activeProgram()?.uuid, 'prog-1');
    });
  });

  group('activation', () {
    test('activating B deactivates A in the same call', () {
      import('a', makeActive: true);
      import('b', makeActive: true);
      expect(programs.activeProgram()?.uuid, 'b');
      expect(
        store.box<TrainingProgramEntity>().getAll().where((p) => p.isActive),
        hasLength(1),
      );
      programs.setActive('a', true, DateTime(2026, 11, 27));
      final active = programs.activeProgram()!;
      expect(active.uuid, 'a');
      expect(active.activatedLocalDate, '2026-11-27');
      programs.setActive('a', false, today);
      expect(programs.activeProgram(), isNull);
    });

    test('an archived program cannot be activated', () {
      import('a');
      programs.archiveProgram('a', 5);
      expect(() => programs.setActive('a', true, today), throwsStateError);
    });
  });

  group('schedule edits', () {
    test('setFirstWeekday validates and saves', () {
      import('a');
      programs.setFirstWeekday('a', 6);
      expect(programs.getProgram('a')!.firstDayWeekday, 6);
      expect(() => programs.setFirstWeekday('a', 8), throwsArgumentError);
      expect(() => programs.setFirstWeekday('a', 0), throwsArgumentError);
    });

    test('setDayPlan moves a workout, sets rest, rejects a foreign plan', () {
      final p = import('a');
      final planB = p.days[1].planUuid!;
      programs.setDayPlan('a', 2, planB);
      programs.setDayPlan('a', 0, null);
      final changed = programs.getProgram('a')!;
      expect(changed.days[2].planUuid, planB);
      expect(changed.days[0].planUuid, isNull);
      library.savePlan(
        uuid: 'own',
        name: 'Mine',
        description: '',
        exercises: const [],
      );
      expect(() => programs.setDayPlan('a', 4, 'own'), throwsArgumentError);
      expect(() => programs.setDayPlan('a', 7, planB), throwsArgumentError);
      expect(programs.getProgram('a')!.days[4].planUuid, isNull);
    });

    test('programPlans lists the program plans even when no day uses them', () {
      final p = import('a');
      final planB = p.days[1].planUuid!;
      programs.setDayPlan('a', 1, null);
      final plans = programs.programPlans('a');
      expect(plans.map((e) => e.name), ['Day A', 'Day B']);
      expect(plans.map((e) => e.uuid), contains(planB));
      programs.setDayPlan('a', 1, planB);
      expect(programs.getProgram('a')!.days[1].planUuid, planB);
      import('b');
      expect(programs.programPlans('a'), hasLength(2));
      programs.archiveProgram('a', 5);
      expect(programs.programPlans('a'), isEmpty);
    });

    test('a week with no training day is allowed', () {
      final p = import(
        'a',
        days: ['tpl.a', null, null, null, null, null, null],
      );
      programs.setDayPlan('a', 0, null);
      expect(
        programs.getProgram(p.uuid)!.days.every((d) => d.planUuid == null),
        isTrue,
      );
    });
  });

  group('archive', () {
    test('archives program and plans, leaves sessions alone', () {
      final p = import('a', makeActive: true);
      store.box<WorkoutSessionEntity>().put(
        WorkoutSessionEntity(
          uuid: 's1',
          name: 'Day A',
          planUuid: p.days[0].planUuid,
          startedAtMs: 1,
          originalOffsetMinutes: 0,
          updatedAtMs: 1,
          programUuid: 'a',
          programDayLocalDate: '2026-11-25',
        ),
      );
      programs.archiveProgram('a', 99);
      final archived = store.box<TrainingProgramEntity>().getAll().single;
      expect(archived.archivedAtMs, 99);
      expect(archived.isActive, isFalse);
      expect(
        store.box<WorkoutPlanEntity>().getAll().map((e) => e.archivedAtMs),
        everyElement(99),
      );
      final session = store.box<WorkoutSessionEntity>().getAll().single;
      expect(session.programUuid, 'a');
      expect(session.programDayLocalDate, '2026-11-25');
      expect(session.status, 'inProgress');
      expect(programs.activeProgram(), isNull);
    });

    test('watchPrograms excludes archived programs', () async {
      import('a');
      import('b');
      programs.archiveProgram('a', 1);
      final list = await programs.watchPrograms().first;
      expect(list.map((p) => p.uuid), ['b']);
    });
  });

  group('plans', () {
    test('Your plans excludes program plans; editing keeps programUuid', () {
      final p = import('a');
      library.savePlan(
        uuid: 'own',
        name: 'Mine',
        description: '',
        exercises: const [],
      );
      expect(library.listPlans().map((e) => e.uuid), ['own']);
      final plan = library.getPlan(p.days[0].planUuid!)!;
      final saved = library.savePlan(
        uuid: plan.uuid,
        name: 'Renamed',
        description: plan.description,
        exercises: plan.exercises,
        expectedUpdatedAtMs: plan.updatedAtMs,
      );
      expect(saved.programUuid, 'a');
      expect(library.getPlan(plan.uuid)!.programUuid, 'a');
      expect(library.listPlans().map((e) => e.uuid), ['own']);
    });

    test('a catalogue sync to a newer release leaves imported plans', () {
      final p = import('a');
      final before = library.getPlan(p.days[0].planUuid!)!;
      library.syncCatalogDefinitions([def('builtin.v1.synthetic-press')], 5);
      final after = library.getPlan(before.uuid)!;
      expect(after.updatedAtMs, before.updatedAtMs);
      expect(
        after.exercises.map(
          (e) => [e.targetSets, e.targetRepsMax, e.restSeconds],
        ),
        before.exercises.map(
          (e) => [e.targetSets, e.targetRepsMax, e.restSeconds],
        ),
      );
      expect(count<TrainingProgramEntity>(), 1);
    });
  });
}
