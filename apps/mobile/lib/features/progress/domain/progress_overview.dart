import '../../workouts/domain/workout_models.dart';
import 'workout_history_models.dart';

/// This week (Sunday to Saturday, on each session's original local day) next
/// to the week before. Nothing here is estimated: volume is the loaded
/// working-set total from [calculateWorkoutHistory] and is null, never zero,
/// when no loaded set exists.
class WeekOverview {
  const WeekOverview({
    required this.volumeGramReps,
    required this.previousVolumeGramReps,
    required this.workoutTime,
    required this.previousWorkoutTime,
    required this.sessions,
  });

  final int? volumeGramReps;
  final int? previousVolumeGramReps;
  final Duration workoutTime;
  final Duration previousWorkoutTime;
  final int sessions;

  /// Whole-percent change in volume, or null when either week has none.
  int? get volumeChangePercent {
    final now = volumeGramReps;
    final before = previousVolumeGramReps;
    if (now == null || before == null || before <= 0) return null;
    return ((now - before) * 100 / before).round();
  }

  /// Whole-percent change in workout time, or null without a previous week.
  int? get timeChangePercent {
    if (previousWorkoutTime == Duration.zero) return null;
    return ((workoutTime - previousWorkoutTime).inSeconds *
            100 /
            previousWorkoutTime.inSeconds)
        .round();
  }
}

class MonthConsistency {
  const MonthConsistency({
    required this.month,
    required this.trainedDays,
    required this.totalSessions,
    required this.weekStreak,
  });

  /// First day of the month shown, as a UTC date.
  final DateTime month;
  final Set<int> trainedDays;

  /// Every finished session, not only this month.
  final int totalSessions;

  /// Consecutive weeks, ending this week, with at least one session. An empty
  /// current week does not break the streak until the week is over.
  final int weekStreak;
}

DateTime _weekStart(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day - (day.weekday % 7));

Iterable<WorkoutSessionRecord> _finished(WorkoutHistorySnapshot snapshot) =>
    snapshot.sessions.where(
      (s) => s.status == WorkoutStatus.completed && s.completedAtUtc != null,
    );

Duration _duration(WorkoutSessionRecord s) {
  final d = s.completedAtUtc!.difference(s.startedAtUtc);
  return d.isNegative ? Duration.zero : d;
}

/// [today] is a UTC date holding the device's current local calendar day.
WeekOverview weekOverview(WorkoutHistorySnapshot snapshot, DateTime today) {
  final start = _weekStart(today);
  final previous = start.subtract(const Duration(days: 7));
  final next = start.add(const Duration(days: 7));
  final thisWeek = <WorkoutSessionRecord>[];
  final lastWeek = <WorkoutSessionRecord>[];
  for (final s in _finished(snapshot)) {
    final day = originalLocalDay(s);
    if (!day.isBefore(start) && day.isBefore(next)) {
      thisWeek.add(s);
    } else if (!day.isBefore(previous) && day.isBefore(start)) {
      lastWeek.add(s);
    }
  }
  int? volume(List<WorkoutSessionRecord> sessions) {
    final summary = calculateWorkoutHistory(sessions);
    return summary.loadedWorkingSets == 0 ? null : summary.loadedVolumeGramReps;
  }

  Duration total(List<WorkoutSessionRecord> sessions) =>
      sessions.fold(Duration.zero, (sum, s) => sum + _duration(s));

  return WeekOverview(
    volumeGramReps: volume(thisWeek),
    previousVolumeGramReps: volume(lastWeek),
    workoutTime: total(thisWeek),
    previousWorkoutTime: total(lastWeek),
    sessions: thisWeek.length,
  );
}

MonthConsistency monthConsistency(
  WorkoutHistorySnapshot snapshot,
  DateTime today,
  DateTime month,
) {
  final first = DateTime.utc(month.year, month.month);
  final days = <int>{};
  final weeks = <DateTime>{};
  var total = 0;
  for (final s in _finished(snapshot)) {
    total++;
    final day = originalLocalDay(s);
    weeks.add(_weekStart(day));
    if (day.year == first.year && day.month == first.month) days.add(day.day);
  }
  var cursor = _weekStart(today);
  if (!weeks.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 7));
  }
  var streak = 0;
  while (weeks.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 7));
  }
  return MonthConsistency(
    month: first,
    trainedDays: days,
    totalSessions: total,
    weekStreak: streak,
  );
}

/// "1h 15m", "45m", "0m". Seconds are dropped, so under a minute reads "0m".
String formatDurationShort(Duration d) {
  final minutes = d.inMinutes;
  if (minutes >= 60) {
    final rest = minutes % 60;
    return rest == 0 ? '${minutes ~/ 60}h' : '${minutes ~/ 60}h ${rest}m';
  }
  return '${minutes}m';
}

/// "00:26:44".
String formatDurationClock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}
