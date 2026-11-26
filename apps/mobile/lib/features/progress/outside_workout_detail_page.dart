import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/page_header.dart';
import '../health/application/health_overview.dart';
import '../health/application/health_summary_controller.dart';
import '../health/application/workout_heart_rate.dart';
import '../health/domain/health_types.dart';
import '../health/domain/metric_explanations.dart';
import '../health/domain/outside_workouts.dart';
import '../health/health_format.dart';
import '../health/widgets/detail_layout.dart';
import '../health/widgets/health_card_frame.dart';
import '../health/widgets/metric_info_sheet.dart';

/// Read-only detail of a workout another app saved to the health platform.
/// Looked up in the in-memory overview; never stored.
class OutsideWorkoutDetailPage extends ConsumerWidget {
  const OutsideWorkoutDetailPage({required this.workoutId, super.key});

  final String workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(healthOverviewProvider).value;
    final owner = ref.watch(healthOwnerIdProvider);
    OutsideWorkout? workout;
    if (overview != null && overview.ownerId == owner) {
      if (overview.workouts case SectionData(:final value)) {
        for (final w in value.outside) {
          if (w.id == workoutId) workout = w;
        }
      }
    }
    return Scaffold(
      appBar: AppBar(
        leading: const NsBackButton(),
        title: Text(
          workout == null ? 'Workout' : outsideWorkoutName(workout.kind),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: workout == null
              ? const Center(
                  child: Text('This workout is no longer available.'),
                )
              : _Detail(workout: workout, platform: overview!.platform),
        ),
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.workout, required this.platform});

  final OutsideWorkout workout;
  final HealthPlatformKind platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final start = workout.start.toLocal();
    final end = workout.end.toLocal();
    final hr = ref
        .watch(
          workoutAverageHrProvider((start: workout.start, end: workout.end)),
        )
        .value;
    final km = workout.distanceMeters;
    final kcal = workout.activeKcal;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        DetailPanel(
          title: 'Workout details',
          info: metricInfoButton(
            context,
            MetricKey.otherAppWorkouts,
            platform: platform,
          ),
          children: [
            DetailRow('Date', formatHealthDate(start)),
            DetailRow('Time', formatTimeRange(start, end)),
            DetailRow('Duration', '${workout.minutes} min'),
            if (km != null)
              DetailRow('Distance', '${(km / 1000).toStringAsFixed(1)} km'),
            if (kcal != null)
              DetailRow('Active calories', '${kcal.round()} kcal'),
            DetailRow(
              'Average heart rate',
              hr == null ? '—' : '${hr.round()} bpm',
            ),
            DetailRow('Source', workout.source),
          ],
        ),
        HealthCaption(
          'Read from ${healthPlatformName(platform)}. '
          'Read only and not saved in BeyondRep.',
        ),
      ],
    );
  }
}
