import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../progress/workout_history_state.dart';
import '../../workouts/domain/workout_models.dart';
import '../domain/daily_series.dart';
import '../domain/training_insights.dart';
import 'health_overview.dart';
import 'health_summary_controller.dart';

const _windowDays = 30;

/// Joins the overview's sleep and resting heart rate with completed workout
/// history. Derived in memory only; nothing is written anywhere.
class TrainingInsights {
  const TrainingInsights({this.sleep, this.restingHr});

  final SleepAfterTraining? sleep;
  final RestingHrAfterHard? restingHr;
}

/// Null unless the overview is loaded for the current owner and the history
/// is loaded.
final trainingInsightsProvider = Provider.autoDispose<TrainingInsights?>((ref) {
  final overview = ref.watch(healthOverviewProvider).value;
  final history = ref.watch(completedWorkoutHistoryProvider).value;
  final owner = ref.watch(healthOwnerIdProvider);
  if (overview == null || history == null || overview.ownerId != owner) {
    return null;
  }

  final end = dayOf(overview.readAt);
  final start = DateTime(end.year, end.month, end.day - _windowDays);
  final perDay = <DateTime, int>{};
  for (final s in history.sessions) {
    final at = s.completedAtUtc;
    if (s.status != WorkoutStatus.completed || at == null) continue;
    final day = dayOf(at.toLocal());
    if (day.isBefore(start) || day.isAfter(end)) continue;
    final sets = s.sets
        .where(
          (x) =>
              x.status == WorkoutSetStatus.completed &&
              x.kind == WorkoutSetKind.working,
        )
        .length;
    perDay.update(day, (v) => v + sets, ifAbsent: () => sets);
  }
  final training = <TrainingDay>[
    for (final e in perDay.entries)
      if (e.value > 0) (day: e.key, workingSets: e.value),
  ];

  return TrainingInsights(
    sleep: switch (overview.sleep) {
      SectionData(:final value) => sleepAfterTraining(value.nights, training),
      SectionGap() => null,
    },
    restingHr: switch (overview.heart) {
      SectionData(:final value) => restingHrAfterHardSessions(
        value.restingHrDaily,
        training,
      ),
      SectionGap() => null,
    },
  );
});
