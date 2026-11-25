import 'package:flutter_test/flutter_test.dart';
import 'package:beyondrep/features/progress/muscle_recovery.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';

final _now = DateTime.utc(2026, 11, 24, 12);

/// One exercise of [group] with [count] sets of [reps] at [rpe].
WorkoutSessionRecord _session(
  String id,
  Duration ago,
  String group, {
  int count = 10,
  int? reps = 10,
  int? seconds,
  double? rpe = 8,
  WorkoutStatus status = WorkoutStatus.completed,
  WorkoutSetKind kind = WorkoutSetKind.working,
  WorkoutSetStatus setStatus = WorkoutSetStatus.completed,
}) {
  final at = _now.subtract(ago);
  return WorkoutSessionRecord(
    uuid: id,
    name: id,
    status: status,
    startedAtUtc: at.subtract(const Duration(minutes: 40)),
    completedAtUtc: status == WorkoutStatus.completed ? at : null,
    originalOffsetMinutes: 0,
    revision: 1,
    exercises: [
      WorkoutExerciseRecord(
        uuid: '$id-e',
        sessionUuid: id,
        nameSnapshot: 'Exercise',
        muscleSnapshot: group,
        position: 0,
      ),
    ],
    sets: [
      for (var i = 0; i < count; i++)
        WorkoutSetRecord(
          uuid: '$id-s$i',
          exerciseUuid: '$id-e',
          position: i,
          kind: kind,
          status: setStatus,
          reps: reps,
          durationSeconds: seconds,
          rpe: rpe,
          completedAtUtc: at,
        ),
    ],
  );
}

/// One catalogue-style exercise with [primary] and [secondary] snapshots.
WorkoutSessionRecord _fine(
  String id,
  Duration ago,
  List<String> primary, {
  List<String> secondary = const [],
  int count = 10,
  String group = 'Legs',
  List<WorkoutExerciseRecord> extraExercises = const [],
  List<WorkoutSetRecord> extraSets = const [],
}) {
  final at = _now.subtract(ago);
  return WorkoutSessionRecord(
    uuid: id,
    name: id,
    status: WorkoutStatus.completed,
    startedAtUtc: at.subtract(const Duration(minutes: 40)),
    completedAtUtc: at,
    originalOffsetMinutes: 0,
    revision: 1,
    exercises: [
      WorkoutExerciseRecord(
        uuid: '$id-e',
        sessionUuid: id,
        nameSnapshot: 'Catalogue exercise',
        muscleSnapshot: group,
        position: 0,
        primaryMusclesSnapshot: primary,
        secondaryMusclesSnapshot: secondary,
      ),
      ...extraExercises,
    ],
    sets: [
      for (var i = 0; i < count; i++)
        WorkoutSetRecord(
          uuid: '$id-s$i',
          exerciseUuid: '$id-e',
          position: i,
          kind: WorkoutSetKind.working,
          status: WorkoutSetStatus.completed,
          reps: 10,
          rpe: 8,
          completedAtUtc: at,
        ),
      ...extraSets,
    ],
  );
}

MuscleRecovery _recover(Iterable<WorkoutSessionRecord> s) =>
    MuscleRecovery.fromWorkouts(s, _now);

void main() {
  group('window by group', () {
    test('legs: full now, half at 36 h, gone at 72 h, calves included', () {
      const legs = [
        Muscle.quads,
        Muscle.hamstrings,
        Muscle.glutes,
        Muscle.calves,
      ];
      for (final (hours, expected) in [(0, 1.0), (36, .5), (72, 0.0)]) {
        final r = _recover([_session('l', Duration(hours: hours), 'Legs')]);
        for (final m in legs) {
          expect(r.loadOf(m), closeTo(expected, .001), reason: '$m $hours h');
        }
      }
    });

    test('arms: half at 24 h, gone at 48 h', () {
      expect(
        _recover([_session('a', const Duration(hours: 24), 'Arms')])
            .loadOf(Muscle.biceps),
        closeTo(.5, .001),
      );
      final r = _recover([_session('a', const Duration(hours: 48), 'Arms')]);
      expect(r.loadOf(Muscle.biceps), 0);
      expect(r.groups['Arms'] ?? 0, 0);
    });

    test('shoulders and core use 48 h, chest and back 72 h', () {
      const age = Duration(hours: 48);
      expect(
        _recover([_session('s', age, 'Shoulders')]).loadOf(Muscle.shoulders),
        0,
      );
      expect(_recover([_session('c', age, 'Core')]).loadOf(Muscle.abs), 0);
      expect(
        _recover([_session('c', age, 'Chest')]).loadOf(Muscle.chest),
        closeTo(1 / 3, .001),
      );
      expect(
        _recover([_session('b', age, 'Back')]).loadOf(Muscle.lats),
        closeTo(1 / 3, .001),
      );
    });

    test('custom groups named after a small muscle use 48 h', () {
      for (final name in [
        'Calves',
        'Biceps',
        'Triceps',
        'Forearms',
        'Abs',
        'Obliques',
      ]) {
        final r = _recover([_session('x', const Duration(hours: 48), name)]);
        expect(r.groups[name] ?? 0, 0, reason: name);
      }
    });

    test('other custom groups use 72 h', () {
      final r = _recover([_session('x', const Duration(hours: 36), 'Glutes')]);
      expect(r.loadOf(Muscle.glutes), closeTo(.5, .001));
      final g = _recover([_session('x', const Duration(hours: 36), 'Grip')]);
      expect(g.groups['Grip'], closeTo(.5, .001));
    });
  });

  group('stimulus', () {
    test('4 sets x 10 reps with no RPE is fresh 0.32', () {
      final r = _recover([
        _session('a', Duration.zero, 'Chest', count: 4, rpe: null),
      ]);
      expect(r.loadOf(Muscle.chest), closeTo(.32, .001));
    });

    test('4 sets x 5 reps at RPE 5 is fresh 0.2', () {
      final r = _recover([
        _session('a', Duration.zero, 'Chest', count: 4, reps: 5, rpe: 5),
      ]);
      expect(r.loadOf(Muscle.chest), closeTo(.2, .001));
    });

    test('null reps count as 1.0, zero reps as 0.7', () {
      expect(
        _recover([_session('a', Duration.zero, 'Chest', count: 5, reps: null)])
            .loadOf(Muscle.chest),
        closeTo(.5, .001),
      );
      expect(
        _recover([_session('a', Duration.zero, 'Chest', count: 10, reps: 0)])
            .loadOf(Muscle.chest),
        closeTo(.7, .001),
      );
    });

    test('a timed set counts like a set with no reps at the same RPE', () {
      final timed = _recover([
        _session(
          'a',
          Duration.zero,
          'Chest',
          count: 5,
          reps: null,
          seconds: 45,
        ),
      ]);
      final unknown = _recover([
        _session('a', Duration.zero, 'Chest', count: 5, reps: null),
      ]);
      expect(timed.loadOf(Muscle.chest), closeTo(.5, .001));
      expect(timed.loadOf(Muscle.chest), unknown.loadOf(Muscle.chest));
    });

    test('RPE 6-7.9 weighs 0.75 and reps of 5 or more weigh the same', () {
      expect(
        _recover([_session('a', Duration.zero, 'Chest', count: 4, rpe: 7)])
            .loadOf(Muscle.chest),
        closeTo(.3, .001),
      );
      expect(
        _recover([_session('a', Duration.zero, 'Chest', count: 4, reps: 30)])
            .loadOf(Muscle.chest),
        closeTo(.4, .001),
      );
    });

    test('heavy low-rep work is not counted as light', () {
      final fives = _recover([
        _session('a', Duration.zero, 'Legs', count: 5, reps: 5, rpe: 9),
      ]);
      expect(fives.loadOf(Muscle.quads), closeTo(.5, .001));
      final threes = _recover([
        _session('b', Duration.zero, 'Legs', count: 3, reps: 3, rpe: 9),
      ]);
      expect(threes.loadOf(Muscle.quads), closeTo(.21, .001));
      for (final s in [
        _session(
          'a',
          const Duration(hours: 24),
          'Legs',
          count: 5,
          reps: 5,
          rpe: 9,
        ),
        _session(
          'b',
          const Duration(hours: 24),
          'Legs',
          count: 3,
          reps: 3,
          rpe: 9,
        ),
      ]) {
        expect(
          _recover([s]).loadOf(Muscle.quads),
          greaterThanOrEqualTo(recoveredBelow),
        );
      }
    });

    test('display names share one normalisation', () {
      expect(groupDisplayName('  UPPER chest '), 'Upper chest');
      final r = _recover([
        _session('a', Duration.zero, 'UPPER chest', count: 2),
        _session('b', Duration.zero, 'Upper chest', count: 2),
      ]);
      expect(r.groups.keys, ['Upper chest']);
    });

    test('sessions add up per group, capped at 1', () {
      final r = _recover([
        _session('a', const Duration(hours: 24), 'Legs', count: 6),
        _session('b', Duration.zero, 'Legs', count: 6),
      ]);
      // 0.6 fresh now plus 0.6 * (1 - 24/72) = 0.4 -> 1.0.
      expect(r.loadOf(Muscle.quads), closeTo(1, .001));
      expect(r.groups['Legs'], closeTo(1, .001));
    });
  });

  group('ignored work', () {
    test('warm-up, skipped, in-progress and old sessions', () {
      final r = _recover([
        _session('w', Duration.zero, 'Chest', kind: WorkoutSetKind.warmup),
        _session(
          's',
          Duration.zero,
          'Back',
          setStatus: WorkoutSetStatus.skipped,
        ),
        _session('p', Duration.zero, 'Core', status: WorkoutStatus.paused),
        _session('o', const Duration(hours: 73), 'Legs'),
      ]);
      expect(r.load, isEmpty);
      expect(r.groups, isEmpty);
    });

    test('a custom group is still named in groups', () {
      final r = _recover([_session('g', Duration.zero, 'Grip')]);
      expect(r.load, isEmpty);
      expect(r.groups.keys, ['Grip']);
    });
  });

  test('musclesOf resolves catalog and drawn-muscle names', () {
    expect(MuscleRecovery.musclesOf('Legs'), [
      Muscle.quads,
      Muscle.hamstrings,
      Muscle.glutes,
      Muscle.calves,
    ]);
    expect(MuscleRecovery.musclesOf(' glutes '), [Muscle.glutes]);
    expect(MuscleRecovery.musclesOf('Grip'), isEmpty);
  });
  group('specific muscles', () {
    test(
      'an RDL day loads hamstrings and glutes fully, lower back at half',
      () {
        final r = _recover([
          _fine(
            'rdl',
            Duration.zero,
            ['hamstrings', 'glutes'],
            secondary: ['lowerBack'],
          ),
        ]);
        expect(r.loadOf(Muscle.hamstrings), closeTo(1, .001));
        expect(r.loadOf(Muscle.glutes), closeTo(1, .001));
        expect(r.loadOf(Muscle.lowerBack), closeTo(.5, .001));
        expect(r.loadOf(Muscle.quads), 0);
        expect(r.loadOf(Muscle.calves), 0);
        expect(r.groups['Hamstrings'], closeTo(1, .001));
        expect(r.groups['Lower back'], closeTo(.5, .001));
        expect(r.groups.containsKey('Legs'), isFalse);
      },
    );

    test('a catalogue calf raise fades over 48 h, legacy Legs keeps 72 h', () {
      final calf24 = _recover([
        _fine('c', const Duration(hours: 24), ['calves'], group: 'Legs'),
      ]);
      expect(calf24.loadOf(Muscle.calves), closeTo(.5, .001));
      expect(
        _recover([
          _fine('c', const Duration(hours: 48), ['calves']),
        ]).loadOf(Muscle.calves),
        0,
      );
      expect(
        _recover([_session('l', const Duration(hours: 48), 'Legs')])
            .loadOf(Muscle.calves),
        closeTo(1 / 3, .001),
      );
    });

    test('legacy-only history gives exactly the coarse numbers', () {
      final r = _recover([_session('l', const Duration(hours: 36), 'Legs')]);
      expect(r.loadOf(Muscle.quads), closeTo(.5, .001));
      expect(r.groups, {'Legs': closeTo(.5, .001)});
    });

    test('two exercises add on a shared muscle with no double counting', () {
      final at = _now;
      final r = _recover([
        _fine(
          'a',
          Duration.zero,
          ['hamstrings'],
          count: 3,
          extraExercises: [
            WorkoutExerciseRecord(
              uuid: 'b-e',
              sessionUuid: 'a',
              nameSnapshot: 'Second',
              position: 1,
              primaryMusclesSnapshot: const ['glutes'],
              secondaryMusclesSnapshot: const ['hamstrings'],
            ),
          ],
          extraSets: [
            for (var i = 0; i < 4; i++)
              WorkoutSetRecord(
                uuid: 'b-s$i',
                exerciseUuid: 'b-e',
                position: i,
                kind: WorkoutSetKind.working,
                status: WorkoutSetStatus.completed,
                reps: 10,
                rpe: 8,
                completedAtUtc: at,
              ),
          ],
        ),
      ]);
      // hamstrings: 3 primary + 4 * 0.5 secondary = 5 of 10.
      expect(r.loadOf(Muscle.hamstrings), closeTo(.5, .001));
      expect(r.loadOf(Muscle.glutes), closeTo(.4, .001));
    });

    test(
      'mixed session: a drawn muscle takes the larger of fine and coarse',
      () {
        final custom = WorkoutExerciseRecord(
          uuid: 'm-custom',
          sessionUuid: 'mixed',
          nameSnapshot: 'Sled push',
          muscleSnapshot: 'Legs',
          position: 1,
        );
        final at = _now;
        final r = _recover([
          _fine(
            'mixed',
            Duration.zero,
            ['hamstrings', 'glutes'],
            secondary: ['lowerBack'],
            count: 5,
            extraExercises: [custom],
            extraSets: [
              for (var i = 0; i < 10; i++)
                WorkoutSetRecord(
                  uuid: 'm-s$i',
                  exerciseUuid: 'm-custom',
                  position: i,
                  kind: WorkoutSetKind.working,
                  status: WorkoutSetStatus.completed,
                  reps: 10,
                  rpe: 8,
                  completedAtUtc: at,
                ),
            ],
          ),
        ]);
        // Fine hamstrings 0.5, coarse Legs 1.0: the larger wins, not the sum.
        expect(r.loadOf(Muscle.hamstrings), closeTo(1, .001));
        expect(r.loadOf(Muscle.quads), closeTo(1, .001));
        // Lower back has only the fine half-weight value.
        expect(r.loadOf(Muscle.lowerBack), closeTo(.25, .001));
        expect(r.groups['Legs'], closeTo(1, .001));
        expect(r.groups['Hamstrings'], closeTo(.5, .001));
      },
    );

    test('fine and coarse values never add up for one muscle', () {
      final custom = WorkoutExerciseRecord(
        uuid: 'm-custom',
        sessionUuid: 'mixed',
        nameSnapshot: 'Sled push',
        muscleSnapshot: 'Legs',
        position: 1,
      );
      final r = _recover([
        _fine(
          'mixed',
          Duration.zero,
          ['hamstrings'],
          count: 4,
          extraExercises: [custom],
          extraSets: [
            for (var i = 0; i < 4; i++)
              WorkoutSetRecord(
                uuid: 'm-s$i',
                exerciseUuid: 'm-custom',
                position: i,
                kind: WorkoutSetKind.working,
                status: WorkoutSetStatus.completed,
                reps: 10,
                rpe: 8,
                completedAtUtc: _now,
              ),
          ],
        ),
      ]);
      expect(r.loadOf(Muscle.hamstrings), closeTo(.4, .001));
    });

    test('sessions add up per muscle, capped at 1', () {
      final r = _recover([
        _fine('old', const Duration(hours: 24), ['chest'], count: 10),
        _fine('new', Duration.zero, ['chest'], count: 10),
      ]);
      expect(r.loadOf(Muscle.chest), 1);
    });
  });
}
