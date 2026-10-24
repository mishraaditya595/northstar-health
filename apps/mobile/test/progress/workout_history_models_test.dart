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
  String definition = 'builtin.v1.bench-press',
}) => WorkoutSessionRecord(
  uuid: id,
  name: name,
  status: status,
  startedAtUtc: DateTime.utc(2026, 10, 24, 7),
  completedAtUtc: status == WorkoutStatus.completed
      ? DateTime.utc(2026, 10, 24, 8)
      : null,
  originalOffsetMinutes: 330,
  revision: 4,
  exercises: [
    WorkoutExerciseRecord(
      uuid: 'exercise-$id',
      sessionUuid: id,
      definitionUuid: definition,
      nameSnapshot: 'Bench press',
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
}
