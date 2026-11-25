import 'package:beyondrep/features/progress/muscle_recovery.dart';
import 'package:beyondrep/features/train/plan_fit.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:flutter_test/flutter_test.dart';

ExerciseRecord _ex(String uuid, String group) => ExerciseRecord(
  uuid: uuid,
  name: uuid,
  muscleGroup: group,
  equipment: 'Barbell',
  movementCategory: 'Push',
  inputMode: 'weightReps',
  isBuiltIn: false,
  updatedAtMs: 0,
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

void main() {
  final exercises = {
    'bench': _ex('bench', 'Chest'),
    'curl': _ex('curl', 'arms'),
    'yoga': _ex('yoga', 'Mobility'),
  };
  const recovery = MuscleRecovery({
    Muscle.chest: 0.6,
    Muscle.biceps: 0.1,
    Muscle.triceps: 0.05,
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
