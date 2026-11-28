import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock.dart';
import '../health/application/health_overview.dart';
import '../health/domain/readiness.dart';
import '../progress/muscle_recovery.dart';
import '../progress/workout_history_state.dart';
import '../workouts/data/objectbox_workout_library_repository.dart';
import '../workouts/domain/workout_library_models.dart';
import 'plan_fit.dart';

/// Repository is the sole data owner: screens never operate on ObjectBox boxes.
final trainLibraryProvider = FutureProvider<WorkoutLibrarySnapshot>((
  ref,
) async {
  final repository = ref.watch(workoutLibraryRepositoryProvider);
  repository.ensureCatalogSeeded();
  return WorkoutLibrarySnapshot(
    exercises: repository.listExercises(includeArchived: true),
    plans: repository.listPlans(),
  );
});

/// How recovered each plan's muscles are, and the plan that fits today best.
class PlanFit {
  const PlanFit({required this.byPlan, required this.suggestion});

  /// Only plans with at least one exercise that maps to a drawn muscle.
  final Map<String, PlanRecovery> byPlan;
  final PlanSuggestion? suggestion;
}

/// Null while the library or completed history loads or fails, and when
/// there are no completed workouts. Health loading, failing or unavailable
/// only means readiness is not low.
final planFitProvider = Provider.autoDispose<PlanFit?>((ref) {
  final library = ref.watch(trainLibraryProvider).value;
  final history = ref.watch(completedWorkoutHistoryProvider).value;
  if (library == null || history == null || history.sessions.isEmpty) {
    return null;
  }
  final recovery = ref.watch(muscleRecoveryProvider);
  final exercises = {for (final e in library.exercises) e.uuid: e};
  final byPlan = <String, PlanRecovery>{};
  for (final plan in library.plans) {
    final planRecovery = planRecoveryOf(plan, exercises, recovery);
    if (planRecovery != null) byPlan[plan.uuid] = planRecovery;
  }
  final overview = ref.watch(healthOverviewProvider).value;
  final energy = overview == null
      ? null
      : currentEnergyScore(overview, ref.watch(localNowProvider));
  final low = energy != null && energy.band == ReadinessBand.low;
  return PlanFit(
    byPlan: byPlan,
    suggestion: suggestPlan(byPlan.values.toList(), lowReadiness: low),
  );
});
