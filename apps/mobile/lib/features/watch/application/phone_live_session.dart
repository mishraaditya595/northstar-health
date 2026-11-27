import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/ids/uuid_factory.dart';
import '../../../core/units/load_units.dart';
import '../../account/account_auth_provider.dart';
import '../../programs/application/program_providers.dart';
import '../../progress/workout_history_state.dart';
import '../../sync/workout_upload_coordinator.dart';
import '../../train/active_workout_state.dart';
import '../../workouts/data/objectbox_workout_library_repository.dart';
import '../../workouts/data/objectbox_workout_outbox.dart';
import '../../workouts/data/objectbox_workout_repository.dart';
import '../../workouts/domain/live_workout_engine.dart';
import '../../workouts/domain/workout_library_models.dart';
import '../../workouts/domain/workout_models.dart';
import '../../workouts/domain/workout_repository.dart';
import '../data/watch_live_link.dart';
import '../domain/watch_status.dart';
import '../domain/watch_account_key.dart';
import '../domain/watch_message.dart';
import 'live_watch_workout.dart';
import 'watch_status_provider.dart';
import 'watch_sync_controller.dart' show watchMessageIdsProvider;

/// The phone broadcasts its workout this often while a watch is linked.
const phoneStateEvery = Duration(seconds: 30);

/// Applied command ids kept in memory per session (the state echoes 20).
const _appliedMemory = 50;

/// An ended state is sent again for this long, so a watch that was out of
/// reach for a moment still learns how the workout ended.
const _endedResendFor = Duration(minutes: 2);

/// Whole milliseconds: the watch's date parser is only sure of three
/// fractional digits.
String _utc(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
  t.millisecondsSinceEpoch,
  isUtc: true,
).toIso8601String();

String _cap(String text, int max) {
  final runes = text.runes;
  return runes.length <= max ? text : String.fromCharCodes(runes.take(max));
}

/// Turns the phone's active workout into a `session_state` with owner
/// `phone`. Pure: ids, time and the timed-exercise rule are passed in. The
/// workout's ObjectBox revision is its `last_sequence`. Nothing here is a
/// health value.
SessionState buildPhoneSessionState({
  required String accountKey,
  required ActiveWorkoutView view,
  required bool Function(
    WorkoutExerciseRecord exercise,
    List<WorkoutSetRecord> sets,
  )
  isTimed,
  required DateTime nowUtc,
  required String messageId,
  DateTime? pausedAt,
  int pausedSeconds = 0,
  List<String> appliedCommandIds = const [],
  List<({String commandId, String reason})> rejectedCommands = const [],
  String? endReason,
}) {
  final session = view.session;
  final paused = session.status == WorkoutStatus.paused;
  final exercises = [...session.exercises]
    ..sort((a, b) => a.position.compareTo(b.position));
  final byExercise = <String, List<WorkoutSetRecord>>{
    for (final e in exercises)
      e.uuid: [
        for (final s in session.sets)
          if (s.exerciseUuid == e.uuid) s,
      ]..sort((a, b) => a.position.compareTo(b.position)),
  };
  String? current;
  for (final e in exercises) {
    for (final s in byExercise[e.uuid]!) {
      if (s.status == WorkoutSetStatus.planned) {
        current ??= s.uuid;
      }
    }
  }
  final deadlineMs = view.checkpoint.restDeadlineUtcMs;
  final restRunning =
      !paused &&
      endReason == null &&
      view.checkpoint.restStatus == RestTimerStatus.running &&
      deadlineMs != null;
  final applied = appliedCommandIds.length > 20
      ? appliedCommandIds.sublist(appliedCommandIds.length - 20)
      : appliedCommandIds;
  final rejected = rejectedCommands.length > 20
      ? rejectedCommands.sublist(rejectedCommands.length - 20)
      : rejectedCommands;
  return SessionState(
    messageId: messageId,
    sentAtUtc: _utc(nowUtc),
    accountKey: accountKey,
    sessionId: session.uuid,
    owner: 'phone',
    status: endReason != null
        ? 'ended'
        : paused
        ? 'paused'
        : 'active',
    name: _cap(session.name, 120),
    startedAtUtc: _utc(session.startedAtUtc),
    lastSequence: session.revision,
    currentSetId: endReason == null ? current : null,
    restDeadlineUtc: restRunning
        ? _utc(DateTime.fromMillisecondsSinceEpoch(deadlineMs, isUtc: true))
        : null,
    endReason: endReason,
    pausedAtUtc: paused && endReason == null && pausedAt != null
        ? _utc(pausedAt)
        : null,
    pausedSeconds: pausedSeconds > 0 ? pausedSeconds : null,
    appliedCommandIds: applied,
    rejectedCommands: rejected,
    exercises: [
      for (final e in exercises.take(120))
        {
          'exercise_id': _cap(e.uuid, 128),
          'name': _cap(e.nameSnapshot, 120),
          'kind': isTimed(e, byExercise[e.uuid]!) ? 'duration' : 'reps',
          'sets': [
            for (final s in byExercise[e.uuid]!.take(300))
              _setJson(s, e.restSeconds),
          ],
        },
    ],
  );
}

Map<String, Object?> _setJson(WorkoutSetRecord s, int? exerciseRest) {
  final status = switch (s.status) {
    WorkoutSetStatus.completed => 'completed',
    WorkoutSetStatus.skipped => 'skipped',
    _ => 'planned',
  };
  final unit = s.inputUnit == LoadUnit.lb ? 'lb' : 'kg';
  return {
    'set_id': s.uuid,
    'position': s.position,
    'kind': s.kind == WorkoutSetKind.warmup ? 'warmup' : 'working',
    'status': status,
    // A skipped set has a kind and no values.
    if (status != 'skipped') ...{
      'input_unit': unit,
      if (s.reps != null && (status == 'completed' || s.reps! > 0))
        'reps': s.reps,
      if (s.durationSeconds != null && s.durationSeconds! > 0)
        'duration_seconds': s.durationSeconds,
      if (s.loadGrams != null && s.loadGrams! > 0) 'load_grams': s.loadGrams,
      if (s.rpe != null) 'rpe': s.rpe,
    },
    if (status == 'planned' &&
        exerciseRest != null &&
        exerciseRest >= 1 &&
        exerciseRest <= 3600)
      'rest_seconds': exerciseRest,
  };
}

@immutable
class PhoneLiveSessionState {
  const PhoneLiveSessionState({this.pendingDiscard = false});

  /// The watch asked to discard the workout and the phone must confirm.
  final bool pendingDiscard;
}

/// Broadcasts the phone's own workout to the watch and applies the watch's
/// `session_command` messages to it. The ObjectBox engine stays the only
/// authority: every command goes through [WorkoutActions], nothing is stored
/// here, and a command is shown as applied only when its effect committed.
///
/// Idempotency is by effect (a set already holding the same values, a session
/// already paused, a rest not running), so a phone that lost the in-memory
/// command ids can take any command again. The ids of the newest [_appliedMemory]
/// commands are kept per session so `start_rest` and `add_set` are not repeated.
class PhoneLiveSessionController extends Notifier<PhoneLiveSessionState> {
  late final WatchLiveLink _link;
  late final UuidFactory _ids;
  late final DateTime Function() _clock;
  Timer? _timer;
  String? _lastUser;

  /// The last workout seen, to say how it ended.
  ActiveWorkoutView? _lastView;
  bool _seenNull = false;

  /// Memory of the session below.
  String? _sessionId;
  final List<String> _applied = [];
  final List<({String commandId, String reason})> _rejected = [];
  DateTime? _pausedAt;
  int _pausedSeconds = 0;
  String? _lastSignature;
  final Set<String> _launched = {};

  /// The ended state and when to stop sending it.
  String? _endedJson;
  DateTime? _endedUntil;

  /// The discard the watch asked for, until the phone answers.
  String? _discardId;
  String? _discardSession;

  @override
  PhoneLiveSessionState build() {
    _link = ref.read(watchLiveLinkProvider);
    _ids = ref.read(watchMessageIdsProvider);
    _clock = ref.read(wallClockProvider);
    final auth = ref.read(accountAuthControllerProvider);
    _lastUser = auth?.userId;
    void onAuth() {
      final user = auth?.userId;
      if (user == _lastUser) return;
      _lastUser = user;
      _forgetAll();
    }

    auth?.addListener(onAuth);
    final messages = _link.messages.listen(_onMessage);
    ref.onDispose(() {
      auth?.removeListener(onAuth);
      unawaited(messages.cancel());
      _timer?.cancel();
    });
    ref.listen<AsyncValue<ActiveWorkoutView?>>(
      activeWorkoutProvider,
      (_, next) => _onActive(next.value),
      fireImmediately: true,
    );
    // The watch app was just installed or paired: tell it what is running.
    ref.listen<bool>(
      watchLinkStateProvider.select((s) => _isLinked(s.device)),
      (was, now) {
        if (now && was != true) _broadcast(force: true);
      },
    );
    return const PhoneLiveSessionState();
  }

  static bool _isLinked(WatchDeviceStatus d) =>
      d.supported && d.paired && d.installed;

  bool get _linked => _isLinked(ref.read(watchLinkStateProvider).device);

  String? get _accountKey {
    final user = _lastUser;
    return user == null ? null : watchAccountKey(user);
  }

  /// No state while a workout the watch owns is live: one owner at a time.
  bool get _watchOwnsAWorkout =>
      ref.read(liveWatchWorkoutProvider).workout != null;

  bool get _canSend => _accountKey != null && _linked && !_watchOwnsAWorkout;

  void _forgetAll() {
    _lastView = null;
    _sessionId = null;
    _applied.clear();
    _rejected.clear();
    _pausedAt = null;
    _pausedSeconds = 0;
    _lastSignature = null;
    _endedJson = null;
    _endedUntil = null;
    _discardId = null;
    _discardSession = null;
    _launched.clear();
    if (state.pendingDiscard) state = const PhoneLiveSessionState();
    _syncTimer();
  }

  // MARK: The phone's workout

  void _onActive(ActiveWorkoutView? view) {
    if (view == null) {
      final last = _lastView;
      _lastView = null;
      _seenNull = true;
      if (last != null) _onEnded(last);
      _syncTimer();
      return;
    }
    final newSession = view.session.uuid != _sessionId;
    if (newSession) {
      _sessionId = view.session.uuid;
      _applied.clear();
      _rejected.clear();
      _pausedAt = null;
      _pausedSeconds = 0;
      _lastSignature = null;
      _endedJson = null;
      _endedUntil = null;
      // A workout that was already there when the app started (or came back
      // after a relaunch) is broadcast but never launches the watch app.
      if (_seenNull && view.session.status == WorkoutStatus.inProgress) {
        if (_launched.add(view.session.uuid) && _canSend) {
          unawaited(_link.startWatchApp());
        }
      }
    }
    _lastView = view;
    _syncTimer();
    _broadcast();
  }

  /// The workout is gone from the active slot: finished or discarded.
  void _onEnded(ActiveWorkoutView last) {
    final stored = _storedStatus(last.session.uuid);
    final reason = switch (stored) {
      WorkoutStatus.completed => 'completed',
      WorkoutStatus.discarded => 'discarded',
      _ => null,
    };
    if (reason == null) return;
    _trackPause(last);
    if (_accountKey == null) return;
    final json = _stateJson(last, endReason: reason);
    _endedJson = json;
    _endedUntil = _clock().add(_endedResendFor);
    _lastSignature = null;
    if (_canSend) unawaited(_link.sendState(json));
  }

  WorkoutStatus? _storedStatus(String uuid) {
    try {
      return ref.read(workoutRepositoryProvider).getSession(uuid)?.status;
    } catch (_) {
      return null;
    }
  }

  /// Pause time lives in memory: the engine records none. After a relaunch the
  /// running pause starts counting again from the first state built.
  void _trackPause(ActiveWorkoutView view) {
    final now = _clock();
    if (view.session.status == WorkoutStatus.paused) {
      _pausedAt ??= now;
    } else if (_pausedAt != null) {
      _pausedSeconds += now.difference(_pausedAt!).inSeconds;
      _pausedAt = null;
    }
  }

  bool _isTimed(WorkoutExerciseRecord exercise, List<WorkoutSetRecord> sets) {
    Map<String, ExerciseRecord> definitions = const {};
    try {
      definitions = {
        for (final e
            in ref
                .read(workoutLibraryRepositoryProvider)
                .listExercises(includeArchived: true))
          e.uuid: e,
      };
    } catch (_) {
      // The sets themselves decide.
    }
    final definition = definitions[exercise.definitionUuid];
    if (definition != null) return definition.inputMode == 'duration';
    return sets.any((s) => s.durationSeconds != null);
  }

  String _stateJson(ActiveWorkoutView view, {String? endReason}) {
    final key = _accountKey!;
    final state = buildPhoneSessionState(
      accountKey: key,
      view: view,
      isTimed: _isTimed,
      nowUtc: _clock().toUtc(),
      messageId: _ids.newId(),
      pausedAt: _pausedAt,
      pausedSeconds: _pausedSeconds,
      appliedCommandIds: List.unmodifiable(_applied),
      rejectedCommands: List.unmodifiable(_rejected),
      endReason: endReason,
    );
    return jsonEncode(state.toJson());
  }

  /// Sends the state when a watch is linked. Unchanged states are skipped
  /// unless [force] (the 30 s beat, a join, a repeated command).
  void _broadcast({bool force = false}) {
    final view = _lastView;
    if (view == null || !_canSend) return;
    _trackPause(view);
    final json = _stateJson(view);
    // Message id and send time change on every build; the rest is the state.
    final body = (jsonDecode(json) as Map<String, Object?>)['body'];
    final signature = jsonEncode(body);
    if (!force && signature == _lastSignature) return;
    _lastSignature = signature;
    unawaited(_link.sendState(json));
  }

  void _syncTimer() {
    final needed = _lastView != null || _endedJson != null;
    if (needed && _timer == null) {
      _timer = Timer.periodic(phoneStateEvery, (_) => _tick());
    } else if (!needed) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _tick() {
    final ended = _endedJson;
    if (ended != null) {
      final until = _endedUntil;
      if (until == null || !_clock().isBefore(until)) {
        _endedJson = null;
        _endedUntil = null;
        _syncTimer();
        return;
      }
      if (_canSend) unawaited(_link.sendState(ended));
    }
    if (_lastView != null) {
      // Pick up changes the page made without a provider notification.
      ref.invalidate(activeWorkoutProvider);
      // A workout that ended meanwhile is handled by the provider listener.
      final value = ref.read(activeWorkoutProvider).value;
      if (value == null) return;
      _lastView = value;
      _broadcast(force: true);
    }
  }

  // MARK: Opening the watch app

  /// The "Open on Apple Watch" action: launches the watch app for the running
  /// workout and sends its state. Silent when it cannot.
  Future<void> openOnWatch() async {
    if (!_linked) return;
    try {
      await _link.startWatchApp();
    } catch (_) {
      // The workout goes on as before.
    }
    _broadcast(force: true);
  }

  // MARK: Incoming

  void _onMessage(String json) {
    final WatchMessage message;
    try {
      message = WatchMessage.fromJson(jsonDecode(json) as Map<String, Object?>);
    } catch (_) {
      return;
    }
    final key = _accountKey;
    if (key == null || message.accountKey != key) return;
    if (message is JoinMessage) {
      final view = _fresh();
      if (view != null &&
          view.session.uuid.toLowerCase() == message.sessionId.toLowerCase()) {
        _broadcast(force: true);
      }
    } else if (message is SessionCommand) {
      _onCommand(message);
    }
  }

  ActiveWorkoutView? _fresh() {
    ref.invalidate(activeWorkoutProvider);
    final value = ref.read(activeWorkoutProvider).value;
    if (value != null) _lastView = value;
    return value;
  }

  void _onCommand(SessionCommand c) {
    final view = _fresh();
    if (view == null ||
        view.session.uuid.toLowerCase() != c.sessionId.toLowerCase()) {
      return;
    }
    final id = c.commandId.toLowerCase();
    if (_applied.contains(id) || _rejected.any((r) => r.commandId == id)) {
      // Said again: the watch did not see the answer.
      _broadcast(force: true);
      return;
    }
    if (c.command == 'discard') {
      if (_discardId != null) return;
      _discardId = id;
      _discardSession = view.session.uuid;
      state = const PhoneLiveSessionState(pendingDiscard: true);
      return;
    }
    _settle(id, _apply(view, c));
  }

  /// The phone's answer to a discard the watch asked for.
  void resolveDiscard(bool confirmed) {
    final id = _discardId;
    final sessionId = _discardSession;
    _discardId = null;
    _discardSession = null;
    if (state.pendingDiscard) state = const PhoneLiveSessionState();
    if (id == null || sessionId == null) return;
    final view = _fresh();
    if (view == null || view.session.uuid != sessionId) return;
    if (!confirmed) {
      _settle(id, 'not_allowed');
      return;
    }
    _settle(
      id,
      _run(() {
        ref.read(workoutActionsProvider).discard(view.session);
        return null;
      }),
    );
  }

  /// Records the outcome (null applied, else a reject reason), refreshes the
  /// phone's own screens and sends the state with the outcome in it.
  void _settle(String id, String? rejection) {
    if (rejection == null) {
      _applied.add(id);
      if (_applied.length > _appliedMemory) _applied.removeAt(0);
    } else if (rejection != 'transient') {
      _rejected.add((commandId: id, reason: rejection));
      if (_rejected.length > 20) _rejected.removeAt(0);
    }
    ref.invalidate(activeWorkoutProvider);
    ref.invalidate(programWeekProvider);
    final value = ref.read(activeWorkoutProvider).value;
    if (value == null) {
      // The workout ended: the page's own finish and discard refresh these.
      ref.invalidate(completedWorkoutHistoryProvider);
      ref.invalidate(blockedWorkoutCountProvider);
      ref.read(workoutUploadKickProvider)?.call();
      final last = _lastView;
      _lastView = null;
      if (last != null) {
        _seenNull = true;
        _onEnded(last);
        _syncTimer();
      }
      return;
    }
    _lastView = value;
    _broadcast(force: true);
  }

  /// Runs one change. Null: applied. A reason: refused. `transient`: it did
  /// not commit and says nothing, so the watch sends it again.
  String? _run(String? Function() change) {
    try {
      return change();
    } on ArgumentError {
      return 'invalid_values';
    } on StateError {
      return 'not_allowed';
    } on WorkoutRevisionConflict {
      return 'not_allowed';
    } catch (_) {
      return 'transient';
    }
  }

  String? _apply(ActiveWorkoutView view, SessionCommand c) {
    final actions = ref.read(workoutActionsProvider);
    final session = view.session;
    final checkpoint = view.checkpoint;
    final paused = session.status == WorkoutStatus.paused;
    WorkoutSetRecord? setOf(String? id) {
      for (final s in session.sets) {
        if (s.uuid == id) return s;
      }
      return null;
    }

    switch (c.command) {
      case 'log_set':
      case 'correct_set':
        final raw = c.set;
        final stored = setOf(raw?['set_id'] as String?);
        if (raw == null || stored == null) return 'unknown_set';
        final reps = (raw['reps'] as num?)?.toInt();
        final seconds = (raw['duration_seconds'] as num?)?.toInt();
        final load = (raw['load_grams'] as num?)?.toInt();
        final rpe = (raw['rpe'] as num?)?.toDouble();
        final unit = raw['input_unit'] == 'lb' ? LoadUnit.lb : LoadUnit.kg;
        if (reps == null && seconds == null) return 'invalid_values';
        if (stored.status == WorkoutSetStatus.completed &&
            stored.reps == reps &&
            stored.durationSeconds == seconds &&
            (stored.loadGrams ?? 0) == (load ?? 0) &&
            stored.rpe == rpe &&
            stored.inputUnit == unit) {
          return null; // the same values on the same set: a duplicate
        }
        final wasCompleted = stored.status == WorkoutSetStatus.completed;
        final exercise = session.exercises
            .where((e) => e.uuid == stored.exerciseUuid)
            .firstOrNull;
        return _run(() {
          actions.saveSet(
            session,
            WorkoutSetRecord(
              uuid: stored.uuid,
              exerciseUuid: stored.exerciseUuid,
              position: stored.position,
              kind: stored.kind,
              status: WorkoutSetStatus.completed,
              reps: reps,
              durationSeconds: seconds,
              loadGrams: load != null && load > 0 ? load : null,
              inputUnit: unit,
              rpe: rpe,
              completedAtUtc: wasCompleted
                  ? stored.completedAtUtc
                  : _clock().toUtc(),
            ),
            // A correction never starts another rest.
            restSeconds: wasCompleted ? null : (exercise?.restSeconds ?? 90),
          );
          return null;
        });
      case 'skip_set':
        final stored = setOf(c.set?['set_id'] as String?);
        if (stored == null) return 'unknown_set';
        if (stored.status == WorkoutSetStatus.skipped) return null;
        if (stored.status == WorkoutSetStatus.completed) return 'not_allowed';
        return _run(() {
          actions.saveSet(session, skippedSet(stored));
          return null;
        });
      case 'add_set':
        final exercise = session.exercises
            .where((e) => e.uuid == c.exerciseId)
            .firstOrNull;
        if (exercise == null) return 'unknown_set';
        return _run(() {
          actions.addPlannedSet(session, exercise);
          return null;
        });
      case 'start_rest':
        if (paused) return 'not_allowed';
        final seconds = c.restSeconds;
        if (seconds == null) return 'invalid_values';
        return _run(() {
          actions.startRest(session, checkpoint, seconds);
          return null;
        });
      case 'clear_rest':
        final running =
            checkpoint.restStatus == RestTimerStatus.running ||
            checkpoint.restStatus == RestTimerStatus.paused;
        if (!running) return null;
        return _run(() {
          actions.clearRest(session, checkpoint);
          return null;
        });
      case 'pause':
        if (paused) return null;
        return _run(() {
          actions.pause(session);
          return null;
        });
      case 'resume':
        if (!paused) return null;
        return _run(() {
          actions.resume(session);
          return null;
        });
      case 'finish':
        return _run(() {
          actions.finish(session);
          return null;
        });
    }
    return 'not_allowed';
  }
}

final phoneLiveSessionProvider =
    NotifierProvider<PhoneLiveSessionController, PhoneLiveSessionState>(
      PhoneLiveSessionController.new,
    );
