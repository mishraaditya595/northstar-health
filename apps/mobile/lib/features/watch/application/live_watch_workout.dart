import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/ids/uuid_factory.dart';
import '../../account/account_auth_provider.dart';
import '../data/watch_live_link.dart';
import '../domain/live_watch_workout.dart';
import '../domain/watch_account_key.dart';
import '../domain/watch_message.dart';
import 'watch_sync_controller.dart' show watchMessageIdsProvider;

/// No message for this long and the state is stale: shown read-only.
const liveStaleAfter = Duration(seconds: 90);

/// A stale state is dropped after this long without a message.
const liveDropAfter = Duration(hours: 6);

/// A pending command is sent again this often while the link is up...
const liveResendEvery = Duration(seconds: 5);

/// ...and given up on after this long since it was first sent.
const liveGiveUpAfter = Duration(seconds: 30);

/// Where a command stands. A command that the watch listed as applied is gone.
enum LiveCommandPhase {
  /// Sent, not yet listed by the watch ("Saving…").
  pending,

  /// Not listed after [liveGiveUpAfter] ("Not saved on your watch"); can be retried.
  failed,

  /// The watch refused it; see [LiveCommand.reason].
  rejected,
}

@immutable
class LiveCommand {
  const LiveCommand({
    required this.id,
    required this.sessionId,
    required this.command,
    required this.json,
    required this.phase,
    required this.firstSentAt,
    required this.lastSentAt,
    this.setId,
    this.reason,
  });

  final String id;
  final String sessionId;
  final String command;

  /// The set this command is about, for the row that shows "Saving…".
  final String? setId;

  /// The exact message that is sent again, so its command id never changes.
  final String json;
  final LiveCommandPhase phase;
  final DateTime firstSentAt;
  final DateTime lastSentAt;
  final String? reason;

  LiveCommand _with({
    LiveCommandPhase? phase,
    DateTime? firstSentAt,
    DateTime? lastSentAt,
    String? reason,
  }) => LiveCommand(
    id: id,
    sessionId: sessionId,
    command: command,
    json: json,
    setId: setId,
    phase: phase ?? this.phase,
    firstSentAt: firstSentAt ?? this.firstSentAt,
    lastSentAt: lastSentAt ?? this.lastSentAt,
    reason: reason ?? this.reason,
  );
}

/// How a workout the page was following ended.
@immutable
class LiveWatchEnd {
  const LiveWatchEnd({required this.sessionId, required this.completed});

  final String sessionId;

  /// False when it was discarded.
  final bool completed;
}

@immutable
class LiveWatchState {
  const LiveWatchState({
    this.workout,
    this.stale = false,
    this.commands = const [],
    this.ended,
  });

  /// The workout on the watch, or null when none is live for this account.
  final LiveWatchWorkout? workout;

  /// No word from the watch for a while, or the link dropped: read-only.
  final bool stale;
  final List<LiveCommand> commands;

  /// Set when the workout that was shown just ended; cleared by the next one.
  final LiveWatchEnd? ended;

  /// A fresh workout the phone can control.
  bool get isLive => workout != null && !stale;

  List<LiveCommand> commandsForSet(String setId) => [
    for (final c in commands)
      if (c.setId == setId) c,
  ];

  /// True while any command about [setId] is waiting for the watch.
  bool isSaving(String setId) =>
      commandsForSet(setId).any((c) => c.phase == LiveCommandPhase.pending);

  LiveWatchState _copy({
    LiveWatchWorkout? workout,
    bool? stale,
    List<LiveCommand>? commands,
    LiveWatchEnd? ended,
    bool clearWorkout = false,
    bool clearEnded = false,
  }) => LiveWatchState(
    workout: clearWorkout ? null : (workout ?? this.workout),
    stale: stale ?? this.stale,
    commands: commands ?? this.commands,
    ended: clearEnded ? null : (ended ?? this.ended),
  );
}

/// Follows and controls a workout that runs on the Apple Watch. The watch owns
/// it: this controller keeps the last `session_state` in memory, sends
/// `session_command` messages, and shows a command as saved only when the
/// watch lists its id as applied. It never writes ObjectBox; the finished
/// workout arrives through the `completed_workout` import.
class LiveWatchWorkoutController extends Notifier<LiveWatchState> {
  late final WatchLiveLink _link;
  late final UuidFactory _ids;
  late final DateTime Function() _clock;
  Timer? _timer;
  DateTime? _lastReceived;
  String? _lastUser;
  final List<String> _ended = [];

  @override
  LiveWatchState build() {
    _link = ref.read(watchLiveLinkProvider);
    _ids = ref.read(watchMessageIdsProvider);
    _clock = ref.read(wallClockProvider);
    final auth = ref.read(accountAuthControllerProvider);
    _lastUser = auth?.userId;
    void onAuth() {
      final user = auth?.userId;
      if (user == _lastUser) return;
      _lastUser = user;
      _dropAll();
    }

    auth?.addListener(onAuth);
    final messages = _link.messages.listen(_onMessage);
    final disconnects = _link.disconnects.listen((_) => _onDisconnected());
    ref.onDispose(() {
      auth?.removeListener(onAuth);
      unawaited(messages.cancel());
      unawaited(disconnects.cancel());
      _timer?.cancel();
    });
    return const LiveWatchState();
  }

  String? get _accountKey {
    final user = _lastUser;
    return user == null ? null : watchAccountKey(user);
  }

  // MARK: Incoming

  void _onMessage(String json) {
    final WatchMessage message;
    try {
      message = WatchMessage.fromJson(jsonDecode(json) as Map<String, Object?>);
    } catch (_) {
      return;
    }
    if (message is! SessionState || message.owner != 'watch') return;
    // Another account's workout is never shown, and never answered.
    final key = _accountKey;
    if (key == null || message.accountKey != key) return;
    final sentAt = DateTime.parse(message.sentAtUtc).toUtc();
    final current = state.workout;
    if (current != null &&
        (sentAt.isBefore(current.sentAt) ||
            message.messageId.toLowerCase() ==
                current.messageId.toLowerCase())) {
      return;
    }
    final sessionId = message.sessionId.toLowerCase();
    if (_ended.contains(sessionId)) return;
    if (message.status == 'ended') {
      _remember(sessionId);
      if (current == null || current.sessionId.toLowerCase() == sessionId) {
        _lastReceived = null;
        state = LiveWatchState(
          ended: LiveWatchEnd(
            sessionId: message.sessionId,
            completed: message.endReason == 'completed',
          ),
        );
        _syncTimer();
      }
      return;
    }
    final workout = LiveWatchWorkout.fromState(message);
    _lastReceived = _clock();
    state = LiveWatchState(
      workout: workout,
      commands: _settle(workout, state.commands),
    );
    _syncTimer();
  }

  /// Keeps the commands of this session that the watch has not applied; a
  /// refused one carries its reason.
  List<LiveCommand> _settle(
    LiveWatchWorkout workout,
    List<LiveCommand> commands,
  ) => [
    for (final c in commands)
      if (c.sessionId.toLowerCase() == workout.sessionId.toLowerCase() &&
          !workout.appliedCommandIds.contains(c.id))
        if (workout.rejectedCommands[c.id] case final reason?)
          c._with(phase: LiveCommandPhase.rejected, reason: reason)
        else
          c,
  ];

  void _remember(String sessionId) {
    _ended.add(sessionId);
    if (_ended.length > 5) _ended.removeAt(0);
  }

  void _onDisconnected() {
    if (state.workout == null || state.stale) return;
    state = state._copy(stale: true);
  }

  void _dropAll() {
    _lastReceived = null;
    _ended.clear();
    state = const LiveWatchState();
    _syncTimer();
  }

  // MARK: Time

  void _syncTimer() {
    final needed = state.workout != null || state.commands.isNotEmpty;
    if (needed && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else if (!needed) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _tick() {
    final now = _clock();
    final received = _lastReceived;
    if (state.workout != null && received != null) {
      final quiet = now.difference(received);
      if (quiet >= liveDropAfter) {
        _dropAll();
        return;
      }
      if (!state.stale && quiet >= liveStaleAfter) {
        state = state._copy(stale: true);
      }
    }
    var changed = false;
    final next = <LiveCommand>[];
    for (final c in state.commands) {
      var command = c;
      if (c.phase == LiveCommandPhase.pending) {
        if (now.difference(c.firstSentAt) >= liveGiveUpAfter) {
          command = c._with(phase: LiveCommandPhase.failed);
          changed = true;
        } else if (!state.stale &&
            now.difference(c.lastSentAt) >= liveResendEvery) {
          unawaited(_link.sendCommand(c.json));
          command = c._with(lastSentAt: now);
          changed = true;
        }
      }
      next.add(command);
    }
    if (changed) state = state._copy(commands: next);
  }

  // MARK: Commands

  /// Sends a command to the watch. Null when no fresh workout is followed:
  /// nothing is ever sent for a stale state.
  LiveCommand? send(
    String command, {
    String? setId,
    Map<String, Object?>? set,
    int? restSeconds,
    String? exerciseId,
  }) {
    final key = _accountKey;
    final workout = state.workout;
    if (key == null || workout == null || state.stale) return null;
    final now = _clock();
    final commandId = _ids.newId().toLowerCase();
    final json = jsonEncode(
      SessionCommand(
        messageId: _ids.newId(),
        sentAtUtc: now.toUtc().toIso8601String(),
        accountKey: key,
        sessionId: workout.sessionId,
        commandId: commandId,
        command: command,
        set: set,
        restSeconds: restSeconds,
        exerciseId: exerciseId,
      ).toJson(),
    );
    final sent = LiveCommand(
      id: commandId,
      sessionId: workout.sessionId,
      command: command,
      setId: setId,
      json: json,
      phase: LiveCommandPhase.pending,
      firstSentAt: now,
      lastSentAt: now,
    );
    unawaited(_link.sendCommand(json));
    state = state._copy(commands: [...state.commands, sent]);
    _syncTimer();
    return sent;
  }

  /// Logs a planned set, or corrects a completed one; the watch turns both
  /// into the right event.
  LiveCommand? logSet(
    String setId, {
    int? reps,
    int? durationSeconds,
    int? loadGrams,
    num? rpe,
    String? inputUnit,
  }) {
    final workout = state.workout;
    final set = workout?.setById(setId);
    final exercise = workout?.exerciseOfSet(setId);
    if (workout == null || set == null || exercise == null) return null;
    return send(
      set.isCompleted ? 'correct_set' : 'log_set',
      setId: setId,
      set: {
        'set_id': set.setId,
        'exercise_id': exercise.exerciseId,
        'position': set.position,
        'kind': set.kind,
        'input_unit': inputUnit ?? set.inputUnit ?? 'kg',
        'reps': ?reps,
        'duration_seconds': ?durationSeconds,
        if (loadGrams != null && loadGrams > 0) 'load_grams': loadGrams,
        'rpe': ?rpe,
      },
    );
  }

  LiveCommand? skipSet(String setId) {
    final workout = state.workout;
    final set = workout?.setById(setId);
    final exercise = workout?.exerciseOfSet(setId);
    if (workout == null || set == null || exercise == null) return null;
    return send(
      'skip_set',
      setId: setId,
      set: {
        'set_id': set.setId,
        'exercise_id': exercise.exerciseId,
        'position': set.position,
        'kind': set.kind,
        'input_unit': set.inputUnit ?? 'kg',
      },
    );
  }

  LiveCommand? addSet(String exerciseId) =>
      send('add_set', exerciseId: exerciseId);
  LiveCommand? startRest(int seconds) =>
      send('start_rest', restSeconds: seconds);
  LiveCommand? clearRest() => send('clear_rest');
  LiveCommand? pause() => send('pause');
  LiveCommand? resume() => send('resume');
  LiveCommand? finish() => send('finish');
  LiveCommand? discard() => send('discard');

  /// Tries a failed command again with the same command id, as a new attempt.
  void retry(String commandId) {
    if (state.stale) return;
    final now = _clock();
    var found = false;
    final next = <LiveCommand>[];
    for (final c in state.commands) {
      if (c.id == commandId && c.phase == LiveCommandPhase.failed) {
        found = true;
        unawaited(_link.sendCommand(c.json));
        next.add(
          c._with(
            phase: LiveCommandPhase.pending,
            firstSentAt: now,
            lastSentAt: now,
          ),
        );
      } else {
        next.add(c);
      }
    }
    if (found) state = state._copy(commands: next);
  }

  /// Hides a refused or failed command.
  void dismiss(String commandId) {
    state = state._copy(
      commands: [
        for (final c in state.commands)
          if (c.id != commandId) c,
      ],
    );
    _syncTimer();
  }

  /// The page showed how the workout ended.
  void acknowledgeEnd() {
    if (state.ended != null) state = state._copy(clearEnded: true);
  }
}

final liveWatchWorkoutProvider =
    NotifierProvider<LiveWatchWorkoutController, LiveWatchState>(
      LiveWatchWorkoutController.new,
    );
