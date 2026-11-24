import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../workouts/domain/workout_models.dart';
import 'workout_history_state.dart';

/// Muscle groups drawn on the body map. Some appear on both figures.
enum Muscle {
  chest,
  shoulders,
  biceps,
  forearms,
  abs,
  obliques,
  quads,
  calves,
  traps,
  lats,
  lowerBack,
  triceps,
  glutes,
  hamstrings,
}

/// How recently each muscle was trained, 0 (recovered / not trained) to 1
/// (just trained). Missing means no data, drawn neutral.
class MuscleRecovery {
  const MuscleRecovery(this.load);

  final Map<Muscle, double> load;

  double loadOf(Muscle muscle) => (load[muscle] ?? 0).clamp(0.0, 1.0);

  /// Work older than this counts as recovered.
  static const window = Duration(hours: 72);

  /// Catalog muscle groups (see built_in_exercises.dart) and the drawn
  /// muscles they cover. A custom group named after a drawn muscle, such as
  /// "Glutes", maps to that muscle; any other group is not drawn.
  static const _groups = {
    'chest': [Muscle.chest],
    'shoulders': [Muscle.shoulders],
    'back': [Muscle.lats, Muscle.traps, Muscle.lowerBack],
    'legs': [Muscle.quads, Muscle.hamstrings, Muscle.glutes, Muscle.calves],
    'arms': [Muscle.biceps, Muscle.triceps, Muscle.forearms],
    'core': [Muscle.abs, Muscle.obliques],
  };

  /// Exercises with a completed working set in a finished workout inside
  /// [window] load their muscles, fading linearly from 1 at finish to 0.
  factory MuscleRecovery.fromWorkouts(
    Iterable<WorkoutSessionRecord> sessions,
    DateTime nowUtc,
  ) {
    final load = <Muscle, double>{};
    for (final session in sessions) {
      final finished = session.completedAtUtc;
      if (session.status != WorkoutStatus.completed || finished == null) {
        continue;
      }
      final age = nowUtc.difference(finished);
      if (age >= window) continue;
      final value = age.isNegative ? 1.0 : 1 - age.inSeconds / window.inSeconds;
      final worked = {
        for (final set in session.sets)
          if (set.status == WorkoutSetStatus.completed &&
              set.kind == WorkoutSetKind.working)
            set.exerciseUuid,
      };
      for (final exercise in session.exercises) {
        if (!worked.contains(exercise.uuid)) continue;
        final group = exercise.muscleSnapshot.trim().toLowerCase();
        final muscles =
            _groups[group] ??
            [
              for (final m in Muscle.values)
                if (m.name.toLowerCase() == group) m,
            ];
        for (final m in muscles) {
          if (value > (load[m] ?? 0)) load[m] = value;
        }
      }
    }
    return MuscleRecovery(load);
  }
}

/// Derived from finished workouts on this device and the Progress clock.
/// Empty while history loads or fails; the Progress page shows that state.
final muscleRecoveryProvider = Provider.autoDispose<MuscleRecovery>((ref) {
  final history = ref.watch(completedWorkoutHistoryProvider).value;
  return MuscleRecovery.fromWorkouts(
    history?.sessions ?? const [],
    ref.watch(progressNowProvider),
  );
});
