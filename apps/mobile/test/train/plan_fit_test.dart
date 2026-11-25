import 'package:beyondrep/features/progress/muscle_recovery.dart';
import 'package:beyondrep/features/train/plan_fit.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:flutter_test/flutter_test.dart';

ExerciseRecord _ex(
  String uuid,
  String group, {
  List<String> primary = const [],
  List<String> secondary = const [],
}) => ExerciseRecord(
  uuid: uuid,
  name: uuid,
  muscleGroup: group,
  equipment: 'Barbell',
  movementCategory: 'Push',
  inputMode: 'weightReps',
  isBuiltIn: false,
  updatedAtMs: 0,
  primaryMuscles: primary,
  secondaryMuscles: secondary,
);

WorkoutPlanRecord _plan(String uuid, Map<String, int> sets) =>
    WorkoutPlanRecord(
      uuid: uuid,
      name: uuid,
      description: '',
      updatedAtMs: 0,
      exercises: [
        for (final (i, e) in sets.entries.indexed)
          PlanExerciseRecord(
            uuid: '$uuid-$i',
            exerciseUuid: e.key,
            position: i,
            targetSets: e.value,
          ),
      ],
    );

PlanRecovery _pr(
  String id, {
  Set<String> groups = const {},
  Set<String> recovering = const {},
  double worst = 0,
  int sets = 10,
}) => PlanRecovery(
  planUuid: id,
  groups: groups,
  recovering: recovering,
  worstLoad: worst,
  totalSets: sets,
);

/// Three working sets of ten, no RPE, finished at [at] on a Legs exercise.
WorkoutSessionRecord _lightLegs(DateTime at) => WorkoutSessionRecord(
  uuid: 'light',
  name: 'Light',
  status: WorkoutStatus.completed,
  startedAtUtc: at.subtract(const Duration(minutes: 30)),
  completedAtUtc: at,
  originalOffsetMinutes: 0,
  revision: 1,
  exercises: [
    WorkoutExerciseRecord(
      uuid: 'e',
      sessionUuid: 'light',
      nameSnapshot: 'Squat',
      muscleSnapshot: 'Legs',
      position: 0,
    ),
  ],
  sets: [
    for (var i = 0; i < 3; i++)
      WorkoutSetRecord(
        uuid: 's$i',
        exerciseUuid: 'e',
        position: i,
        kind: WorkoutSetKind.working,
        status: WorkoutSetStatus.completed,
        reps: 10,
        completedAtUtc: at,
      ),
  ],
);

void main() {
  final exercises = {
    'bench': _ex('bench', 'Chest'),
    'curl': _ex('curl', 'arms'),
    'yoga': _ex('yoga', 'Mobility'),
    'squat': _ex('squat', 'Legs'),
  };
  const recovery = MuscleRecovery({
    Muscle.chest: 0.6,
    Muscle.biceps: 0.09,
    Muscle.triceps: 0.05,
  });

  group('specific muscles', () {
    final done = DateTime.utc(2026, 11, 24, 12);
    // An RDL day: hamstrings and glutes primary, lower back secondary.
    WorkoutSessionRecord rdlDay() => WorkoutSessionRecord(
      uuid: 'rdl',
      name: 'RDL',
      status: WorkoutStatus.completed,
      startedAtUtc: done.subtract(const Duration(minutes: 30)),
      completedAtUtc: done,
      originalOffsetMinutes: 0,
      revision: 1,
      exercises: [
        WorkoutExerciseRecord(
          uuid: 'e',
          sessionUuid: 'rdl',
          nameSnapshot: 'Romanian deadlift',
          muscleSnapshot: 'Legs',
          position: 0,
          primaryMusclesSnapshot: const ['hamstrings', 'glutes'],
          secondaryMusclesSnapshot: const ['lowerBack'],
        ),
      ],
      sets: [
        for (var i = 0; i < 10; i++)
          WorkoutSetRecord(
            uuid: 's$i',
            exerciseUuid: 'e',
            position: i,
            kind: WorkoutSetKind.working,
            status: WorkoutSetStatus.completed,
            reps: 10,
            rpe: 8,
            completedAtUtc: done,
          ),
      ],
    );

    final fine = {
      'rdl': _ex(
        'rdl',
        'Legs',
        primary: ['hamstrings', 'glutes'],
        secondary: ['lowerBack'],
      ),
      'bench': _ex(
        'bench',
        'Chest',
        primary: ['chest'],
        secondary: ['triceps', 'shoulders'],
      ),
      'legacy': _ex('legacy', 'Legs'),
      'row': _ex('row', 'Back', primary: ['lats'], secondary: ['biceps']),
    };

    test('a plan of backfilled built-ins names Hamstrings and Glutes', () {
      final recovery = MuscleRecovery.fromWorkouts([rdlDay()], done);
      final r = planRecoveryOf(
        _plan('p', {'rdl': 3, 'bench': 3}),
        fine,
        recovery,
      )!;
      expect(r.groups, {'Hamstrings', 'Glutes', 'Chest'});
      expect(r.recovering, {'Hamstrings', 'Glutes'});
      expect(r.recovering, isNot(contains('Legs')));
      expect(r.recovering, isNot(contains('Chest')));
    });

    test('secondary muscles are ignored for recovering', () {
      final recovery = MuscleRecovery.fromWorkouts([rdlDay()], done);
      // Back is primary lats, secondary biceps; lower back is loaded but is
      // only a secondary muscle of the RDL, so a lats plan stays recovered.
      final r = planRecoveryOf(_plan('p', {'row': 3}), fine, recovery)!;
      expect(r.groups, {'Lats'});
      expect(r.isRecovered, isTrue);
      final bodyRecovery = const MuscleRecovery({Muscle.biceps: 1});
      expect(
        planRecoveryOf(_plan('p', {'row': 3}), fine, bodyRecovery)!.isRecovered,
        isTrue,
      );
    });

    test('a legacy custom Legs exercise still reports Legs', () {
      final recovery = MuscleRecovery.fromWorkouts([rdlDay()], done);
      final r = planRecoveryOf(_plan('p', {'legacy': 3}), fine, recovery)!;
      expect(r.groups, {'Legs'});
      expect(r.recovering, {'Legs'});
    });

    test('suggestion works with muscle names and when nothing recovers', () {
      final recovery = MuscleRecovery.fromWorkouts([rdlDay()], done);
      final rdlPlan = planRecoveryOf(
        _plan('rdl-day', {'rdl': 3}),
        fine,
        recovery,
      )!;
      final pushPlan = planRecoveryOf(
        _plan('push-day', {'bench': 3}),
        fine,
        recovery,
      )!;
      final suggestion = suggestPlan([rdlPlan, pushPlan], lowReadiness: false);
      expect(suggestion, isA<SuggestRecovered>());
      expect(suggestion!.plan.planUuid, 'push-day');
      expect((suggestion as SuggestRecovered).restedGroups, {
        'Hamstrings',
        'Glutes',
      });

      final rested = MuscleRecovery.fromWorkouts([
        rdlDay(),
      ], done.add(const Duration(hours: 80)));
      final a = planRecoveryOf(_plan('a', {'rdl': 3}), fine, rested)!;
      final b = planRecoveryOf(_plan('b', {'bench': 3}), fine, rested)!;
      expect(suggestPlan([a, b], lowReadiness: false), isNull);
    });
  });

  group('planRecoveryOf', () {
    test('chest and arms plan', () {
      final r = planRecoveryOf(
        _plan('p', {'bench': 3, 'curl': 4, 'yoga': 2, 'gone': 5}),
        exercises,
        recovery,
      )!;
      expect(r.groups, {'Chest', 'Arms'});
      expect(r.recovering, {'Chest'});
      expect(r.worstLoad, 0.6);
      expect(r.totalSets, 14);
      expect(r.isRecovered, isFalse);
    });

    test(
      'a light session is recovering when just finished, recovered at 48 h',
      () {
        final done = DateTime.utc(2026, 11, 24, 12);
        final plan = _plan('p', {'squat': 3});
        PlanRecovery at(Duration later) => planRecoveryOf(
          plan,
          exercises,
          MuscleRecovery.fromWorkouts([_lightLegs(done)], done.add(later)),
        )!;
        expect(at(Duration.zero).recovering, {'Legs'});
        expect(at(Duration.zero).isRecovered, isFalse);
        expect(at(const Duration(hours: 48)).isRecovered, isTrue);
      },
    );

    test('group names are normalised so case variants merge', () {
      final r = planRecoveryOf(_plan('p', {'a': 2, 'b': 2}), {
        'a': _ex('a', 'GLUTES'),
        'b': _ex('b', ' glutes '),
      }, const MuscleRecovery({Muscle.glutes: 0.5}))!;
      expect(r.groups, {'Glutes'});
      expect(r.recovering, {'Glutes'});
    });

    test('unmapped-only, empty and missing exercises give null', () {
      expect(
        planRecoveryOf(_plan('p', {'yoga': 3}), exercises, recovery),
        isNull,
      );
      expect(planRecoveryOf(_plan('p', {}), exercises, recovery), isNull);
      expect(
        planRecoveryOf(_plan('p', {'gone': 3}), exercises, recovery),
        isNull,
      );
    });
  });

  group('suggestPlan normal readiness', () {
    final fresh = _pr('a', groups: {'Arms'}, worst: 0.05);
    final tired = _pr(
      'b',
      groups: {'Chest', 'Arms'},
      recovering: {'Chest'},
      worst: 0.6,
    );

    test('clear recovered winner names rested groups', () {
      final s = suggestPlan([tired, fresh], lowReadiness: false);
      expect(s, isA<SuggestRecovered>());
      expect(s!.plan.planUuid, 'a');
      expect((s as SuggestRecovered).restedGroups, {'Chest'});
    });

    test('rested groups exclude the chosen plan groups', () {
      final other = _pr(
        'c',
        groups: {'Arms', 'Legs'},
        recovering: {'Arms', 'Legs'},
        worst: 0.7,
      );
      final s =
          suggestPlan([other, fresh], lowReadiness: false) as SuggestRecovered;
      expect(s.restedGroups, {'Legs'});
    });

    test('tie within 0.2 gives null', () {
      final close = _pr('c', groups: {'Legs'}, worst: 0.2);
      expect(suggestPlan([fresh, close], lowReadiness: false), isNull);
    });

    test('best not recovered gives null', () {
      final a = _pr('a', recovering: {'Chest'}, worst: 0.3);
      final b = _pr('b', recovering: {'Legs'}, worst: 0.9);
      expect(suggestPlan([a, b], lowReadiness: false), isNull);
    });

    test('single plan and empty list give null', () {
      expect(suggestPlan([fresh], lowReadiness: false), isNull);
      expect(suggestPlan([], lowReadiness: false), isNull);
      expect(suggestPlan([], lowReadiness: true), isNull);
    });
  });

  group('suggestPlan low readiness', () {
    test('fewest sets among recovered, ties earlier', () {
      final heavy = _pr('a', sets: 20);
      final light = _pr('b', sets: 8);
      final light2 = _pr('c', sets: 8);
      final tiredLightest = _pr('d', recovering: {'Chest'}, sets: 2);
      final s = suggestPlan([
        heavy,
        tiredLightest,
        light,
        light2,
      ], lowReadiness: true);
      expect(s, isA<SuggestLightest>());
      expect(s!.plan.planUuid, 'b');
    });

    test('no recovered plan gives null', () {
      expect(
        suggestPlan([
          _pr('a', recovering: {'Chest'}),
        ], lowReadiness: true),
        isNull,
      );
    });
  });
}
