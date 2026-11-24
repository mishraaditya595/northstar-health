import '../progress/domain/progress_overview.dart';
import '../progress/domain/workout_history_models.dart';
import '../workouts/domain/workout_library_models.dart';
import '../workouts/domain/workout_models.dart';

/// Finished sessions on each day of [weekDays] for [today], counted on each
/// session's original local day like Progress.
List<int> sessionsPerDay(WorkoutHistorySnapshot snapshot, DateTime today) {
  final days = weekDays(today);
  final counts = List.filled(days.length, 0);
  for (final s in snapshot.sessions) {
    if (s.status != WorkoutStatus.completed || s.completedAtUtc == null) {
      continue;
    }
    final index = days.indexOf(originalLocalDay(s));
    if (index >= 0) counts[index]++;
  }
  return counts;
}

class NextPlan {
  const NextPlan(this.plan, this.lastDone);
  final WorkoutPlanRecord plan;

  /// The latest finished workout started from this plan, or null if never.
  final WorkoutSessionRecord? lastDone;
}

/// A saved plan to suggest on Today. There is no schedule, so this rotates:
/// a plan never finished comes first (most recently edited first, the order
/// [plans] arrives in), otherwise the plan finished longest ago.
NextPlan? nextPlan(
  List<WorkoutPlanRecord> plans,
  Iterable<WorkoutSessionRecord> sessions,
) {
  if (plans.isEmpty) return null;
  final lastDone = <String, WorkoutSessionRecord>{};
  for (final s in sessions) {
    final plan = s.planUuid;
    final at = s.completedAtUtc;
    if (s.status != WorkoutStatus.completed || plan == null || at == null) {
      continue;
    }
    final seen = lastDone[plan];
    if (seen == null || at.isAfter(seen.completedAtUtc!)) lastDone[plan] = s;
  }
  NextPlan? best;
  for (final plan in plans) {
    final done = lastDone[plan.uuid];
    if (done == null) return NextPlan(plan, null);
    if (best == null ||
        done.completedAtUtc!.isBefore(best.lastDone!.completedAtUtc!)) {
      best = NextPlan(plan, done);
    }
  }
  return best;
}
