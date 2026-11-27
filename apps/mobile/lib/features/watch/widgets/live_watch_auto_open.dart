import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/live_watch_workout.dart';
import 'live_watch_workout_card.dart';

/// Session ids the mirror page was already opened for, so a workout opens it
/// once and never again after the person leaves it.
final liveWatchOpenedSessionsProvider = Provider<Set<String>>((ref) => {});

/// True, after opening the mirror page, when a fresh workout on the Apple
/// Watch is live. The Start buttons call this first: while the watch owns a
/// workout the phone does not start a second one.
bool openLiveWatchWorkoutInstead(BuildContext context, WidgetRef ref) {
  final state = ref.read(liveWatchWorkoutProvider);
  if (!state.isLive) return false;
  context.push(liveWatchWorkoutRoute);
  return true;
}

/// Opens the mirror page when the app comes to the foreground, or a state
/// arrives, with a fresh watch workout for this account that was not opened
/// yet. It never takes over the screen of a workout being logged on the phone.
class LiveWatchAutoOpen extends ConsumerStatefulWidget {
  const LiveWatchAutoOpen({
    required this.location,
    required this.child,
    super.key,
  });

  /// The current route path.
  final String location;
  final Widget child;

  @override
  ConsumerState<LiveWatchAutoOpen> createState() => _LiveWatchAutoOpenState();
}

class _LiveWatchAutoOpenState extends ConsumerState<LiveWatchAutoOpen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _maybeOpen);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpen());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _maybeOpen() {
    if (!mounted) return;
    final state = ref.read(liveWatchWorkoutProvider);
    final workout = state.workout;
    if (workout == null || state.stale) return;
    final opened = ref.read(liveWatchOpenedSessionsProvider);
    if (opened.contains(workout.sessionId)) return;
    if (widget.location == liveWatchWorkoutRoute) {
      opened.add(workout.sessionId);
      return;
    }
    // Logging a set on the phone must not be interrupted.
    if (widget.location == '/train/workout') return;
    opened.add(workout.sessionId);
    context.push(liveWatchWorkoutRoute);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(liveWatchWorkoutProvider, (_, _) => _maybeOpen());
    return widget.child;
  }
}
