import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/objectbox_workout_history_repository.dart';
import 'domain/workout_history_models.dart';

/// Retained across tabs. Invalidated after a finish/discard or user refresh.
/// ObjectBox executes this read transaction in its own background isolate.
final completedWorkoutHistoryProvider = FutureProvider<WorkoutHistorySnapshot>(
  (ref) => ref.watch(workoutHistoryRepositoryProvider).readCompletedAsync(),
);

/// Injectable clock used by Progress and Train recovery, not cached with the
/// completed history. Sampled when first read and re-sampled on app resume,
/// so those pages stay current after days in background; there is no periodic
/// timer. Disposes after the last listener leaves.
final progressNowProvider = Provider.autoDispose<DateTime>((ref) {
  final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(lifecycle.dispose);
  return DateTime.now().toUtc();
});
