import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/features/account/account_auth_controller.dart';
import 'package:beyondrep/features/account/account_auth_provider.dart';
import 'package:beyondrep/features/watch/application/live_watch_workout.dart';
import 'package:beyondrep/features/watch/application/watch_sync_controller.dart';
import 'package:beyondrep/features/watch/data/watch_live_link.dart';
import 'package:beyondrep/features/watch/domain/watch_account_key.dart';
import 'package:beyondrep/features/watch/domain/watch_message.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_account_auth.dart';
import 'fake_watch_live_link.dart';

class _Ids implements UuidFactory {
  int n = 0;
  @override
  String newId() =>
      '77777777-3333-4333-8333-${(n++).toString().padLeft(12, '0')}';
}

const _session = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _set1 = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _set2 = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2';
final _t0 = DateTime.utc(2026, 11, 24, 8);

String _t(Duration d) => _t0.add(d).toIso8601String();

/// A `session_state` built from the shared fixture, so it stays valid.
String _state({
  String? key,
  Duration at = Duration.zero,
  String? messageId,
  String status = 'active',
  String session = _session,
  List<String> applied = const [],
  List<Map<String, String>> rejected = const [],
  String? endReason,
  String owner = 'watch',
}) {
  final json = jsonDecode(
    File('../../contracts/watch_link/v1/fixtures/valid/session_state.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  json['account_key'] = key ?? watchAccountKey(accountA);
  json['message_id'] =
      messageId ??
      '99999999-3333-4333-8333-${at.inSeconds.toString().padLeft(12, '0')}';
  json['sent_at_utc'] = _t(at);
  final body = json['body']! as Map<String, Object?>;
  body['session_id'] = session;
  body['owner'] = owner;
  body['status'] = status;
  body['started_at_utc'] = _t0.toIso8601String();
  if (status == 'ended') {
    body.remove('rest_deadline_utc');
    body.remove('current_set_id');
    body['end_reason'] = endReason ?? 'completed';
  }
  if (applied.isNotEmpty) body['applied_command_ids'] = applied;
  if (rejected.isNotEmpty) body['rejected_commands'] = rejected;
  return jsonEncode(json);
}

class _Harness {
  _Harness(WidgetTester tester) {
    api = FakeAuthApi()..sessionId = accountA;
    bound = FakeBoundAccountStore()..saved = accountA;
    auth = controller(api, bound);
    link = FakeWatchLiveLink();
    container = ProviderContainer(
      overrides: [
        accountAuthControllerProvider.overrideWithValue(auth),
        watchLiveLinkProvider.overrideWithValue(link),
        watchMessageIdsProvider.overrideWithValue(_Ids()),
        wallClockProvider.overrideWithValue(() => _t0.add(elapsed)),
      ],
    );
    addTearDown(() async {
      dispose();
      auth.dispose();
      await api.dispose();
      await link.dispose();
    });
  }

  bool _disposed = false;

  /// The controller's 1 s timer must be gone before a test body ends.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
  }

  late final FakeAuthApi api;
  late final FakeBoundAccountStore bound;
  late final AccountAuthController auth;
  late final FakeWatchLiveLink link;
  late final ProviderContainer container;

  /// The fake wall clock, moved together with `tester.pump`.
  Duration elapsed = Duration.zero;

  Future<void> start() async {
    await auth.restore();
    container.read(liveWatchWorkoutProvider);
  }

  LiveWatchState get state => container.read(liveWatchWorkoutProvider);
  LiveWatchWorkoutController get live =>
      container.read(liveWatchWorkoutProvider.notifier);

  Future<void> advance(WidgetTester tester, Duration d) async {
    for (var left = d; left > Duration.zero;) {
      final step = left > const Duration(seconds: 1)
          ? const Duration(seconds: 1)
          : left;
      elapsed += step;
      await tester.pump(step);
      left -= step;
    }
  }

  List<SessionCommand> get commands => [
    for (final json in link.sent)
      WatchMessage.fromJson(jsonDecode(json) as Map<String, Object?>)
          as SessionCommand,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a state for the signed-in key is shown, another key is ignored',
    (tester) async {
      final h = _Harness(tester);
      await h.start();
      h.link.receive(_state(key: watchAccountKey(accountB)));
      expect(h.state.workout, isNull);
      h.link.receive(_state());
      expect(h.state.workout?.sessionId, _session);
      expect(h.state.workout?.name, 'Synthetic push day');
      expect(h.state.isLive, isTrue);
      expect(h.state.workout?.currentSetId, _set2);
      h.dispose();
    },
  );

  testWidgets('a state owned by the phone is not a watch workout', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    h.link.receive(_state(owner: 'phone'));
    expect(h.state.workout, isNull);
    h.dispose();
  });

  testWidgets('garbage and wrong message types are ignored', (tester) async {
    final h = _Harness(tester);
    await h.start();
    h.link.receive('not json');
    h.link.receive('{"schema_version":1}');
    expect(h.state.workout, isNull);
    h.dispose();
  });

  testWidgets(
    'a newer state replaces an older one, older and duplicate are ignored',
    (tester) async {
      final h = _Harness(tester);
      await h.start();
      h.link.receive(_state(at: const Duration(seconds: 10)));
      expect(h.state.workout?.sentAt, _t0.add(const Duration(seconds: 10)));
      h.link.receive(_state(at: const Duration(seconds: 5)));
      expect(h.state.workout?.sentAt, _t0.add(const Duration(seconds: 10)));
      h.link.receive(_state(at: const Duration(seconds: 20), status: 'paused'));
      expect(h.state.workout?.status, 'paused');
      // The same message again (delivered on both paths) changes nothing.
      h.link.receive(
        _state(
          at: const Duration(seconds: 20),
          status: 'active',
          messageId: h.state.workout!.messageId,
        ),
      );
      expect(h.state.workout?.status, 'paused');
      h.dispose();
    },
  );

  testWidgets('stale after 90 s, fresh again on the next state', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    h.link.receive(_state());
    await h.advance(tester, const Duration(seconds: 89));
    expect(h.state.stale, isFalse);
    await h.advance(tester, const Duration(seconds: 1));
    expect(h.state.stale, isTrue);
    expect(h.state.workout, isNotNull);
    h.link.receive(_state(at: const Duration(seconds: 95)));
    expect(h.state.stale, isFalse);
    h.dispose();
  });

  testWidgets('stale at once when the mirrored session disconnects', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    h.link.receive(_state());
    h.link.disconnect();
    expect(h.state.stale, isTrue);
    expect(h.state.isLive, isFalse);
    h.dispose();
  });

  testWidgets('a stale state is dropped after 6 hours', (tester) async {
    final h = _Harness(tester);
    await h.start();
    h.link.receive(_state());
    h.link.disconnect();
    h.elapsed = const Duration(hours: 6) - const Duration(seconds: 1);
    await tester.pump(const Duration(seconds: 1));
    expect(h.state.workout, isNotNull);
    h.elapsed = const Duration(hours: 6);
    await tester.pump(const Duration(seconds: 1));
    expect(h.state.workout, isNull);
    h.dispose();
  });

  testWidgets('ended drops the state and an older state cannot bring it back', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    h.link.receive(_state(at: const Duration(seconds: 1)));
    h.link.receive(
      _state(
        at: const Duration(seconds: 30),
        status: 'ended',
        endReason: 'completed',
      ),
    );
    expect(h.state.workout, isNull);
    expect(h.state.ended?.completed, isTrue);
    expect(h.state.ended?.sessionId, _session);
    // A late copy of an earlier state of the same session.
    h.link.receive(_state(at: const Duration(seconds: 40)));
    expect(h.state.workout, isNull);
    h.live.acknowledgeEnd();
    expect(h.state.ended, isNull);
    h.dispose();
  });

  testWidgets('a discarded workout is reported as not completed', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    h.link.receive(_state());
    h.link.receive(
      _state(
        at: const Duration(seconds: 3),
        status: 'ended',
        endReason: 'discarded',
      ),
    );
    expect(h.state.ended?.completed, isFalse);
    h.dispose();
  });

  testWidgets('sign out drops the state, and so does an account switch', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    h.link.receive(_state());
    expect(h.state.workout, isNotNull);
    await h.auth.signOut();
    expect(h.state.workout, isNull);
    h.api.verifiedId = accountB;
    // Account B signs in: A's workout is not B's.
    h.link.receive(_state());
    expect(h.state.workout, isNull);
    h.dispose();
  });

  testWidgets('a command is pending until the watch lists it as applied', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    h.link.receive(_state());
    final command = h.live.logSet(_set2, reps: 8, loadGrams: 60000)!;
    expect(h.state.isSaving(_set2), isTrue);
    expect(h.state.commands.single.phase, LiveCommandPhase.pending);
    final sent = h.commands.single;
    expect(sent.command, 'log_set');
    expect(sent.commandId, command.id);
    expect(sent.sessionId, _session);
    expect(sent.accountKey, watchAccountKey(accountA));
    expect(sent.set!['set_id'], _set2);
    expect(sent.set!['reps'], 8);
    h.link.receive(
      _state(at: const Duration(seconds: 2), applied: [command.id]),
    );
    expect(h.state.commands, isEmpty);
    expect(h.state.isSaving(_set2), isFalse);
    h.dispose();
  });

  testWidgets('a completed set is corrected, not logged again', (tester) async {
    final h = _Harness(tester);
    await h.start();
    h.link.receive(_state());
    h.live.logSet(_set1, reps: 9);
    expect(h.commands.single.command, 'correct_set');
    h.dispose();
  });

  testWidgets(
    'a command is resent every 5 s for 30 s, then failed, and retry reuses its id',
    (tester) async {
      final h = _Harness(tester);
      await h.start();
      h.link.receive(_state());
      // Keep the link fresh so only the command times out.
      Future<void> beat(int seconds) async {
        h.link.receive(_state(at: Duration(seconds: seconds)));
      }

      final command = h.live.skipSet(_set2)!;
      expect(h.link.sent, hasLength(1));
      await h.advance(tester, const Duration(seconds: 5));
      await beat(5);
      expect(h.link.sent, hasLength(2));
      await h.advance(tester, const Duration(seconds: 5));
      await beat(10);
      expect(h.link.sent, hasLength(3));
      for (var s = 15; s <= 25; s += 5) {
        await h.advance(tester, const Duration(seconds: 5));
        await beat(s);
      }
      expect(h.link.sent, hasLength(6));
      expect(
        {for (final c in h.commands) c.commandId},
        {command.id},
        reason: 'every resend keeps the command id',
      );
      await h.advance(tester, const Duration(seconds: 5));
      expect(h.state.commands.single.phase, LiveCommandPhase.failed);
      final before = h.link.sent.length;
      await h.advance(tester, const Duration(seconds: 10));
      expect(
        h.link.sent.length,
        before,
        reason: 'a failed command is not resent',
      );

      h.live.retry(command.id);
      expect(h.state.commands.single.phase, LiveCommandPhase.pending);
      expect(h.link.sent.length, before + 1);
      expect(h.commands.last.commandId, command.id);
      h.dispose();
    },
  );

  testWidgets('a rejected command shows its reason', (tester) async {
    final h = _Harness(tester);
    await h.start();
    h.link.receive(_state());
    final command = h.live.logSet(_set2, reps: 8)!;
    h.link.receive(
      _state(
        at: const Duration(seconds: 2),
        rejected: [
          {'command_id': command.id, 'reason': 'invalid_values'},
        ],
      ),
    );
    final shown = h.state.commands.single;
    expect(shown.phase, LiveCommandPhase.rejected);
    expect(shown.reason, 'invalid_values');
    expect(h.state.isSaving(_set2), isFalse);
    h.live.dismiss(command.id);
    expect(h.state.commands, isEmpty);
    h.dispose();
  });

  testWidgets('no command is sent or resent while the state is stale', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    h.link.receive(_state());
    final pending = h.live.pause()!;
    expect(h.link.sent, hasLength(1));
    h.link.disconnect();
    expect(h.live.resume(), isNull);
    expect(h.live.logSet(_set2, reps: 8), isNull);
    await h.advance(tester, const Duration(seconds: 20));
    expect(h.link.sent, hasLength(1), reason: 'no resend while stale');
    h.live.retry(pending.id);
    expect(h.link.sent, hasLength(1));
    h.dispose();
  });

  testWidgets('a command for a workout that ended is dropped with it', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    h.link.receive(_state());
    h.live.finish();
    expect(h.state.commands, hasLength(1));
    h.link.receive(
      _state(
        at: const Duration(seconds: 4),
        status: 'ended',
        endReason: 'completed',
      ),
    );
    expect(h.state.commands, isEmpty);
    await h.advance(tester, const Duration(seconds: 60));
    expect(h.link.sent, hasLength(1), reason: 'nothing resent after the end');
    h.dispose();
  });

  testWidgets('add set and rest commands carry their fields', (tester) async {
    final h = _Harness(tester);
    await h.start();
    h.link.receive(_state());
    h.live.addSet('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
    h.live.startRest(90);
    h.live.clearRest();
    final sent = h.commands;
    expect(sent[0].command, 'add_set');
    expect(sent[0].exerciseId, 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
    expect(sent[1].command, 'start_rest');
    expect(sent[1].restSeconds, 90);
    expect(sent[2].command, 'clear_rest');
    h.dispose();
  });

  testWidgets('a whole live session leaves ObjectBox untouched', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('beyondrep-live-');
    final store = Store(getObjectBoxModel(), directory: dir.path);
    addTearDown(() {
      store.close();
      dir.deleteSync(recursive: true);
    });
    int count() =>
        store.box<WorkoutSessionEntity>().count() +
        store.box<WorkoutSetEntity>().count();
    final before = count();
    final h = _Harness(tester);
    await h.start();
    h.link.receive(_state());
    final c = h.live.logSet(_set2, reps: 8, loadGrams: 60000)!;
    h.link.receive(_state(at: const Duration(seconds: 2), applied: [c.id]));
    h.live.finish();
    h.link.receive(
      _state(
        at: const Duration(seconds: 5),
        status: 'ended',
        endReason: 'completed',
      ),
    );
    expect(count(), before);
    expect(before, 0);
    h.dispose();
  });
}
