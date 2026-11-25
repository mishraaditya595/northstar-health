import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../workouts/domain/muscles.dart';
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

/// The drawn muscle for a catalogue muscle name, or null for an unknown name.
Muscle? muscleFromName(String name) {
  for (final muscle in Muscle.values) {
    if (muscle.name == name) return muscle;
  }
  return null;
}

/// Share of a set's stimulus that a secondary muscle receives.
const secondaryMuscleWeight = 0.5;

/// A muscle group below this load counts as recovered: not shaded or listed
/// on Progress, not recovering on Train.
const recoveredBelow = 0.1;

/// Display name of a logged muscle group: trimmed, lower-cased, first letter
/// capitalised, so "UPPER chest" and "Upper chest" are one group. Empty stays
/// empty.
String groupDisplayName(String group) {
  final key = group.trim().toLowerCase();
  return key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);
}

/// How recently each muscle was trained, 0 (recovered / not trained) to 1
/// (just trained). Missing means no data, drawn neutral.
class MuscleRecovery {
  const MuscleRecovery(this.load, {this.groups = const {}});

  final Map<Muscle, double> load;

  /// The logged muscle groups, by display name, with the same 0..1 value.
  /// Exercises only record a group ("Legs"), so this, not the individual
  /// drawn muscles, is what the card names as trained. It includes custom
  /// groups that map to no drawn muscle.
  final Map<String, double> groups;

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

  /// Groups that recover in [_smallWindow]: the catalog's small groups and
  /// custom groups named after a small drawn muscle.
  static const _smallGroups = {
    'shoulders',
    'arms',
    'core',
    'calves',
    'biceps',
    'triceps',
    'forearms',
    'abs',
    'obliques',
  };
  static const _smallWindow = Duration(hours: 48);

  /// The drawn muscles a logged group covers: the catalog table, then a
  /// custom group named after a drawn muscle. Empty when none is drawn.
  static List<Muscle> musclesOf(String group) {
    final key = group.trim().toLowerCase();
    return _groups[key] ??
        [
          for (final m in Muscle.values)
            if (m.name.toLowerCase() == key) m,
        ];
  }

  /// Per completed working set: a reps weight (unknown or 5 and up 1.0,
  /// 0 to 4 reps 0.7, so heavy low-rep work still counts) times an effort
  /// weight (RPE 8+ 1.0, 6-8 0.75, below 6 0.5, unrated 0.8).
  static double _stimulus(WorkoutSetRecord set) {
    final reps = set.reps;
    final repsFactor = reps == null || reps >= 5 ? 1.0 : 0.7;
    final rpe = set.rpe;
    final effort = rpe == null
        ? 0.8
        : rpe >= 8
        ? 1.0
        : rpe >= 6
        ? 0.75
        : 0.5;
    return repsFactor * effort;
  }

  /// Muscles that recover in [_smallWindow] on the fine path.
  static const _smallMuscles = {
    Muscle.shoulders,
    Muscle.biceps,
    Muscle.triceps,
    Muscle.forearms,
    Muscle.abs,
    Muscle.obliques,
    Muscle.calves,
  };

  static double _fade(Duration age, Duration span) => age.isNegative
      ? 1.0
      : age >= span
      ? 0.0
      : 1 - age.inSeconds / span.inSeconds;

  /// A finished workout loads what it worked, within 72 h.
  ///
  /// Exercises with a muscle snapshot (catalogue exercises) work specific
  /// muscles: each completed working set adds its stimulus to every primary
  /// muscle and [secondaryMuscleWeight] times that to every secondary one.
  /// A muscle's session load is `min(1, Σ / 10)`, fading linearly over its
  /// window (48 h small muscles, 72 h others); sessions add up, capped at 1.
  ///
  /// Exercises without one (custom, or logged before muscles existed) work
  /// their logged group: `min(1, Σ stimulus / 10)` fading over the group's
  /// window (48 h small groups, 72 h others), summed per group across
  /// sessions, capped at 1; each drawn muscle takes its group's value (the
  /// highest if two groups cover it).
  ///
  /// A drawn muscle takes the larger of its specific and group values, never
  /// their sum.
  factory MuscleRecovery.fromWorkouts(
    Iterable<WorkoutSessionRecord> sessions,
    DateTime nowUtc,
  ) {
    final coarse = <String, double>{};
    final fine = <Muscle, double>{};
    for (final session in sessions) {
      final finished = session.completedAtUtc;
      if (session.status != WorkoutStatus.completed || finished == null) {
        continue;
      }
      final age = nowUtc.difference(finished);
      if (age >= window) continue;
      final stimulus = <String, double>{};
      final fineStimulus = <Muscle, double>{};
      for (final exercise in session.exercises) {
        final primary = [
          for (final name in exercise.primaryMusclesSnapshot)
            ?muscleFromName(name),
        ];
        final secondary = [
          for (final name in exercise.secondaryMusclesSnapshot)
            ?muscleFromName(name),
        ];
        final group = exercise.muscleSnapshot.trim().toLowerCase();
        if (primary.isEmpty && group.isEmpty) continue;
        for (final set in session.sets) {
          if (set.exerciseUuid != exercise.uuid ||
              set.status != WorkoutSetStatus.completed ||
              set.kind != WorkoutSetKind.working) {
            continue;
          }
          final value = _stimulus(set);
          if (primary.isEmpty) {
            stimulus[group] = (stimulus[group] ?? 0) + value;
            continue;
          }
          for (final m in primary) {
            fineStimulus[m] = (fineStimulus[m] ?? 0) + value;
          }
          for (final m in secondary) {
            fineStimulus[m] =
                (fineStimulus[m] ?? 0) + secondaryMuscleWeight * value;
          }
        }
      }
      for (final entry in stimulus.entries) {
        final group = entry.key;
        // `legs` is a catalog group, so its calves keep the 72 h window.
        final span = _smallGroups.contains(group) ? _smallWindow : window;
        final value = (entry.value / 10).clamp(0.0, 1.0) * _fade(age, span);
        // Named even when no drawn muscle matches, so the card never says
        // nothing was trained after a workout of custom groups.
        final name = groupDisplayName(group);
        coarse[name] = ((coarse[name] ?? 0) + value).clamp(0.0, 1.0);
      }
      for (final entry in fineStimulus.entries) {
        final span = _smallMuscles.contains(entry.key) ? _smallWindow : window;
        final value = (entry.value / 10).clamp(0.0, 1.0) * _fade(age, span);
        fine[entry.key] = ((fine[entry.key] ?? 0) + value).clamp(0.0, 1.0);
      }
    }
    final load = <Muscle, double>{};
    for (final entry in coarse.entries) {
      for (final m in musclesOf(entry.key)) {
        if (entry.value > (load[m] ?? 0)) load[m] = entry.value;
      }
    }
    final groups = {...coarse};
    for (final entry in fine.entries) {
      if (entry.value > (load[entry.key] ?? 0)) load[entry.key] = entry.value;
      final name = muscleDisplayName(entry.key.name);
      if (entry.value > (groups[name] ?? 0)) groups[name] = entry.value;
    }
    return MuscleRecovery(load, groups: groups);
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
