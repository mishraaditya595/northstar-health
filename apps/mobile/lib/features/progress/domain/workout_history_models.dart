import '../../../core/units/load_units.dart';
import '../../workouts/domain/workout_models.dart';

/// Only explicit, locally committed COMPLETED NorthStar workouts are history.
class WorkoutHistorySnapshot {
  const WorkoutHistorySnapshot({required this.sessions});
  final List<WorkoutSessionRecord> sessions;
}

enum WorkoutHistoryPeriod { last30Days, last90Days, all }

/// A rolling window around an explicitly supplied UTC clock.
List<WorkoutSessionRecord> workoutsInPeriod(
  WorkoutHistorySnapshot snapshot,
  WorkoutHistoryPeriod period,
  DateTime nowUtc,
) {
  final cutoff = switch (period) {
    WorkoutHistoryPeriod.last30Days => nowUtc.toUtc().subtract(
      const Duration(days: 30),
    ),
    WorkoutHistoryPeriod.last90Days => nowUtc.toUtc().subtract(
      const Duration(days: 90),
    ),
    WorkoutHistoryPeriod.all => null,
  };
  return snapshot.sessions
      .where(
        (s) =>
            s.status == WorkoutStatus.completed &&
            s.completedAtUtc != null &&
            (cutoff == null || !s.completedAtUtc!.isBefore(cutoff)),
      )
      .toList();
}

String formatWorkoutDay(DateTime day) =>
    '${day.day.toString().padLeft(2, '0')}/'
    '${day.month.toString().padLeft(2, '0')}/${day.year}';

class WorkoutHistorySummary {
  const WorkoutHistorySummary({
    required this.completedWorkouts,
    required this.completedWorkingSets,
    required this.loadedVolumeGramReps,
    required this.loadedWorkingSets,
    required this.unloadedWorkingSets,
    required this.zeroLoadWorkingSets,
    required this.exerciseTrends,
  });

  final int completedWorkouts;
  final int completedWorkingSets;

  /// Sum of reps * grams for loaded working sets. NOT calories or total
  /// volume when bodyweight/unloaded sets are present.
  final int loadedVolumeGramReps;
  final int loadedWorkingSets;
  final int unloadedWorkingSets;
  final int zeroLoadWorkingSets;
  final List<ExerciseStrengthTrend> exerciseTrends;
}

class ExerciseStrengthPoint {
  const ExerciseStrengthPoint({
    required this.sessionUuid,
    required this.performedAtUtc,
    required this.grams,
    required this.reps,
    required this.inputUnit,
    required this.originalOffsetMinutes,
  });

  final String sessionUuid;
  final DateTime performedAtUtc;
  final int grams;
  final int reps;
  final LoadUnit inputUnit;
  final int originalOffsetMinutes;

  /// Local day reconstructed from the original session offset (not the
  /// current device timezone), keeping chart labels consistent with history.
  DateTime get originalLocalDay {
    final at = performedAtUtc.toUtc().add(
      Duration(minutes: originalOffsetMinutes),
    );
    return DateTime.utc(at.year, at.month, at.day);
  }
}

class ExerciseStrengthTrend {
  const ExerciseStrengthTrend({
    required this.key,
    required this.name,
    required this.points,
  });
  final String key;
  final String name;
  final List<ExerciseStrengthPoint> points;

  int get bestLoadGrams => points
      .map((p) => p.grams)
      .fold<int>(0, (best, grams) => grams > best ? grams : best);
}

/// Pure summaries: use only performed working sets from finished sessions.
/// Warm-ups, skipped/planned, unknown status/kind and incomplete values never
/// become strength or volume numbers. No 1RM/calorie claims.
WorkoutHistorySummary calculateWorkoutHistory(
  Iterable<WorkoutSessionRecord> source,
) {
  final sessions = source
      .where(
        (s) => s.status == WorkoutStatus.completed && s.completedAtUtc != null,
      )
      .toList();
  var workouts = 0;
  var workingSets = 0;
  var loadedWorking = 0;
  var unloadedWorking = 0;
  var zeroLoadWorking = 0;
  var volume = 0;
  final trends = <String, List<ExerciseStrengthPoint>>{};
  final labels = <String, String>{};
  final labelTimes = <String, DateTime>{};

  // Name snapshots lacking a definition ID join a definition only when
  // name, equipment AND muscle match a single unambiguous definition.
  // Different variants (e.g. barbell vs dumbbell) remain distinct.
  String signature(WorkoutExerciseRecord e) =>
      '${e.nameSnapshot.trim().toLowerCase()}|'
      '${e.equipmentSnapshot.trim().toLowerCase()}|'
      '${e.muscleSnapshot.trim().toLowerCase()}';
  final definitionsBySignature = <String, Set<String>>{};
  for (final session in sessions) {
    for (final exercise in session.exercises) {
      final id = exercise.definitionUuid;
      if (id != null && id.isNotEmpty) {
        definitionsBySignature
            .putIfAbsent(signature(exercise), () => <String>{})
            .add('definition:$id');
      }
    }
  }

  for (final session in sessions) {
    workouts++;
    final exercises = {
      for (final exercise in session.exercises) exercise.uuid: exercise,
    };
    final bestByExercise = <String, WorkoutSetRecord>{};
    for (final set in session.sets) {
      if (set.status != WorkoutSetStatus.completed ||
          set.kind != WorkoutSetKind.working ||
          set.reps == null) {
        continue;
      }
      workingSets++;
      if (set.loadGrams == null) {
        unloadedWorking++;
        continue;
      }
      if (set.loadGrams! == 0) {
        zeroLoadWorking++;
        continue;
      }
      loadedWorking++;
      // int arithmetic: no floating-point rounding and no estimated 1RM.
      volume += set.loadGrams! * set.reps!;
      final exercise = exercises[set.exerciseUuid];
      if (exercise == null) continue;
      final identified = exercise.definitionUuid;
      final sig = signature(exercise);
      final matches = definitionsBySignature[sig];
      final key = identified != null && identified.isNotEmpty
          ? 'definition:$identified'
          : matches != null && matches.length == 1
          ? matches.single
          : 'snapshot:$sig';
      final loggedAt = session.completedAtUtc!;
      if (labelTimes[key] == null || !loggedAt.isBefore(labelTimes[key]!)) {
        labelTimes[key] = loggedAt;
        labels[key] = exercise.nameSnapshot;
      }
      final previous = bestByExercise[key];
      if (previous == null ||
          set.loadGrams! > previous.loadGrams! ||
          (set.loadGrams == previous.loadGrams && set.reps! > previous.reps!)) {
        bestByExercise[key] = set;
      }
    }
    for (final entry in bestByExercise.entries) {
      final sample = entry.value;
      trends
          .putIfAbsent(entry.key, () => [])
          .add(
            ExerciseStrengthPoint(
              sessionUuid: session.uuid,
              // Trend points represent a completed workout. The chosen set
              // supplies load/reps, but the date must match the history row
              // even when that set was logged before midnight.
              performedAtUtc: session.completedAtUtc!,
              grams: sample.loadGrams!,
              reps: sample.reps!,
              inputUnit: sample.inputUnit,
              originalOffsetMinutes: session.originalOffsetMinutes,
            ),
          );
    }
  }
  final result = [
    for (final entry in trends.entries)
      ExerciseStrengthTrend(
        key: entry.key,
        name: labels[entry.key]!,
        points: entry.value
          ..sort((a, b) {
            final time = a.performedAtUtc.compareTo(b.performedAtUtc);
            return time != 0 ? time : a.sessionUuid.compareTo(b.sessionUuid);
          }),
      ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return WorkoutHistorySummary(
    completedWorkouts: workouts,
    completedWorkingSets: workingSets,
    loadedWorkingSets: loadedWorking,
    unloadedWorkingSets: unloadedWorking,
    zeroLoadWorkingSets: zeroLoadWorking,
    loadedVolumeGramReps: volume,
    exerciseTrends: List.unmodifiable(result),
  );
}

/// Human-readable gym-log date under the offset captured when the session
/// began, without assuming the phone's CURRENT timezone or its DST rules.
DateTime originalLocalDay(WorkoutSessionRecord workout) {
  final instant = workout.completedAtUtc ?? workout.startedAtUtc;
  final shifted = instant.toUtc().add(
    Duration(minutes: workout.originalOffsetMinutes),
  );
  return DateTime.utc(shifted.year, shifted.month, shifted.day);
}

int countWorkingSets(WorkoutSessionRecord session) => session.sets
    .where(
      (s) =>
          s.kind == WorkoutSetKind.working &&
          s.status == WorkoutSetStatus.completed &&
          s.reps != null,
    )
    .length;
