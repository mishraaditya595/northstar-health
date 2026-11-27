import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/core/units/load_units.dart';
import 'package:beyondrep/features/account/account_auth_controller.dart';
import 'package:beyondrep/features/account/account_auth_provider.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/watch/application/live_watch_workout.dart';
import 'package:beyondrep/features/watch/application/phone_live_session.dart';
import 'package:beyondrep/features/watch/application/watch_sync_controller.dart';
import 'package:beyondrep/features/watch/application/watch_status_provider.dart';
import 'package:beyondrep/features/watch/data/watch_live_link.dart';
import 'package:beyondrep/features/watch/domain/watch_account_key.dart';
import 'package:beyondrep/features/watch/domain/watch_message.dart';
import 'package:beyondrep/features/watch/domain/watch_status.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_repository.dart';
import 'package:beyondrep/features/workouts/domain/live_workout_engine.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_account_auth.dart';
import 'fake_watch_live_link.dart';

const _s1 = 'dddddddd-dddd-4ddd-8ddd-dddddddddd01';
const _s2 = 'dddddddd-dddd-4ddd-8ddd-dddddddddd02';
const _s3 = 'dddddddd-dddd-4ddd-8ddd-dddddddddd03';
const _x1 = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeee01';
const _x2 = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeee02';
const _sessionId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

WorkoutSessionRecord _record({
  WorkoutStatus status = WorkoutStatus.inProgress,
  int revision = 7,
}) => WorkoutSessionRecord(
  uuid: _sessionId,
  name: 'Synthetic push day',
  status: status,
  startedAtUtc: DateTime.utc(2026, 11, 24, 8),
  originalOffsetMinutes: 0,
  revision: revision,
  exercises: const [
    WorkoutExerciseRecord(
      uuid: _x1,
      sessionUuid: _sessionId,
      nameSnapshot: 'Synthetic press',
      position: 0,
      restSeconds: 75,
    ),
    WorkoutExerciseRecord(
      uuid: _x2,
      sessionUuid: _sessionId,
      nameSnapshot: 'Synthetic hold',
      position: 1,
    ),
  ],
  sets: [
    WorkoutSetRecord(
      uuid: _s1,
      exerciseUuid: _x1,
      position: 0,
      kind: WorkoutSetKind.working,
      status: WorkoutSetStatus.completed,
      reps: 8,
      loadGrams: 60000,
      rpe: 8,
      completedAtUtc: DateTime.utc(2026, 11, 24, 8, 5),
    ),
    const WorkoutSetRecord(
      uuid: _s2,
      exerciseUuid: _x1,
      position: 1,
      kind: WorkoutSetKind.working,
      status: WorkoutSetStatus.planned,
      reps: 8,
      loadGrams: 60000,
      inputUnit: LoadUnit.lb,
    ),
    const WorkoutSetRecord(
      uuid: _s3,
      exerciseUuid: _x2,
      position: 0,
      kind: WorkoutSetKind.working,
      status: WorkoutSetStatus.skipped,
      durationSeconds: 30,
    ),
  ],
);

WorkoutRecoveryCheckpoint _checkpoint({int? restDeadlineMs}) =>
    WorkoutRecoveryCheckpoint(
      sessionUuid: _sessionId,
      checkpointRevision: 7,
      restState: restDeadlineMs == null ? 'idle' : 'running',
      restDeadlineUtcMs: restDeadlineMs,
    );

SessionState _build(
  ActiveWorkoutView view, {
  DateTime? pausedAt,
  int pausedSeconds = 0,
  List<String> applied = const [],
  List<({String commandId, String reason})> rejected = const [],
}) {
  final state = buildPhoneSessionState(
    accountKey: watchAccountKey(accountA),
    view: view,
    isTimed: (exercise, sets) => sets.any((s) => s.durationSeconds != null),
    nowUtc: DateTime.utc(2026, 11, 24, 8, 10),
    messageId: '77777777-3333-4333-8333-000000000001',
    pausedAt: pausedAt,
    pausedSeconds: pausedSeconds,
    appliedCommandIds: applied,
    rejectedCommands: rejected,
  );
  // The strict decoder is the contract: what the phone builds must pass it.
  return WatchMessage.fromJson(
    jsonDecode(jsonEncode(state.toJson())) as Map<String, Object?>,
  ) as SessionState;
}

class _Ids implements UuidFactory {
  int n = 0;
  @override
  String newId() =>
      '77777777-3333-4333-8333-${(n++).toString().padLeft(12, '0')}';
}

/// Counts how often the active workout provider was invalidated.
base class _InvalidationCount extends ProviderObserver {
  int count = 0;

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    if (context.provider == activeWorkoutProvider) count++;
  }
}

class _Harness {
  _Harness(this.tester, {this.store, bool linked = true}) {
    api = FakeAuthApi()..sessionId = accountA;
    bound = FakeBoundAccountStore()..saved = accountA;
    auth = controller(api, bound);
    link = FakeWatchLiveLink();
    container = ProviderContainer(
      observers: [invalidations],
      overrides: [
        accountAuthControllerProvider.overrideWithValue(auth),
        objectBoxStoreProvider.overrideWithValue(store!),
        watchLiveLinkProvider.overrideWithValue(link),
        watchMessageIdsProvider.overrideWithValue(_Ids()),
        wallClockProvider.overrideWithValue(() => t0.add(elapsed)),
      ],
    );
    this.linked = linked;
    addTearDown(() async {
      dispose();
      auth.dispose();
      await api.dispose();
      await link.dispose();
    });
  }

  final WidgetTester tester;
  final Store? store;
  late final FakeAuthApi api;
  late final FakeBoundAccountStore bound;
  late final AccountAuthController auth;
  late final FakeWatchLiveLink link;
  final invalidations = _InvalidationCount();
  late ProviderContainer container;
  final DateTime t0 = DateTime.now().toUtc();
  Duration elapsed = Duration.zero;
  bool _disposed = false;

  set linked(bool value) {
    container
        .read(watchLinkStateProvider.notifier)
        .update(
          WatchLinkState(
            device: WatchDeviceStatus(
              supported: true,
              paired: true,
              installed: value,
              reachable: true,
            ),
          ),
        );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
  }

  Future<void> start() async {
    await auth.restore();
    container.read(phoneLiveSessionProvider);
  }

  /// A new container on the same store, as after a phone relaunch.
  Future<void> relaunch() async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        accountAuthControllerProvider.overrideWithValue(auth),
        objectBoxStoreProvider.overrideWithValue(store!),
        watchLiveLinkProvider.overrideWithValue(link),
        watchMessageIdsProvider.overrideWithValue(_Ids()),
        wallClockProvider.overrideWithValue(() => t0.add(elapsed)),
      ],
    );
    linked = true;
    link.states.clear();
    container.read(phoneLiveSessionProvider);
  }

  ObjectBoxWorkoutRepository get repo => ObjectBoxWorkoutRepository(store!);
  WorkoutActions get actions => container.read(workoutActionsProvider);
  PhoneLiveSessionController get live =>
      container.read(phoneLiveSessionProvider.notifier);

  /// A workout with one exercise and three planned sets.
  Future<WorkoutSessionRecord> seed({int sets = 3}) async {
    final session = actions.startQuick('Synthetic push day');
    repo.addExercise(
      WorkoutExerciseRecord(
        uuid: _x1,
        sessionUuid: session.uuid,
        nameSnapshot: 'Synthetic press',
        position: 0,
        restSeconds: 60,
      ),
    );
    for (var i = 0; i < sets; i++) {
      final fresh = repo.getSession(session.uuid)!;
      actions.addPlannedSet(fresh, fresh.exercises.first);
    }
    sessionUuid = session.uuid;
    container.invalidate(activeWorkoutProvider);
    container.read(activeWorkoutProvider);
    await tester.pump();
    return repo.getSession(session.uuid)!;
  }

  WorkoutSessionRecord get session => repo.getSession(sessionUuid)!;
  late String sessionUuid;

  String command(
    String name, {
    String? id,
    String? sessionOverride,
    String? key,
    Map<String, Object?>? set,
    int? rest,
    String? exerciseId,
  }) {
    final json = SessionCommand(
      messageId: _Ids().newId().replaceAll('7777', '5555'),
      sentAtUtc: t0.add(elapsed).toIso8601String(),
      accountKey: key ?? watchAccountKey(accountA),
      sessionId: sessionOverride ?? sessionUuid,
      commandId: id ?? _nextCommandId(),
      command: name,
      set: set,
      restSeconds: rest,
      exerciseId: exerciseId,
    ).toJson();
    return jsonEncode(json);
  }

  int _commands = 0;
  String _nextCommandId() =>
      '88888888-4444-4444-8444-${(_commands++).toString().padLeft(12, '0')}';

  Map<String, Object?> setPayload(
    WorkoutSetRecord set, {
    int? reps = 8,
    int? seconds,
    int? load = 60000,
  }) => {
    'set_id': set.uuid,
    'exercise_id': set.exerciseUuid,
    'position': set.position,
    'kind': 'working',
    'input_unit': 'kg',
    'reps': ?reps,
    'duration_seconds': ?seconds,
    'load_grams': ?load,
  };

  SessionState get lastState => WatchMessage.fromJson(
    jsonDecode(link.states.last) as Map<String, Object?>,
  ) as SessionState;

  Future<void> advance(Duration d) async {
    for (var left = d; left > Duration.zero;) {
      final step = left > const Duration(seconds: 1)
          ? const Duration(seconds: 1)
          : left;
      elapsed += step;
      await tester.pump(step);
      left -= step;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildPhoneSessionState', () {
    test('turns an active workout into a valid phone-owned state', () {
      final view = ActiveWorkoutView(
        _record(),
        _checkpoint(
          restDeadlineMs: DateTime.utc(
            2026,
            11,
            24,
            8,
            11,
          ).millisecondsSinceEpoch,
        ),
      );
      final s = _build(
        view,
        applied: const ['88888888-4444-4444-8444-000000000001'],
      );
      expect(s.owner, 'phone');
      expect(s.status, 'active');
      expect(s.sessionId, _sessionId);
      expect(s.name, 'Synthetic push day');
      expect(s.startedAtUtc, '2026-11-24T08:00:00.000Z');
      expect(s.lastSequence, 7);
      expect(s.currentSetId, _s2);
      expect(s.restDeadlineUtc, '2026-11-24T08:11:00.000Z');
      expect(s.appliedCommandIds, ['88888888-4444-4444-8444-000000000001']);
      expect(s.pausedAtUtc, isNull);
      final exercises = s.exercises.cast<Map<String, Object?>>();
      expect(exercises.map((e) => e['exercise_id']), [_x1, _x2]);
      expect(exercises.map((e) => e['kind']), ['reps', 'duration']);
      final press = (exercises.first['sets']! as List).cast<Map>();
      expect(press[0], {
        'set_id': _s1,
        'position': 0,
        'kind': 'working',
        'status': 'completed',
        'input_unit': 'kg',
        'reps': 8,
        'load_grams': 60000,
        'rpe': 8.0,
      });
      expect(press[1]['status'], 'planned');
      expect(press[1]['input_unit'], 'lb');
      expect(press[1]['rest_seconds'], 75, reason: 'the exercise rest');
      final hold = (exercises.last['sets']! as List).cast<Map>();
      expect(hold.single['status'], 'skipped');
      expect(hold.single.containsKey('duration_seconds'), isFalse);
    });

    test('a paused workout has paused fields and no rest deadline', () {
      final view = ActiveWorkoutView(
        _record(status: WorkoutStatus.paused),
        _checkpoint(
          restDeadlineMs: DateTime.utc(
            2026,
            11,
            24,
            8,
            11,
          ).millisecondsSinceEpoch,
        ),
      );
      final s = _build(
        view,
        pausedAt: DateTime.utc(2026, 11, 24, 8, 9),
        pausedSeconds: 40,
      );
      expect(s.status, 'paused');
      expect(s.pausedAtUtc, '2026-11-24T08:09:00.000Z');
      expect(s.pausedSeconds, 40);
      expect(s.restDeadlineUtc, isNull);
    });

    test('rejected commands are echoed with their reason', () {
      final view = ActiveWorkoutView(_record(), _checkpoint());
      final s = _build(
        view,
        rejected: const [
          (
            commandId: '88888888-4444-4444-8444-000000000002',
            reason: 'not_allowed',
          ),
        ],
      );
      expect(s.rejectedCommands.single.reason, 'not_allowed');
    });

    test('no state carries a health value', () {
      final text = jsonEncode(
        _build(ActiveWorkoutView(_record(), _checkpoint())).toJson(),
      ).toLowerCase();
      for (final word in ['heart', 'kcal', 'energy', 'bpm', 'hrv', 'sleep']) {
        expect(text.contains(word), isFalse, reason: word);
      }
    });
  });

  group('controller', () {
    late Directory dir;
    late Store store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('beyondrep-phone-live-');
      store = Store(getObjectBoxModel(), directory: dir.path);
    });
    tearDown(() {
      store.close();
      dir.deleteSync(recursive: true);
    });

    testWidgets('broadcasts after a start and after a set save', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      final seeded = await h.seed();
      h.sessionUuid = seeded.uuid;
      expect(h.link.states, isNotEmpty);
      expect(h.lastState.owner, 'phone');
      expect(h.lastState.sessionId, seeded.uuid);
      final before = h.link.states.length;
      final planned = seeded.sets.first;
      h.actions.saveSet(
        seeded,
        WorkoutSetRecord(
          uuid: planned.uuid,
          exerciseUuid: planned.exerciseUuid,
          position: planned.position,
          kind: planned.kind,
          status: WorkoutSetStatus.completed,
          reps: 5,
          completedAtUtc: DateTime.now().toUtc(),
        ),
      );
      h.container.invalidate(activeWorkoutProvider);
      h.container.read(activeWorkoutProvider);
      await tester.pump();
      expect(h.link.states.length, greaterThan(before));
      final sets = (h.lastState.exercises.first as Map)['sets']! as List;
      expect((sets.first as Map)['status'], 'completed');
      h.dispose();
    });

    testWidgets('broadcasts every 30 s while linked and not without a link', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      h.sessionUuid = (await h.seed()).uuid;
      final before = h.link.states.length;
      await h.advance(const Duration(seconds: 30));
      expect(h.link.states.length, before + 1);
      await h.advance(const Duration(seconds: 30));
      expect(h.link.states.length, before + 2);
      h.linked = false;
      final stopped = h.link.states.length;
      await h.advance(const Duration(seconds: 90));
      expect(h.link.states.length, stopped);
      h.dispose();
    });

    testWidgets('sends nothing when the watch app is not installed', (
      tester,
    ) async {
      final h = _Harness(tester, store: store, linked: false);
      await h.start();
      h.sessionUuid = (await h.seed()).uuid;
      await h.advance(const Duration(seconds: 60));
      expect(h.link.states, isEmpty);
      expect(h.link.watchAppStarts, 0);
      h.dispose();
    });

    testWidgets('log_set, skip_set and add_set apply through the actions', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      final seeded = await h.seed();
      h.sessionUuid = seeded.uuid;
      final first = seeded.sets[0];
      final second = seeded.sets[1];
      final logId = '88888888-4444-4444-8444-0000000000a1';
      h.link.receive(h.command('log_set', id: logId, set: h.setPayload(first)));
      final logged = h.session.sets.firstWhere((s) => s.uuid == first.uuid);
      expect(logged.status, WorkoutSetStatus.completed);
      expect(logged.reps, 8);
      expect(logged.loadGrams, 60000);
      expect(h.lastState.appliedCommandIds, contains(logId));
      expect(
        (((h.lastState.exercises.first as Map)['sets']! as List).first
            as Map)['status'],
        'completed',
      );

      final skipId = '88888888-4444-4444-8444-0000000000a2';
      h.link.receive(
        h.command('skip_set', id: skipId, set: h.setPayload(second)),
      );
      expect(
        h.session.sets.firstWhere((s) => s.uuid == second.uuid).status,
        WorkoutSetStatus.skipped,
      );
      expect(h.lastState.appliedCommandIds, contains(skipId));

      final addId = '88888888-4444-4444-8444-0000000000a3';
      h.link.receive(h.command('add_set', id: addId, exerciseId: _x1));
      expect(h.session.sets.length, 4);
      expect(h.lastState.appliedCommandIds, contains(addId));
      h.dispose();
    });

    testWidgets('a corrected set takes the new values', (tester) async {
      final h = _Harness(tester, store: store);
      await h.start();
      final seeded = await h.seed();
      h.sessionUuid = seeded.uuid;
      final first = seeded.sets[0];
      h.link.receive(h.command('log_set', set: h.setPayload(first)));
      h.link.receive(
        h.command(
          'correct_set',
          set: h.setPayload(first, reps: 10, load: 65000),
        ),
      );
      final set = h.session.sets.firstWhere((s) => s.uuid == first.uuid);
      expect(set.reps, 10);
      expect(set.loadGrams, 65000);
      h.dispose();
    });

    testWidgets('a set with no reps or seconds is rejected as invalid', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      final seeded = await h.seed();
      h.sessionUuid = seeded.uuid;
      final id = '88888888-4444-4444-8444-0000000000b1';
      h.link.receive(
        h.command(
          'log_set',
          id: id,
          set: h.setPayload(seeded.sets[0], reps: null, load: null),
        ),
      );
      expect(h.session.sets.first.status, WorkoutSetStatus.planned);
      expect(h.lastState.rejectedCommands.single.commandId, id);
      expect(h.lastState.rejectedCommands.single.reason, 'invalid_values');
      h.dispose();
    });

    testWidgets('an unknown set or exercise is rejected', (tester) async {
      final h = _Harness(tester, store: store);
      await h.start();
      final seeded = await h.seed();
      h.sessionUuid = seeded.uuid;
      final ghost = WorkoutSetRecord(
        uuid: 'dddddddd-dddd-4ddd-8ddd-ddddddddddff',
        exerciseUuid: _x1,
        position: 9,
        kind: WorkoutSetKind.working,
        status: WorkoutSetStatus.planned,
      );
      h.link.receive(h.command('log_set', set: h.setPayload(ghost)));
      h.link.receive(h.command('add_set', exerciseId: 'no-such-exercise'));
      expect(h.lastState.rejectedCommands.map((r) => r.reason), [
        'unknown_set',
        'unknown_set',
      ]);
      expect(h.session.sets.length, 3);
      h.dispose();
    });

    testWidgets('rest, pause, resume apply and are idempotent by effect', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      h.sessionUuid = (await h.seed()).uuid;
      h.link.receive(h.command('start_rest', rest: 90));
      var checkpoint = h.container
          .read(activeWorkoutProvider)
          .value!
          .checkpoint;
      expect(checkpoint.restStatus, RestTimerStatus.running);
      expect(h.lastState.restDeadlineUtc, isNotNull);
      h.link.receive(h.command('clear_rest'));
      checkpoint = h.container.read(activeWorkoutProvider).value!.checkpoint;
      expect(checkpoint.restStatus, RestTimerStatus.idle);
      // Clearing a rest that is not running is a duplicate, not a failure.
      h.link.receive(h.command('clear_rest'));
      expect(h.lastState.rejectedCommands, isEmpty);

      h.link.receive(h.command('pause'));
      expect(h.session.status, WorkoutStatus.paused);
      expect(h.lastState.status, 'paused');
      expect(h.lastState.pausedAtUtc, isNotNull);
      final revision = h.session.revision;
      h.link.receive(h.command('pause'));
      expect(h.session.revision, revision, reason: 'pause while paused');
      await h.advance(const Duration(seconds: 20));
      h.link.receive(h.command('resume'));
      expect(h.session.status, WorkoutStatus.inProgress);
      expect(h.lastState.status, 'active');
      expect(h.lastState.pausedSeconds, 20);
      final resumed = h.session.revision;
      h.link.receive(h.command('resume'));
      expect(h.session.revision, resumed, reason: 'resume while active');
      expect(h.lastState.rejectedCommands, isEmpty);
      h.dispose();
    });

    testWidgets('a duplicate command id is applied once and echoed', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      h.sessionUuid = (await h.seed()).uuid;
      final id = '88888888-4444-4444-8444-0000000000c1';
      final json = h.command('start_rest', id: id, rest: 90);
      h.link.receive(json);
      final deadline = h.lastState.restDeadlineUtc;
      final saved = h.container
          .read(activeWorkoutProvider)
          .value!
          .checkpoint
          .savedAtMs;
      await h.advance(const Duration(seconds: 7));
      final before = h.link.states.length;
      h.link.receive(json);
      expect(
        h.container.read(activeWorkoutProvider).value!.checkpoint.savedAtMs,
        saved,
      );
      expect(h.lastState.restDeadlineUtc, deadline);
      expect(h.lastState.appliedCommandIds.where((c) => c == id), hasLength(1));
      expect(h.link.states.length, before + 1, reason: 'echoed again');
      h.dispose();
    });

    testWidgets('replayed commands after the id memory is lost are no-ops', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      final seeded = await h.seed();
      h.sessionUuid = seeded.uuid;
      final first = seeded.sets[0];
      final second = seeded.sets[1];
      final log = h.command('log_set', set: h.setPayload(first));
      final skip = h.command('skip_set', set: h.setPayload(second));
      final pause = h.command('pause');
      h.link.receive(log);
      h.link.receive(skip);
      h.link.receive(pause);
      final revision = h.session.revision;
      final loggedAt = h.session.sets
          .firstWhere((s) => s.uuid == first.uuid)
          .completedAtUtc;
      await h.relaunch();
      await h.advance(const Duration(seconds: 10));
      h.link.receive(log);
      h.link.receive(skip);
      h.link.receive(pause);
      expect(h.session.revision, revision);
      expect(
        h.session.sets.firstWhere((s) => s.uuid == first.uuid).completedAtUtc,
        loggedAt,
      );
      expect(h.session.status, WorkoutStatus.paused);
      expect(h.lastState.rejectedCommands, isEmpty);
      h.dispose();
    });

    testWidgets('another account key or another session is ignored', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      final seeded = await h.seed();
      h.sessionUuid = seeded.uuid;
      final before = h.link.states.length;
      final revision = h.session.revision;
      h.link.receive(h.command('pause', key: watchAccountKey(accountB)));
      h.link.receive(
        h.command(
          'pause',
          sessionOverride: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        ),
      );
      expect(h.session.revision, revision);
      expect(h.session.status, WorkoutStatus.inProgress);
      expect(h.link.states.length, before);
      h.dispose();
    });

    testWidgets('finish from the watch finishes the workout, then ended', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      h.sessionUuid = (await h.seed()).uuid;
      final id = '88888888-4444-4444-8444-0000000000d1';
      h.link.receive(h.command('finish', id: id));
      expect(h.session.status, WorkoutStatus.completed);
      expect(h.container.read(activeWorkoutProvider).value, isNull);
      expect(h.lastState.status, 'ended');
      expect(h.lastState.endReason, 'completed');
      expect(h.lastState.appliedCommandIds, contains(id));
      h.dispose();
    });

    testWidgets('a discard waits for the phone confirm and can be declined', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      h.sessionUuid = (await h.seed()).uuid;
      final id = '88888888-4444-4444-8444-0000000000e1';
      final json = h.command('discard', id: id);
      h.link.receive(json);
      expect(h.container.read(phoneLiveSessionProvider).pendingDiscard, isTrue);
      expect(h.session.status, WorkoutStatus.inProgress);
      // The same command again while asking does not ask twice.
      h.link.receive(json);
      h.live.resolveDiscard(false);
      expect(
        h.container.read(phoneLiveSessionProvider).pendingDiscard,
        isFalse,
      );
      expect(h.session.status, WorkoutStatus.inProgress);
      expect(h.lastState.rejectedCommands.single.commandId, id);
      expect(h.lastState.rejectedCommands.single.reason, 'not_allowed');
      h.dispose();
    });

    testWidgets('a confirmed discard discards and sends ended', (tester) async {
      final h = _Harness(tester, store: store);
      await h.start();
      h.sessionUuid = (await h.seed()).uuid;
      final id = '88888888-4444-4444-8444-0000000000e2';
      h.link.receive(h.command('discard', id: id));
      h.live.resolveDiscard(true);
      expect(h.session.status, WorkoutStatus.discarded);
      expect(h.lastState.status, 'ended');
      expect(h.lastState.endReason, 'discarded');
      expect(h.lastState.appliedCommandIds, contains(id));
      h.dispose();
    });

    testWidgets('a join sends the state at once, even when unchanged', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      h.sessionUuid = (await h.seed()).uuid;
      final before = h.link.states.length;
      final join = JoinMessage(
        messageId: '55555555-3333-4333-8333-000000000001',
        sentAtUtc: h.t0.toIso8601String(),
        accountKey: watchAccountKey(accountA),
        sessionId: h.sessionUuid,
      );
      h.link.receive(jsonEncode(join.toJson()));
      expect(h.link.states.length, before + 1);
      // Another account's join is not answered.
      final other = JoinMessage(
        messageId: '55555555-3333-4333-8333-000000000002',
        sentAtUtc: h.t0.toIso8601String(),
        accountKey: watchAccountKey(accountB),
        sessionId: h.sessionUuid,
      );
      h.link.receive(jsonEncode(other.toJson()));
      expect(h.link.states.length, before + 1);
      h.dispose();
    });

    testWidgets('a join without a session id gets the running state', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      h.sessionUuid = (await h.seed()).uuid;
      final before = h.link.states.length;
      final join = JoinMessage(
        messageId: '55555555-3333-4333-8333-000000000003',
        sentAtUtc: h.t0.toIso8601String(),
        accountKey: watchAccountKey(accountA),
      );
      h.link.receive(jsonEncode(join.toJson()));
      expect(h.link.states.length, before + 1);
      expect(h.lastState.status, 'active');
      h.dispose();
    });

    testWidgets('a join for a finished workout is answered with ended', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      h.sessionUuid = (await h.seed()).uuid;
      h.actions.finish(h.session);
      h.container.invalidate(activeWorkoutProvider);
      h.container.read(activeWorkoutProvider);
      // Well past the 2 minutes the ended state is resent.
      await h.advance(const Duration(minutes: 5));
      h.link.states.clear();
      final join = JoinMessage(
        messageId: '55555555-3333-4333-8333-000000000004',
        sentAtUtc: h.t0.toIso8601String(),
        accountKey: watchAccountKey(accountA),
        sessionId: h.sessionUuid,
      );
      h.link.receive(jsonEncode(join.toJson()));
      expect(h.link.states, hasLength(1));
      expect(h.lastState.status, 'ended');
      expect(h.lastState.endReason, 'completed');
      expect(h.lastState.sessionId, h.sessionUuid);
      h.dispose();
    });

    testWidgets(
      'after a relaunch a join for a discarded workout is answered ended',
      (tester) async {
        final h = _Harness(tester, store: store);
        await h.start();
        h.sessionUuid = (await h.seed()).uuid;
        h.actions.discard(h.session);
        await h.relaunch();
        final join = JoinMessage(
          messageId: '55555555-3333-4333-8333-000000000005',
          sentAtUtc: h.t0.toIso8601String(),
          accountKey: watchAccountKey(accountA),
          sessionId: h.sessionUuid,
        );
        h.link.receive(jsonEncode(join.toJson()));
        expect(h.link.states, hasLength(1));
        expect(h.lastState.status, 'ended');
        expect(h.lastState.endReason, 'discarded');
        h.dispose();
      },
    );

    testWidgets('a join for an unknown workout is not answered', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      h.sessionUuid = (await h.seed()).uuid;
      final before = h.link.states.length;
      final join = JoinMessage(
        messageId: '55555555-3333-4333-8333-000000000006',
        sentAtUtc: h.t0.toIso8601String(),
        accountKey: watchAccountKey(accountA),
        sessionId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      );
      h.link.receive(jsonEncode(join.toJson()));
      expect(h.link.states.length, before);
      h.dispose();
    });

    testWidgets('no timer and no refresh while no watch can be sent to', (
      tester,
    ) async {
      final h = _Harness(tester, store: store, linked: false);
      await h.start();
      h.sessionUuid = (await h.seed()).uuid;
      final before = h.invalidations.count;
      await h.advance(const Duration(seconds: 90));
      expect(h.invalidations.count, before);
      expect(h.link.states, isEmpty);
      // Linking later starts the beat again.
      h.linked = true;
      final linkedStates = h.link.states.length;
      await h.advance(const Duration(seconds: 30));
      expect(h.link.states.length, greaterThan(linkedStates));
      expect(h.invalidations.count, greaterThan(before));
      h.dispose();
    });

    testWidgets('a replayed add_set after a relaunch adds no extra set', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      h.sessionUuid = (await h.seed()).uuid;
      final add = h.command('add_set', exerciseId: _x1);
      h.link.receive(add);
      expect(h.session.sets.length, 4);
      final revision = h.session.revision;
      await h.relaunch();
      await h.advance(const Duration(seconds: 10));
      h.link.receive(add);
      expect(h.session.sets.length, 4);
      expect(h.session.revision, revision);
      expect(h.lastState.rejectedCommands, isEmpty);
      // Another add_set command still adds a set.
      h.link.receive(h.command('add_set', exerciseId: _x1));
      expect(h.session.sets.length, 5);
      h.dispose();
    });

    testWidgets(
      'the watch app is launched once at the start, only when installed',
      (tester) async {
        final h = _Harness(tester, store: store);
        await h.start();
        h.sessionUuid = (await h.seed()).uuid;
        expect(h.link.watchAppStarts, 1);
        h.container.invalidate(activeWorkoutProvider);
        h.container.read(activeWorkoutProvider);
        await h.advance(const Duration(seconds: 30));
        expect(h.link.watchAppStarts, 1);
        await h.live.openOnWatch();
        expect(h.link.watchAppStarts, 2);
        h.dispose();
      },
    );

    testWidgets('a workout recovered at launch does not launch the watch', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.auth.restore();
      h.sessionUuid = (await h.seed()).uuid;
      h.container.read(phoneLiveSessionProvider);
      expect(h.link.watchAppStarts, 0);
      expect(h.link.states, isNotEmpty, reason: 'it still broadcasts');
      h.dispose();
    });

    testWidgets('no broadcast while a watch-owned workout is live', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      h.sessionUuid = (await h.seed()).uuid;
      final before = h.link.states.length;
      final watchState = jsonDecode(
        File('../../contracts/watch_link/v1/fixtures/valid/session_state.json')
            .readAsStringSync(),
      ) as Map<String, Object?>;
      watchState['account_key'] = watchAccountKey(accountA);
      watchState['sent_at_utc'] = h.t0.toIso8601String();
      h.link.receive(jsonEncode(watchState));
      expect(h.container.read(liveWatchWorkoutProvider).workout, isNotNull);
      await h.advance(const Duration(seconds: 60));
      expect(h.link.states.length, before);
      h.dispose();
    });
  });
}
