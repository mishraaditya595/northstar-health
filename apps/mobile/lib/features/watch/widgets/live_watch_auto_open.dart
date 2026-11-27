import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../account/account_auth_provider.dart';
import '../application/live_watch_workout.dart';
import 'live_watch_workout_card.dart';

/// Session ids the mirror page was already opened for, so a workout opens it
/// once and never again after the person leaves it.
/// Forgotten when the account changes.
final liveWatchOpenedSessionsProvider = Provider<Set<String>>((ref) {
  final opened = <String>{};
  final auth = ref.read(accountAuthControllerProvider);
  var user = auth?.userId;
  void onAuth() {
    if (auth?.userId == user) return;
    user = auth?.userId;
    opened.clear();
  }

  auth?.addListener(onAuth);
  ref.onDispose(() => auth?.removeListener(onAuth));
  return opened;
});

/// True, after opening the mirror page, when a fresh workout on the Apple
/// Watch is live. The Start buttons call this first: while the watch owns a
/// workout the phone does not start a second one.
bool openLiveWatchWorkoutInstead(BuildContext context, WidgetRef ref) {
  final state = ref.read(liveWatchWorkoutProvider);
  if (!state.isLive) return false;
  context.push(liveWatchWorkoutRoute);
  return true;
}

/// Opens the mirror page once per foreground: when the app comes to the
/// foreground with a fresh watch workout for this account that was not opened
/// yet, or on the first fresh state that arrives after that. Later states in
/// the same foreground never open it (the Train card does). It never takes
/// over a workout being logged on the phone, a dialog or a bottom sheet.
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

  /// True from the app coming to the foreground until it opened the page or
  /// saw its first fresh state.
  bool _armed = true;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _armed = true;
        _maybeOpen();
      },
    );
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
    if (workout == null || state.stale || !_armed) return;
    final opened = ref.read(liveWatchOpenedSessionsProvider);
    if (opened.contains(workout.sessionId)) {
      _armed = false;
      return;
    }
    if (widget.location == liveWatchWorkoutRoute) {
      opened.add(workout.sessionId);
      _armed = false;
      return;
    }
    // Logging a set on the phone must not be interrupted.
    if (widget.location == '/train/workout') return;
    // A dialog or bottom sheet is above this screen: not now, the next state
    // (or coming back to the foreground) tries again.
    if (ModalRoute.of(context)?.isCurrent == false) return;
    opened.add(workout.sessionId);
    _armed = false;
    context.push(liveWatchWorkoutRoute);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(liveWatchWorkoutProvider, (_, _) => _maybeOpen());
    return widget.child;
  }
}
