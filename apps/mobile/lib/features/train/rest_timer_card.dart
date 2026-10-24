import 'dart:async';

import 'package:flutter/material.dart';

import '../workouts/domain/live_workout_engine.dart';

/// Display-only clock. Persisted UTC deadline is the source of truth.
/// Ticker runs only while visible and while a countdown is active.
class RestTimerCard extends StatefulWidget {
  const RestTimerCard({
    required this.checkpoint,
    required this.onStart,
    required this.onClear,
    required this.runningWorkout,
    super.key,
  });

  final WorkoutRecoveryCheckpoint checkpoint;
  final void Function(int seconds) onStart;
  final VoidCallback onClear;
  final bool runningWorkout;

  @override
  State<RestTimerCard> createState() => _RestTimerCardState();
}

class _RestTimerCardState extends State<RestTimerCard>
    with WidgetsBindingObserver {
  Timer? _ticker;
  DateTime _now = DateTime.now().toUtc();
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant RestTimerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _now = DateTime.now().toUtc();
    _syncTicker();
  }

  void _syncTicker() {
    final deadline = widget.checkpoint.restDeadlineUtcMs;
    final shouldTick = _foreground &&
        widget.checkpoint.restStatus == RestTimerStatus.running &&
        deadline != null &&
        deadline > _now.millisecondsSinceEpoch;
    if (!shouldTick) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now().toUtc());
      if (_now.millisecondsSinceEpoch >= deadline) {
        _ticker?.cancel();
        _ticker = null;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      setState(() => _now = DateTime.now().toUtc());
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.checkpoint;
    if (data.restStatus == RestTimerStatus.unknown) {
      return const Card(child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('Rest timer state is unsupported. Reload your workout.'),
      ));
    }
    final active = data.restStatus == RestTimerStatus.running;
    final paused = data.restStatus == RestTimerStatus.paused;
    final remainingMs = active
        ? ((data.restDeadlineUtcMs ?? 0) - _now.millisecondsSinceEpoch)
        : paused ? (data.restRemainingMsWhenPaused ?? 0) : 0;
    final seconds = remainingMs <= 0 ? 0 : (remainingMs / 1000).ceil();
    final minutes = seconds ~/ 60;
    final restSeconds = seconds % 60;
    final complete = active && seconds == 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.timer_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text('REST TIMER',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800))),
              if (active || paused)
                Text(complete ? 'REST COMPLETE' :
                    paused ? 'PAUSED' : 'COUNTING',
                  style: Theme.of(context).textTheme.labelSmall),
            ]),
            if (active || paused) ...[
              const SizedBox(height: 8),
              Text('$minutes:${restSeconds.toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
            ],
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (widget.runningWorkout)
                for (final duration in [60, 90, 120])
                  OutlinedButton(onPressed: () => widget.onStart(duration),
                    child: Text('${duration}s')),
              if (active || paused)
                TextButton.icon(onPressed: widget.onClear,
                  icon: const Icon(Icons.close),
                  label: const Text('Clear rest')),
            ]),
            if (!active && !paused)
              const Text('Finish a set to start rest, or choose a timer.'),
          ],
        ),
      ),
    );
  }
}
