import 'workout_models.dart';

/// Persisted names are a versioned disk contract. Never parse with byName:
/// future/unsupported values must be preserved as unknown, not make a read fail.
WorkoutStatus workoutStatusFromStorage(String name) => switch (name) {
  'inProgress' => WorkoutStatus.inProgress,
  'paused' => WorkoutStatus.paused,
  'completed' => WorkoutStatus.completed,
  'discarded' => WorkoutStatus.discarded,
  _ => WorkoutStatus.unknown,
};

WorkoutSetStatus workoutSetStatusFromStorage(String name) => switch (name) {
  'planned' => WorkoutSetStatus.planned,
  'completed' => WorkoutSetStatus.completed,
  'skipped' => WorkoutSetStatus.skipped,
  _ => WorkoutSetStatus.unknown,
};

WorkoutSetKind workoutSetKindFromStorage(String name) => switch (name) {
  'warmup' => WorkoutSetKind.warmup,
  'working' => WorkoutSetKind.working,
  _ => WorkoutSetKind.unknown,
};
