import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/clock.dart';
import '../../health/widgets/readiness_note.dart';
import '../../train/active_workout_state.dart';
import '../../watch/widgets/live_watch_auto_open.dart';
import '../application/program_providers.dart';
import '../domain/program_models.dart';
import '../domain/program_schedule.dart';

const _startFailedMessage =
    'Could not start this workout. Check the plan and any unfinished '
    'workout.';

/// Starts [program]'s workout for today, or for a missed day when
/// [missedDate] and [missedPlanUuid] are given, and opens the logger. Reports
/// problems through [onFailed]; the caller keeps any busy state.
Future<void> startProgramDay(
  BuildContext context,
  WidgetRef ref,
  TrainingProgramRecord program, {
  DateTime? missedDate,
  String? missedPlanUuid,
  required void Function(String message) onFailed,
}) async {
  void startFailed() {
    onFailed(_startFailedMessage);
    ref.invalidate(activeWorkoutProvider);
  }

  if (openLiveWatchWorkoutInstead(context, ref)) return;
  final active = ref.read(activeWorkoutProvider);
  if (active.value != null || active.hasError) {
    startFailed();
    return;
  }
  if (!await confirmReadinessBeforeStart(context, ref) || !context.mounted) {
    return;
  }
  try {
    ref
        .read(workoutActionsProvider)
        .startProgramDay(
          program,
          expectedPlanUuid: missedDate == null
              ? dayFor(program, ref.read(localNowProvider)).planUuid
              : missedPlanUuid,
          missedDate: missedDate,
        );
    ref.invalidate(activeWorkoutProvider);
    invalidatePrograms(ref);
  } on ProgramDayChanged {
    // The day rolled over or the schedule changed since the screen was
    // built: show the current day instead of starting the wrong one.
    ref.invalidate(localNowProvider);
    invalidatePrograms(ref);
    onFailed(
      missedDate == null
          ? "Today's workout changed. Check it and try again."
          : 'This day changed. Check it and try again.',
    );
    return;
  } on Object {
    startFailed();
    return;
  }
  await context.push<void>('/train/workout');
}
