import '../progress/muscle_recovery.dart';
import '../workouts/domain/workout_library_models.dart';

/// A muscle group at or above this load still counts as recovering.
const recoveredBelow = 0.25;

/// Smallest `worstLoad` lead a plan needs over every other plan to be named.
const _clearLead = 0.2;

/// How recovered the muscles a plan trains are.
class PlanRecovery {
  const PlanRecovery({
    required this.planUuid,
    required this.groups,
    required this.recovering,
    required this.worstLoad,
    required this.totalSets,
  });

  final String planUuid;

  /// The plan's muscle groups that map to a drawn muscle, by display name.
  final Set<String> groups;

  /// The [groups] whose load is at least [recoveredBelow].
  final Set<String> recovering;

  /// Highest load over the plan's drawn muscles.
  final double worstLoad;

  /// Target sets over every plan exercise, mapped or not.
  final int totalSets;

  bool get isRecovered => recovering.isEmpty;
}

/// Null when no exercise of [plan] maps to a drawn muscle.
PlanRecovery? planRecoveryOf(
  WorkoutPlanRecord plan,
  Map<String, ExerciseRecord> exercisesByUuid,
  MuscleRecovery recovery,
) {
  final groups = <String>{};
  final recovering = <String>{};
  var worst = 0.0;
  var totalSets = 0;
  var mapped = false;
  for (final planExercise in plan.exercises) {
    totalSets += planExercise.targetSets;
    final exercise = exercisesByUuid[planExercise.exerciseUuid];
    if (exercise == null) continue;
    final trimmed = exercise.muscleGroup.trim();
    final muscles = MuscleRecovery.musclesOf(trimmed);
    if (muscles.isEmpty) continue;
    mapped = true;
    final name = '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
    groups.add(name);
    var groupLoad = 0.0;
    for (final muscle in muscles) {
      final load = recovery.loadOf(muscle);
      if (load > groupLoad) groupLoad = load;
    }
    if (groupLoad >= recoveredBelow) recovering.add(name);
    if (groupLoad > worst) worst = groupLoad;
  }
  if (!mapped) return null;
  return PlanRecovery(
    planUuid: plan.uuid,
    groups: groups,
    recovering: recovering,
    worstLoad: worst,
    totalSets: totalSets,
  );
}

sealed class PlanSuggestion {
  const PlanSuggestion(this.plan);
  final PlanRecovery plan;
}

/// [plan] is clearly the most recovered; [restedGroups] are muscle groups
/// other plans would still hit while they recover.
class SuggestRecovered extends PlanSuggestion {
  const SuggestRecovered(super.plan, this.restedGroups);
  final Set<String> restedGroups;
}

/// Readiness is low: the lightest fully recovered plan.
class SuggestLightest extends PlanSuggestion {
  const SuggestLightest(super.plan);
}

PlanSuggestion? suggestPlan(
  List<PlanRecovery> plans, {
  required bool lowReadiness,
}) {
  if (lowReadiness) {
    PlanRecovery? lightest;
    for (final plan in plans) {
      if (!plan.isRecovered) continue;
      if (lightest == null || plan.totalSets < lightest.totalSets) {
        lightest = plan;
      }
    }
    return lightest == null ? null : SuggestLightest(lightest);
  }
  if (plans.length < 2) return null;
  var best = plans.first;
  for (final plan in plans) {
    if (plan.worstLoad < best.worstLoad) best = plan;
  }
  if (!best.isRecovered) return null;
  final rested = <String>{};
  for (final plan in plans) {
    if (identical(plan, best)) continue;
    if (plan.worstLoad - best.worstLoad < _clearLead) return null;
    rested.addAll(plan.recovering);
  }
  rested.removeAll(best.groups);
  if (rested.isEmpty) return null;
  return SuggestRecovered(best, rested);
}
