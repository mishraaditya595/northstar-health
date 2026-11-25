import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../workouts/domain/workout_library_models.dart';
import '../workouts/domain/workout_models.dart';

/// Whether [exercise] is logged in seconds. The definition decides; a
/// definition missing on this device (a restored workout) falls back to what
/// its sets already hold.
bool isTimedExercise(
  WorkoutExerciseRecord exercise,
  List<WorkoutSetRecord> sets,
  Map<String, ExerciseRecord> definitions,
) {
  final definition = definitions[exercise.definitionUuid];
  if (definition != null) return definition.inputMode == 'duration';
  return sets.any((s) => s.durationSeconds != null);
}

/// Wall-clock source for the set stopwatch. Tests replace it because
/// `tester.pump` advances timers but not `DateTime.now`.
final timedSetClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
