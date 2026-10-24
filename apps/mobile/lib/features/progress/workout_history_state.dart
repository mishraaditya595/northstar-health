import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/objectbox_workout_history_repository.dart';
import 'domain/workout_history_models.dart';

/// Retained across tabs. Invalidated after a finish/discard or user refresh.
/// ObjectBox executes this read transaction in its own background isolate.
final completedWorkoutHistoryProvider = FutureProvider<WorkoutHistorySnapshot>(
  (ref) => ref.watch(workoutHistoryRepositoryProvider).readCompletedAsync(),
);

/// Injectable clock: period boundaries do not depend on widget rebuild time.
final progressNowProvider = Provider<DateTime>((ref) => DateTime.now().toUtc());
