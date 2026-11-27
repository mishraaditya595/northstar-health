import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/page_header.dart';
import '../application/live_watch_workout.dart';

/// The route of the live mirror page.
const liveWatchWorkoutRoute = '/train/watch-workout';

/// "Workout on your Apple Watch · Open", shown on Today and Train while a
/// workout the watch owns is live (or was, and is out of reach). Nothing
/// without one.
class LiveWatchWorkoutCard extends ConsumerWidget {
  const LiveWatchWorkoutCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveWatchWorkoutProvider);
    final workout = state.workout;
    if (workout == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NsListCard(
        icon: Icons.watch_outlined,
        title: 'Workout on your Apple Watch',
        subtitle: state.stale
            ? '${workout.name} · Apple Watch out of reach'
            : workout.name,
        trailing: TextButton(
          onPressed: () => context.push(liveWatchWorkoutRoute),
          child: const Text('Open'),
        ),
        onTap: () => context.push(liveWatchWorkoutRoute),
      ),
    );
  }
}
