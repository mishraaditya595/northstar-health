import 'package:flutter/foundation.dart';

import 'watch_message.dart';

/// One set of a workout running on the watch, as the watch last reported it.
@immutable
class LiveSet {
  const LiveSet({
    required this.setId,
    required this.position,
    required this.kind,
    required this.status,
    this.inputUnit,
    this.reps,
    this.durationSeconds,
    this.loadGrams,
    this.rpe,
  });

  final String setId;
  final int position;

  /// `working` or `warmup`.
  final String kind;

  /// `planned`, `completed` or `skipped`. A planned set's values are its
  /// targets, so the phone can prefill them.
  final String status;
  final String? inputUnit;
  final int? reps;
  final int? durationSeconds;
  final int? loadGrams;
  final num? rpe;

  bool get isCompleted => status == 'completed';
  bool get isSkipped => status == 'skipped';
  bool get isPlanned => status == 'planned';
  bool get isWarmup => kind == 'warmup';
}

@immutable
class LiveExercise {
  const LiveExercise({
    required this.exerciseId,
    required this.name,
    required this.kind,
    required this.sets,
  });

  final String exerciseId;
  final String name;

  /// `reps` or `duration`.
  final String kind;
  final List<LiveSet> sets;

  bool get isTimed => kind == 'duration';
}

/// A workout the Apple Watch owns, mirrored in memory only. The phone never
/// stores it: the finished workout arrives later as a `completed_workout`.
@immutable
class LiveWatchWorkout {
  const LiveWatchWorkout({
    required this.sessionId,
    required this.messageId,
    required this.sentAt,
    required this.name,
    required this.status,
    required this.startedAt,
    required this.lastSequence,
    required this.exercises,
    this.pausedAt,
    this.pausedSeconds = 0,
    this.currentSetId,
    this.restDeadline,
    this.appliedCommandIds = const {},
    this.rejectedCommands = const {},
  });

  /// Reads a validated `session_state` the watch owns. The caller has already
  /// checked the account key.
  factory LiveWatchWorkout.fromState(SessionState s) => LiveWatchWorkout(
    sessionId: s.sessionId,
    messageId: s.messageId,
    sentAt: DateTime.parse(s.sentAtUtc).toUtc(),
    name: s.name,
    status: s.status,
    startedAt: DateTime.parse(s.startedAtUtc).toUtc(),
    lastSequence: s.lastSequence,
    pausedAt: s.pausedAtUtc == null
        ? null
        : DateTime.parse(s.pausedAtUtc!).toUtc(),
    pausedSeconds: s.pausedSeconds ?? 0,
    currentSetId: s.currentSetId,
    restDeadline: s.restDeadlineUtc == null
        ? null
        : DateTime.parse(s.restDeadlineUtc!).toUtc(),
    appliedCommandIds: {for (final id in s.appliedCommandIds) id.toLowerCase()},
    rejectedCommands: {
      for (final r in s.rejectedCommands) r.commandId.toLowerCase(): r.reason,
    },
    exercises: [
      for (final raw in s.exercises)
        _exercise(Map<String, Object?>.from(raw! as Map)),
    ],
  );

  static LiveExercise _exercise(Map<String, Object?> e) => LiveExercise(
    exerciseId: e['exercise_id']! as String,
    name: e['name']! as String,
    kind: e['kind']! as String,
    sets: [
      for (final raw in e['sets']! as List)
        _set(Map<String, Object?>.from(raw as Map)),
    ],
  );

  static LiveSet _set(Map<String, Object?> s) => LiveSet(
    setId: s['set_id']! as String,
    position: (s['position']! as num).toInt(),
    kind: s['kind']! as String,
    status: s['status']! as String,
    inputUnit: s['input_unit'] as String?,
    reps: (s['reps'] as num?)?.toInt(),
    durationSeconds: (s['duration_seconds'] as num?)?.toInt(),
    loadGrams: (s['load_grams'] as num?)?.toInt(),
    rpe: s['rpe'] as num?,
  );

  final String sessionId;

  /// Of the state message, so a duplicate delivery is ignored.
  final String messageId;
  final DateTime sentAt;
  final String name;

  /// `active` or `paused` (an ended state is never kept).
  final String status;
  final DateTime startedAt;
  final int lastSequence;
  final DateTime? pausedAt;

  /// The total of earlier pauses.
  final int pausedSeconds;
  final String? currentSetId;
  final DateTime? restDeadline;
  final Set<String> appliedCommandIds;

  /// Command id to the watch's reason.
  final Map<String, String> rejectedCommands;
  final List<LiveExercise> exercises;

  bool get isPaused => status == 'paused';

  /// Time on the clock: since the start, minus earlier pauses and a running one.
  Duration elapsed(DateTime now) {
    final running = pausedAt == null
        ? Duration.zero
        : now.difference(pausedAt!).isNegative
        ? Duration.zero
        : now.difference(pausedAt!);
    final total =
        now.difference(startedAt) - Duration(seconds: pausedSeconds) - running;
    return total.isNegative ? Duration.zero : total;
  }

  /// Time left of the rest, or null when no rest is running.
  Duration? restRemaining(DateTime now) {
    final deadline = restDeadline;
    if (deadline == null || isPaused) return null;
    final left = deadline.difference(now);
    return left > Duration.zero ? left : null;
  }

  LiveSet? setById(String setId) {
    for (final e in exercises) {
      for (final s in e.sets) {
        if (s.setId == setId) return s;
      }
    }
    return null;
  }

  LiveExercise? exerciseOfSet(String setId) {
    for (final e in exercises) {
      if (e.sets.any((s) => s.setId == setId)) return e;
    }
    return null;
  }
}
