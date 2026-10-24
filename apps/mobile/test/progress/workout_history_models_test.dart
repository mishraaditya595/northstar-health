import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/units/load_units.dart';
import 'package:northstar_health/features/progress/domain/workout_history_models.dart';
import 'package:northstar_health/features/workouts/domain/workout_models.dart';

WorkoutSetRecord set({
  required String id,
  required String exercise,
  required WorkoutSetStatus status,
  required WorkoutSetKind kind,
  int? reps,
  int? grams,
}) => WorkoutSetRecord(
  uuid: id,
  exerciseUuid: exercise,
  position: 0,
  status: status,
  kind: kind,
  reps: reps,
  loadGrams: grams,
  inputUnit: LoadUnit.kg,
  completedAtUtc: status == WorkoutSetStatus.completed
      ? DateTime.utc(2026, 10, 24, 8)
      : null,
);

WorkoutSessionRecord workout({
  required String id,
  required WorkoutStatus status,
  required List<WorkoutSetRecord> sets,
  String name = 'Training',
  String? definition = 'builtin.v1.bench-press',
  String exerciseName = 'Bench press',
  String equipment = 'Barbell',
  DateTime? completedAt,
}) => WorkoutSessionRecord(
  uuid: id,
  name: name,
  status: status,
  startedAtUtc: DateTime.utc(2026, 10, 24, 7),
  completedAtUtc: status == WorkoutStatus.completed
      ? (completedAt ?? DateTime.utc(2026, 10, 24, 8))
      : null,
  originalOffsetMinutes: 330,
  revision: 4,
  exercises: [
    WorkoutExerciseRecord(
      uuid: 'exercise-$id',
      sessionUuid: id,
      definitionUuid: definition,
      nameSnapshot: exerciseName,
      equipmentSnapshot: equipment,
      position: 0,
    ),
  ],
  sets: sets,
);

void main() {
  test('only completed workouts and performed working sets count', () {
    final actual = workout(
      id: 'a',
      status: WorkoutStatus.completed,
      sets: [
        set(
          id: 'loaded',
          exercise: 'exercise-a',
          status: WorkoutSetStatus.completed,
          kind: WorkoutSetKind.working,
          reps: 8,
          grams: 100000,
        ),
        set(
          id: 'warm-up',
          exercise: 'exercise-a',
          status: WorkoutSetStatus.completed,
          kind: WorkoutSetKind.warmup,
          reps: 20,
          grams: 25000,
        ),
        set(
          id: 'bodyweight',
          exercise: 'exercise-a',
          status: WorkoutSetStatus.completed,
          kind: WorkoutSetKind.working,
          reps: 12,
        ),
        set(
          id: 'not-done',
          exercise: 'exercise-a',
          status: WorkoutSetStatus.planned,
          kind: WorkoutSetKind.working,
        ),
        set(
          id: 'skipped',
          exercise: 'exercise-a',
          status: WorkoutSetStatus.skipped,
          kind: WorkoutSetKind.working,
        ),
      ],
    );
    final ignored = [
      workout(
        id: 'b',
        status: WorkoutStatus.inProgress,
        sets: [
          set(
            id: 'live',
            exercise: 'exercise-b',
            status: WorkoutSetStatus.completed,
            kind: WorkoutSetKind.working,
            reps: 100,
            grams: 999000,
          ),
        ],
      ),
      workout(id: 'c', status: WorkoutStatus.discarded, sets: []),
      workout(id: 'd', status: WorkoutStatus.unknown, sets: []),
    ];
    final summary = calculateWorkoutHistory([actual, ...ignored]);
    expect(summary.completedWorkouts, 1);
    expect(summary.completedWorkingSets, 2);
    expect(summary.loadedWorkingSets, 1);
    expect(summary.unloadedWorkingSets, 1);
    expect(summary.loadedVolumeGramReps, 800000);
    expect(summary.exerciseTrends.single.bestLoadGrams, 100000);
    expect(summary.exerciseTrends.single.points.single.reps, 8);
  });

  test('best loaded set is selected per finished workout and ordered', () {
    final s1 = workout(
      id: 'a',
      status: WorkoutStatus.completed,
      sets: [
        set(
          id: 'one',
          exercise: 'exercise-a',
          status: WorkoutSetStatus.completed,
          kind: WorkoutSetKind.working,
          reps: 8,
          grams: 80000,
        ),
        set(
          id: 'two',
          exercise: 'exercise-a',
          status: WorkoutSetStatus.completed,
          kind: WorkoutSetKind.working,
          reps: 5,
          grams: 100000,
        ),
      ],
    );
    final s2 = workout(
      id: 'b',
      status: WorkoutStatus.completed,
      sets: [
        set(
          id: 'three',
          exercise: 'exercise-b',
          status: WorkoutSetStatus.completed,
          kind: WorkoutSetKind.working,
          reps: 3,
          grams: 90000,
        ),
      ],
    );
    final summary = calculateWorkoutHistory([s2, s1]);
    final trend = summary.exerciseTrends.single;
    expect(trend.key, 'definition:builtin.v1.bench-press');
    expect(trend.bestLoadGrams, 100000);
    expect(trend.points, hasLength(2));
    expect(trend.points.map((p) => p.grams), [100000, 90000]);
    expect(summary.loadedVolumeGramReps, 8 * 80000 + 5 * 100000 + 3 * 90000);
  });

  test('null loads never become fabricated zeros in exercise trends', () {
    final summary = calculateWorkoutHistory([
      workout(
        id: 'empty',
        status: WorkoutStatus.completed,
        sets: [
          set(
            id: 'body',
            exercise: 'exercise-empty',
            status: WorkoutSetStatus.completed,
            kind: WorkoutSetKind.working,
            reps: 5,
          ),
        ],
      ),
    ]);
    expect(summary.exerciseTrends, isEmpty);
    expect(summary.unloadedWorkingSets, 1);
    expect(summary.loadedVolumeGramReps, 0);
  });

  test(
    'session display day uses original recorded offset, not device timezone',
    () {
      final s = WorkoutSessionRecord(
        uuid: 'timezone',
        name: 'Night training',
        status: WorkoutStatus.completed,
        startedAtUtc: DateTime.utc(2026, 10, 23, 21, 30),
        completedAtUtc: DateTime.utc(2026, 10, 23, 22, 20),
        originalOffsetMinutes: 330,
        revision: 2,
      );
      expect(originalLocalDay(s), DateTime.utc(2026, 10, 24));
    },
  );

  test('zero load is not a loaded lift or a best-lift claim', () {
    final summary = calculateWorkoutHistory([
      workout(
        id: 'zero',
        status: WorkoutStatus.completed,
        sets: [
          set(
            id: 'zero-load',
            exercise: 'exercise-zero',
            status: WorkoutSetStatus.completed,
            kind: WorkoutSetKind.working,
            reps: 10,
            grams: 0,
          ),
        ],
      ),
    ]);
    expect(summary.completedWorkingSets, 1);
    expect(summary.zeroLoadWorkingSets, 1);
    expect(summary.loadedWorkingSets, 0);
    expect(summary.exerciseTrends, isEmpty);
  });

  test('renamed known exercises use most recent saved name', () {
    final old = workout(
      id: 'old',
      status: WorkoutStatus.completed,
      exerciseName: 'Old label',
      completedAt: DateTime.utc(2026, 8, 1),
      sets: [
        set(
          id: 'a',
          exercise: 'exercise-old',
          status: WorkoutSetStatus.completed,
          kind: WorkoutSetKind.working,
          reps: 4,
          grams: 50000,
        ),
      ],
    );
    final newer = workout(
      id: 'new',
      status: WorkoutStatus.completed,
      exerciseName: 'Renamed label',
      completedAt: DateTime.utc(2026, 10, 1),
      sets: [
        set(
          id: 'b',
          exercise: 'exercise-new',
          status: WorkoutSetStatus.completed,
          kind: WorkoutSetKind.working,
          reps: 4,
          grams: 65000,
        ),
      ],
    );
    final result = calculateWorkoutHistory([newer, old]);
    expect(result.exerciseTrends, hasLength(1));
    expect(result.exerciseTrends.single.name, 'Renamed label');
  });

  test('legacy snapshot merges only with unambiguous matching definition', () {
    final recognized = workout(
      id: 'known',
      status: WorkoutStatus.completed,
      sets: [
        set(
          id: 'k',
          exercise: 'exercise-known',
          status: WorkoutSetStatus.completed,
          kind: WorkoutSetKind.working,
          reps: 5,
          grams: 40000,
        ),
      ],
    );
    final legacy = workout(
      id: 'legacy',
      status: WorkoutStatus.completed,
      definition: null,
      sets: [
        set(
          id: 'l',
          exercise: 'exercise-legacy',
          status: WorkoutSetStatus.completed,
          kind: WorkoutSetKind.working,
          reps: 6,
          grams: 45000,
        ),
      ],
    );
    final dumbbell = workout(
      id: 'dumbbell',
      status: WorkoutStatus.completed,
      definition: null,
      equipment: 'Dumbbell',
      sets: [
        set(
          id: 'd',
          exercise: 'exercise-dumbbell',
          status: WorkoutSetStatus.completed,
          kind: WorkoutSetKind.working,
          reps: 8,
          grams: 30000,
        ),
      ],
    );
    final result = calculateWorkoutHistory([legacy, dumbbell, recognized]);
    expect(result.exerciseTrends, hasLength(2));
    expect(result.exerciseTrends.map((e) => e.points.length).toList()..sort(), [
      1,
      2,
    ]);
  });

  test('working set count ignores malformed records with missing reps', () {
    final session = workout(
      id: 'incomplete',
      status: WorkoutStatus.completed,
      sets: [
        set(
          id: 'missing-reps',
          exercise: 'exercise-incomplete',
          status: WorkoutSetStatus.completed,
          kind: WorkoutSetKind.working,
          grams: 25000,
        ),
      ],
    );
    expect(countWorkingSets(session), 0);
    expect(calculateWorkoutHistory([session]).completedWorkingSets, 0);
  });

  test('trend date matches session finish across local midnight', () {
    // The top set may be logged before midnight, but the chart represents
    // the completed workout and must agree with its history-list date.
    final session = workout(
      id: 'midnight',
      status: WorkoutStatus.completed,
      completedAt: DateTime.utc(2026, 10, 24, 19),
      sets: [
        set(
          id: 'midnight-set',
          exercise: 'exercise-midnight',
          status: WorkoutSetStatus.completed,
          kind: WorkoutSetKind.working,
          reps: 6,
          grams: 50000,
        ),
      ],
    );
    final trend = calculateWorkoutHistory([session]).exerciseTrends.single;
    expect(originalLocalDay(session), DateTime.utc(2026, 10, 25));
    expect(trend.points.single.originalLocalDay, originalLocalDay(session));
    expect(trend.points.single.performedAtUtc, session.completedAtUtc);
    expect(trend.points.single.reps, 6);
  });

  test('rolling 30 and 90 day periods include exact cutoff UTC', () {
    final now = DateTime.utc(2026, 10, 24, 12);
    final sessions = [
      workout(
        id: 'edge',
        status: WorkoutStatus.completed,
        completedAt: now.subtract(const Duration(days: 30)),
        sets: [],
      ),
      workout(
        id: 'older',
        status: WorkoutStatus.completed,
        completedAt: now.subtract(const Duration(days: 31)),
        sets: [],
      ),
      workout(
        id: 'outside',
        status: WorkoutStatus.completed,
        completedAt: now.subtract(const Duration(days: 91)),
        sets: [],
      ),
    ];
    final history = WorkoutHistorySnapshot(sessions: sessions);
    expect(
      workoutsInPeriod(
        history,
        WorkoutHistoryPeriod.last30Days,
        now,
      ).map((s) => s.uuid),
      ['edge'],
    );
    expect(
      workoutsInPeriod(
        history,
        WorkoutHistoryPeriod.last90Days,
        now,
      ).map((s) => s.uuid),
      ['edge', 'older'],
    );
    expect(
      workoutsInPeriod(history, WorkoutHistoryPeriod.all, now),
      hasLength(3),
    );
  });
}
