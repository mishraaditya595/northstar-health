import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/application/exercise_choices_provider.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../catalog/domain/catalog_programs.dart';
import '../../train/train_library_state.dart';
import '../../workouts/data/objectbox_workout_library_repository.dart';
import '../data/objectbox_program_repository.dart';
import '../domain/program_models.dart';
import '../domain/program_schedule.dart';
import '../domain/program_status.dart';
import '../../train/active_workout_state.dart';
import '../../workouts/data/objectbox_workout_repository.dart';
import '../../workouts/domain/workout_library_models.dart';

/// Programs the phone can show from the cached catalogue.
final catalogProgramsProvider = Provider<List<CatalogProgram>>((ref) {
  final snapshot = safeCatalogState(() => ref.watch(catalogStateProvider))
      .snapshot;
  return snapshot == null ? const [] : browsablePrograms(snapshot);
});

/// The user's programs from the account store, newest first. Empty when the
/// store is not available. Invalidate after a write.
final localProgramsProvider = Provider.autoDispose<List<TrainingProgramRecord>>(
  (ref) {
    try {
      return ref.watch(programRepositoryProvider).listPrograms();
    } on Object {
      return const [];
    }
  },
);

final localProgramProvider = Provider.autoDispose
    .family<TrainingProgramRecord?, String>((ref, uuid) {
      try {
        final program = ref.watch(programRepositoryProvider).getProgram(uuid);
        return program == null || program.archivedAtMs != null ? null : program;
      } on Object {
        return null;
      }
    });

/// What the Train card for the active program shows.
class ActiveProgramCard {
  const ActiveProgramCard(
    this.program,
    this.todayWorkout, {
    this.unavailable = false,
  });
  final TrainingProgramRecord program;

  /// Name of today's workout, or null on a rest day or when it is
  /// [unavailable].
  final String? todayWorkout;

  /// Today's day points at a plan that is missing or archived.
  final bool unavailable;
}

final activeProgramCardProvider = Provider.autoDispose<ActiveProgramCard?>((
  ref,
) {
  final active = ref
      .watch(localProgramsProvider)
      .where((p) => p.isActive)
      .firstOrNull;
  if (active == null) return null;
  final planUuid = dayFor(active, ref.watch(localNowProvider)).planUuid;
  String? name;
  if (planUuid != null) {
    try {
      name = ref
          .watch(workoutLibraryRepositoryProvider)
          .getPlan(planUuid)
          ?.name;
    } on Object {
      name = null;
    }
  }
  return ActiveProgramCard(
    active,
    name,
    unavailable: planUuid != null && name == null,
  );
});

/// The active program's current week, computed fresh from the clock, the
/// program's plans and its finished sessions. Never stored.
class ProgramWeek {
  const ProgramWeek({
    required this.program,
    required this.localToday,
    required this.rows,
    required this.plans,
    required this.latestMissed,
    required this.nextTraining,
  });
  final TrainingProgramRecord program;
  final DateTime localToday;
  final List<ProgramWeekRow> rows;

  /// The program's available plans by UUID.
  final Map<String, WorkoutPlanRecord> plans;
  final ({DateTime date, ProgramDayRecord day})? latestMissed;
  final ({DateTime date, ProgramDayRecord day})? nextTraining;

  ProgramWeekRow? get todayRow => rows
      .where(
        (r) =>
            r.date ==
            DateTime(localToday.year, localToday.month, localToday.day),
      )
      .firstOrNull;
}

/// Null without an active program or when the store is unavailable.
/// Recomputes after any workout change (finish, discard) through
/// [activeWorkoutProvider], after program edits through
/// [localProgramsProvider], and on resume through [localNowProvider].
final programWeekProvider = Provider.autoDispose<ProgramWeek?>((ref) {
  ref.watch(activeWorkoutProvider);
  final active = ref
      .watch(localProgramsProvider)
      .where((p) => p.isActive)
      .firstOrNull;
  if (active == null) return null;
  final localToday = ref.watch(localNowProvider);
  try {
    final plans = ref
        .watch(programRepositoryProvider)
        .programPlans(active.uuid);
    final available = {for (final p in plans) p.uuid};
    final sessions = ref
        .watch(workoutRepositoryProvider)
        .listProgramSessions(active.uuid);
    return ProgramWeek(
      program: active,
      localToday: localToday,
      rows: programWeekStatus(
        program: active,
        localToday: localToday,
        sessions: sessions,
        availablePlanUuids: available,
      ),
      plans: {for (final p in plans) p.uuid: p},
      latestMissed: latestMissed(
        program: active,
        localToday: localToday,
        sessions: sessions,
        availablePlanUuids: available,
      ),
      nextTraining: nextTraining(
        program: active,
        localToday: localToday,
        availablePlanUuids: available,
      ),
    );
  } on Object {
    return null;
  }
});

/// Refresh every screen that shows programs or program plans.
void invalidatePrograms(WidgetRef ref) {
  ref.invalidate(localProgramsProvider);
  ref.invalidate(localProgramProvider);
  ref.invalidate(activeProgramCardProvider);
  ref.invalidate(programWeekProvider);
  ref.invalidate(trainLibraryProvider);
}
