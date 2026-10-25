import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/features/progress/domain/workout_history_models.dart';
import 'package:northstar_health/features/train/previous_sets.dart';
import 'package:northstar_health/features/workouts/domain/workout_models.dart';

WorkoutSessionRecord session(
  String id,
  DateTime finished, {
  String definition = 'bench',
  List<(int, WorkoutSetStatus, int?)> sets = const [],
}) => WorkoutSessionRecord(
  uuid: id,
  name: id,
  status: WorkoutStatus.completed,
  startedAtUtc: finished.subtract(const Duration(hours: 1)),
  completedAtUtc: finished,
  originalOffsetMinutes: 0,
  revision: 3,
  exercises: [
    WorkoutExerciseRecord(
      uuid: 'ex-$id',
      sessionUuid: id,
      definitionUuid: definition,
      nameSnapshot: 'Bench',
      position: 0,
    ),
  ],
  sets: [
    for (final (position, status, grams) in sets)
      WorkoutSetRecord(
        uuid: '$id-$position',
        exerciseUuid: 'ex-$id',
        position: position,
        kind: WorkoutSetKind.working,
        status: status,
        reps: status == WorkoutSetStatus.completed ? 8 : null,
        loadGrams: grams,
      ),
  ],
);

void main() {
  final older = DateTime.utc(2026, 10, 1);
  final newer = DateTime.utc(2026, 10, 8);

  test('uses the most recent completed session of the same exercise', () {
    final snapshot = WorkoutHistorySnapshot(
      sessions: [
        session('old', older, sets: [(0, WorkoutSetStatus.completed, 40000)]),
        session(
          'new',
          newer,
          sets: [
            (1, WorkoutSetStatus.completed, 52000),
            (0, WorkoutSetStatus.completed, 50000),
          ],
        ),
      ],
    );
    final previous = previousSetsFor(snapshot, 'bench');
    expect(previous.map((s) => s.loadGrams), [50000, 52000]);
  });

  test('ignores other exercises and sets that were not completed', () {
    final snapshot = WorkoutHistorySnapshot(
      sessions: [
        session(
          'squat-day',
          newer,
          definition: 'squat',
          sets: [(0, WorkoutSetStatus.completed, 90000)],
        ),
        session(
          'bench-day',
          older,
          sets: [
            (0, WorkoutSetStatus.completed, 50000),
            (1, WorkoutSetStatus.skipped, null),
            (2, WorkoutSetStatus.planned, null),
          ],
        ),
      ],
    );
    expect(previousSetsFor(snapshot, 'bench').map((s) => s.loadGrams), [50000]);
    expect(previousSetsFor(snapshot, 'deadlift'), isEmpty);
    expect(previousSetsFor(snapshot, null), isEmpty);
  });
}
