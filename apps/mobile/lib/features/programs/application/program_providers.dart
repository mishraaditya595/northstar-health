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

/// Refresh every screen that shows programs or program plans.
void invalidatePrograms(WidgetRef ref) {
  ref.invalidate(localProgramsProvider);
  ref.invalidate(localProgramProvider);
  ref.invalidate(activeProgramCardProvider);
  ref.invalidate(trainLibraryProvider);
}
