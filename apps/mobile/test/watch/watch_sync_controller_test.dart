import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/features/account/account_auth_controller.dart';
import 'package:beyondrep/features/account/account_auth_provider.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/progress/workout_history_state.dart';
import 'package:beyondrep/features/programs/application/program_providers.dart';
import 'package:beyondrep/features/train/train_library_state.dart';
import 'package:beyondrep/features/watch/application/watch_sync_controller.dart';
import 'package:beyondrep/features/watch/application/watch_status_provider.dart';
import 'package:beyondrep/features/watch/data/objectbox_watch_workout_importer.dart';
import 'package:beyondrep/features/watch/data/watch_link.dart';
import 'package:beyondrep/features/watch/data/watch_status_store.dart';
import 'package:beyondrep/features/watch/domain/watch_account_key.dart';
import 'package:beyondrep/features/watch/domain/watch_message.dart';
import 'package:beyondrep/features/watch/domain/watch_status.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_account_auth.dart';
import '../support/fake_health_overview.dart';
import '../support/health_overview_fixtures.dart';

class _Call {
  _Call(this.kind, this.payload);
  final String kind;
  final Object? payload;
}

class _FakeLink implements WatchLink {
  _FakeLink({this.reachable = true});
  bool reachable;
  final calls = <_Call>[];

  /// When set, `updateContext` records its call and then waits for it.
  Completer<void>? holdContext;
  final stateChanges = StreamController<void>.broadcast();

  @override
  Stream<void> get watchStateChanges => stateChanges.stream;

  /// What the watch sent back; tests add acks here.
  int messageListens = 0;
  late final incoming = StreamController<String>.broadcast(
    onListen: () => messageListens++,
  );

  final reachabilityChanges = StreamController<void>.broadcast();

  @override
  Stream<void> get watchReachabilityChanges => reachabilityChanges.stream;

  @override
  Stream<String> get messages => incoming.stream;

  /// Replaces the status derived from [reachable].
  WatchDeviceStatus? deviceOverride;

  @override
  Future<WatchDeviceStatus> status() async =>
      deviceOverride ??
      WatchDeviceStatus(
        supported: true,
        paired: true,
        installed: reachable,
        reachable: reachable,
      );

  @override
  Future<bool> isReachableForUpdates() async => reachable;

  @override
  Future<void> updateContext(Map<String, String> latestByType) async {
    calls.add(_Call('context', Map<String, String>.of(latestByType)));
    await holdContext?.future;
  }

  @override
  Future<void> transfer(String json) async =>
      calls.add(_Call('transfer', json));

  List<_Call> get contexts => [
    for (final c in calls)
      if (c.kind == 'context') c,
  ];

  Map<String, Object?> bodyOf(_Call call, String type) =>
      (jsonDecode((call.payload! as Map<String, String>)[type]!)
              as Map<String, Object?>)['body']!
          as Map<String, Object?>;

  WatchMessage transferred(int index) => WatchMessage.fromJson(
    jsonDecode(
      calls.where((c) => c.kind == 'transfer').toList()[index].payload!
          as String,
    ) as Map<String, Object?>,
  );
}

class _Ids implements UuidFactory {
  int n = 0;
  @override
  String newId() =>
      '77777777-3333-4333-8333-${(n++).toString().padLeft(12, '0')}';
}

final _library = WorkoutLibrarySnapshot(
  exercises: const [],
  plans: [
    WorkoutPlanRecord(
      uuid: 'plan-1',
      name: 'Synthetic push day',
      description: '',
      updatedAtMs: 0,
      exercises: const [],
    ),
  ],
);

class _Harness {
  _Harness(
    WidgetTester tester, {
    bool reachable = true,
    bool signedIn = true,
    Store? store,
  }) {
    link = _FakeLink(reachable: reachable);
    api = FakeAuthApi()..sessionId = signedIn ? accountA : null;
    bound = FakeBoundAccountStore()..saved = signedIn ? accountA : null;
    auth = controller(api, bound);
    health = FakeHealthOverviewController(
      overview(ownerId: accountA, readAt: DateTime(2026, 11, 24, 7, 42)),
    );
    container = ProviderContainer(
      overrides: [
        accountAuthControllerProvider.overrideWithValue(auth),
        watchLinkProvider.overrideWithValue(link),
        watchMessageIdsProvider.overrideWithValue(_Ids()),
        wallClockProvider.overrideWithValue(() => DateTime(2026, 11, 24, 8)),
        localNowProvider.overrideWithValue(DateTime(2026, 11, 24, 8)),
        trainLibraryProvider.overrideWith((ref) async => _library),
        programWeekProvider.overrideWithValue(null),
        completedWorkoutHistoryProvider.overrideWith(
          (ref) async => const WorkoutHistorySnapshot(sessions: []),
        ),
        fakeHealthOverview(health),
        if (store != null)
          watchWorkoutImporterProvider.overrideWithValue(
            (id, active) => ObjectBoxWatchWorkoutImporter(
              store,
              accountId: id,
              activeAccountId: active,
            ),
          ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      auth.dispose();
      await api.dispose();
    });
  }

  late final _FakeLink link;
  late final FakeAuthApi api;
  late final FakeBoundAccountStore bound;
  late final AccountAuthController auth;
  late final FakeHealthOverviewController health;
  late final ProviderContainer container;

  Future<void> start() async {
    await auth.restore();
    container.read(watchSyncControllerProvider);
    await container.read(trainLibraryProvider.future);
    await container.read(completedWorkoutHistoryProvider.future);
    await container.read(healthOverviewProvider.future);
  }
}

Future<void> _elapse(WidgetTester tester, Duration d) async {
  await tester.pump(d);
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

String _ack(String acked, {String? key, String result = 'stored'}) =>
    jsonEncode(
      Ack(
        messageId: '77777777-3333-4333-8333-00000000aaaa',
        sentAtUtc: '2026-11-24T02:31:00Z',
        accountKey: key ?? watchAccountKey(accountA),
        ackedMessageId: acked,
        result: result,
      ).toJson(),
    );

String _idOf(_Call context, String type) =>
    (jsonDecode((context.payload! as Map<String, String>)[type]!)
            as Map<String, Object?>)['message_id']!
        as String;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('signed in sends binding, plans and health in one context', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    await _elapse(tester, const Duration(milliseconds: 1900));
    expect(h.link.calls, isEmpty, reason: 'debounced for 2 s');
    await _elapse(tester, const Duration(milliseconds: 200));
    expect(h.link.contexts, hasLength(1));
    final ctx = h.link.contexts.single.payload! as Map<String, String>;
    expect(ctx.keys.toSet(), {
      'account_binding',
      'plans_snapshot',
      'health_snapshot',
    });
    for (final json in ctx.values) {
      final m = WatchMessage.fromJson(jsonDecode(json) as Map<String, Object?>);
      expect(m.accountKey, watchAccountKey(accountA));
    }
    expect(
      h.link.bodyOf(h.link.contexts.single, 'plans_snapshot')['plans'],
      hasLength(1),
    );
  });

  testWidgets('identical rebuild does not resend', (tester) async {
    final h = _Harness(tester);
    await h.start();
    await _elapse(tester, const Duration(seconds: 3));
    expect(h.link.contexts, hasLength(1));
    // Same content again (a provider rebuild): a new object, equal value.
    h.health.replace(
      overview(ownerId: accountA, readAt: DateTime(2026, 11, 24, 7, 42)),
    );
    await _elapse(tester, const Duration(seconds: 3));
    expect(h.link.contexts, hasLength(1));
  });

  testWidgets('health refresh resends only after 2 s', (tester) async {
    final h = _Harness(tester);
    await h.start();
    await _elapse(tester, const Duration(seconds: 3));
    expect(h.link.contexts, hasLength(1));
    h.health.replace(
      overview(
        ownerId: accountA,
        readAt: DateTime(2026, 11, 24, 7, 55),
        activity: SectionData(
          ActivityOverview(
            stepsToday: 9000,
            stepsDaily: const [],
            activeEnergyToday: null,
            activeEnergyDaily: const [],
            stepsWeekAverage: null,
          ),
        ),
      ),
    );
    await _elapse(tester, const Duration(milliseconds: 1900));
    expect(h.link.contexts, hasLength(1));
    await _elapse(tester, const Duration(milliseconds: 200));
    expect(h.link.contexts, hasLength(2));
    expect(
      h.link.bodyOf(h.link.contexts.last, 'health_snapshot')['steps'],
      9000,
    );
  });

  testWidgets('sign out sends account_cleared for the old key first', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    await _elapse(tester, const Duration(seconds: 3));
    h.link.calls.clear();
    await h.auth.signOut();
    await _elapse(tester, const Duration(milliseconds: 10));
    expect(h.link.calls.first.kind, 'transfer');
    final cleared = h.link.transferred(0) as AccountCleared;
    expect(cleared.accountKey, watchAccountKey(accountA));
    expect(cleared.wipeUnsent, isFalse);
    // The context carries the same clear, so a replay of the old context on
    // the watch cannot bring the account back; nothing else is sent after.
    final ctx = h.link.contexts.single.payload! as Map<String, String>;
    expect(ctx.keys, ['account_cleared']);
    final inContext = WatchMessage.fromJson(
      jsonDecode(ctx['account_cleared']!) as Map<String, Object?>,
    );
    expect(inContext, isA<AccountCleared>());
    expect(inContext.accountKey, watchAccountKey(accountA));
    expect((inContext as AccountCleared).wipeUnsent, isFalse);
    await _elapse(tester, const Duration(seconds: 3));
    expect(h.link.contexts, hasLength(1));
  });

  testWidgets('account switch A to B: cleared(A) then B binding', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    await _elapse(tester, const Duration(seconds: 3));
    h.link.calls.clear();
    await h.auth.signOut();
    h.api.verifiedId = accountB;
    await h.auth.requestCode('b@example.invalid');
    await h.auth.verifyCode('123456');
    expect(h.auth.userId, accountB);
    await _elapse(tester, const Duration(seconds: 3));
    final kinds = [for (final c in h.link.calls) c.kind];
    expect(kinds.first, 'transfer');
    expect((h.link.transferred(0)).accountKey, watchAccountKey(accountA));
    final last = h.link.contexts.last.payload! as Map<String, String>;
    final binding = WatchMessage.fromJson(
      jsonDecode(last['account_binding']!) as Map<String, Object?>,
    );
    expect(binding.accountKey, watchAccountKey(accountB));
    // B's context never carries A's key.
    for (final json in last.values) {
      expect(json, isNot(contains(watchAccountKey(accountA))));
    }
  });

  testWidgets('disposing the scope clears the watch like a sign out', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    await _elapse(tester, const Duration(seconds: 3));
    h.link.calls.clear();
    h.container.dispose();
    await _elapse(tester, const Duration(milliseconds: 10));
    final cleared = h.link.transferred(0) as AccountCleared;
    expect(cleared.accountKey, watchAccountKey(accountA));
    expect(cleared.wipeUnsent, isFalse);
  });

  testWidgets('account deletion sends wipe true', (tester) async {
    final h = _Harness(tester);
    await h.start();
    await _elapse(tester, const Duration(seconds: 3));
    h.link.calls.clear();
    await h.container
        .read(watchSyncControllerProvider)
        .accountDeleted(accountA);
    final cleared = h.link.transferred(0) as AccountCleared;
    expect(cleared.wipeUnsent, isTrue);
    expect(cleared.accountKey, watchAccountKey(accountA));
    final ctx = h.link.contexts.single.payload! as Map<String, String>;
    final inContext = WatchMessage.fromJson(
      jsonDecode(ctx['account_cleared']!) as Map<String, Object?>,
    ) as AccountCleared;
    expect(inContext.wipeUnsent, isTrue);
    expect(ctx.keys, ['account_cleared']);
  });

  testWidgets('a sign out while the context is being sent still clears', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    h.link.holdContext = Completer<void>();
    await _elapse(tester, const Duration(seconds: 3));
    expect(h.link.contexts, hasLength(1), reason: 'send is in flight');
    h.link.calls.clear();
    await h.auth.signOut();
    await _elapse(tester, const Duration(milliseconds: 10));
    h.link.holdContext!.complete();
    await _elapse(tester, const Duration(milliseconds: 10));
    final cleared = h.link.calls.where((c) => c.kind == 'transfer').toList();
    expect(cleared, hasLength(1));
    expect(
      (h.link.transferred(0) as AccountCleared).accountKey,
      watchAccountKey(accountA),
    );
  });

  testWidgets('a change in the watch state resends without a resume', (
    tester,
  ) async {
    final h = _Harness(tester, reachable: false);
    await h.start();
    await _elapse(tester, const Duration(seconds: 3));
    expect(h.link.calls, isEmpty);
    h.link.reachable = true;
    h.link.stateChanges.add(null);
    await _elapse(tester, const Duration(seconds: 3));
    expect(h.link.contexts, hasLength(1));
    // An identical state is sent again after a change, because the watch may
    // be a new one.
    h.link.stateChanges.add(null);
    await _elapse(tester, const Duration(seconds: 3));
    expect(h.link.contexts, hasLength(2));
  });

  testWidgets('the whole context stays under 60000 bytes', (tester) async {
    final h = _Harness(tester);
    final big = ProviderContainer(
      overrides: [
        accountAuthControllerProvider.overrideWithValue(h.auth),
        watchLinkProvider.overrideWithValue(h.link),
        watchMessageIdsProvider.overrideWithValue(_Ids()),
        wallClockProvider.overrideWithValue(() => DateTime(2026, 11, 24, 8)),
        localNowProvider.overrideWithValue(DateTime(2026, 11, 24, 8)),
        trainLibraryProvider.overrideWith(
          (ref) async => WorkoutLibrarySnapshot(
            exercises: const [],
            plans: [
              for (var i = 0; i < 150; i++)
                WorkoutPlanRecord(
                  uuid: 'plan-$i',
                  name: 'Synthetic plan ${i.toString().padLeft(3, '0')}',
                  description: '',
                  updatedAtMs: 0,
                  exercises: [
                    for (var e = 0; e < 40; e++)
                      PlanExerciseRecord(
                        uuid: 'pe-$i-$e',
                        exerciseUuid: 'ex-$e',
                        position: e,
                        targetSets: 3,
                        targetRepsMin: 8,
                        targetRepsMax: 12,
                        restSeconds: 90,
                      ),
                  ],
                ),
            ],
          ),
        ),
        programWeekProvider.overrideWithValue(null),
        completedWorkoutHistoryProvider.overrideWith(
          (ref) async => const WorkoutHistorySnapshot(sessions: []),
        ),
        fakeHealthOverview(h.health),
      ],
    );
    addTearDown(big.dispose);
    await h.auth.restore();
    big.read(watchSyncControllerProvider);
    await big.read(trainLibraryProvider.future);
    await big.read(completedWorkoutHistoryProvider.future);
    await big.read(healthOverviewProvider.future);
    await _elapse(tester, const Duration(seconds: 3));
    final ctx = h.link.contexts.single.payload! as Map<String, String>;
    expect(ctx.keys.toSet(), {
      'account_binding',
      'plans_snapshot',
      'health_snapshot',
    });
    final total = ctx.entries.fold<int>(
      0,
      (sum, e) => sum + utf8.encode(e.key).length + utf8.encode(e.value).length,
    );
    expect(total, lessThanOrEqualTo(60000));
  });

  testWidgets('not reachable sends nothing', (tester) async {
    final h = _Harness(tester, reachable: false);
    await h.start();
    await _elapse(tester, const Duration(seconds: 5));
    expect(h.link.calls, isEmpty);
    await h.auth.signOut();
    await _elapse(tester, const Duration(seconds: 5));
    expect(h.link.calls, isEmpty);
    await h.container
        .read(watchSyncControllerProvider)
        .accountDeleted(accountA);
    expect(h.link.calls, isEmpty);
  });

  testWidgets('becoming reachable sends on the next resume', (tester) async {
    final h = _Harness(tester, reachable: false);
    await h.start();
    await _elapse(tester, const Duration(seconds: 3));
    expect(h.link.calls, isEmpty);
    h.link.reachable = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _elapse(tester, const Duration(seconds: 3));
    expect(h.link.contexts, hasLength(1));
  });

  testWidgets('noop link on Android sends nothing and throws nothing', (
    tester,
  ) async {
    final h = _Harness(tester);
    final noop = ProviderContainer(
      overrides: [
        accountAuthControllerProvider.overrideWithValue(h.auth),
        watchLinkProvider.overrideWithValue(const NoopWatchLink()),
        wallClockProvider.overrideWithValue(() => DateTime(2026, 11, 24, 8)),
        localNowProvider.overrideWithValue(DateTime(2026, 11, 24, 8)),
        trainLibraryProvider.overrideWith((ref) async => _library),
        programWeekProvider.overrideWithValue(null),
        completedWorkoutHistoryProvider.overrideWith(
          (ref) async => const WorkoutHistorySnapshot(sessions: []),
        ),
        fakeHealthOverview(h.health),
      ],
    );
    addTearDown(noop.dispose);
    await h.auth.restore();
    final c = noop.read(watchSyncControllerProvider);
    await _elapse(tester, const Duration(seconds: 3));
    await c.accountDeleted(accountA);
    await h.auth.signOut();
    await _elapse(tester, const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  group('watch status', () {
    final confirmedNow = DateTime(2026, 11, 24, 8);

    testWidgets('stored ack for latest health marks synced', (tester) async {
      final h = _Harness(tester);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      expect(h.container.read(watchStatusProvider), isA<WatchWaiting>());
      final state = h.container.read(watchLinkStateProvider);
      expect(state.sentSummary, 'Health, 1 plan');
      expect(state.device.installed, isTrue);

      h.link.incoming.add(_ack(_idOf(h.link.contexts.last, 'health_snapshot')));
      await _elapse(tester, const Duration(milliseconds: 10));
      expect(h.container.read(watchStatusProvider), WatchSynced(confirmedNow));
      final store = await WatchStatusStore.open();
      expect(store.confirmedAt(watchAccountKey(accountA)), confirmedNow);
    });

    testWidgets('a duplicate ack for plans counts as confirmed', (
      tester,
    ) async {
      final h = _Harness(tester);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      h.link.incoming.add(
        _ack(
          _idOf(h.link.contexts.last, 'plans_snapshot'),
          result: 'duplicate',
        ),
      );
      await _elapse(tester, const Duration(milliseconds: 10));
      expect(h.container.read(watchStatusProvider), isA<WatchSynced>());
    });

    testWidgets('an ack for the previous context still counts', (tester) async {
      final h = _Harness(tester);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      final first = _idOf(h.link.contexts.last, 'health_snapshot');
      h.health.replace(
        overview(
          ownerId: accountA,
          readAt: DateTime(2026, 11, 24, 7, 55),
          activity: SectionData(
            ActivityOverview(
              stepsToday: 9000,
              stepsDaily: const [],
              activeEnergyToday: null,
              activeEnergyDaily: const [],
              stepsWeekAverage: null,
            ),
          ),
        ),
      );
      await _elapse(tester, const Duration(seconds: 3));
      expect(h.link.contexts, hasLength(2));
      h.link.incoming.add(_ack(first));
      await _elapse(tester, const Duration(milliseconds: 10));
      expect(h.container.read(watchStatusProvider), isA<WatchSynced>());
    });

    testWidgets('ack for another account is ignored', (tester) async {
      final h = _Harness(tester);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      h.link.incoming.add(
        _ack(
          _idOf(h.link.contexts.last, 'health_snapshot'),
          key: watchAccountKey(accountB),
        ),
      );
      await _elapse(tester, const Duration(milliseconds: 10));
      expect(h.container.read(watchStatusProvider), isA<WatchWaiting>());
      final store = await WatchStatusStore.open();
      expect(store.confirmedAt(watchAccountKey(accountA)), isNull);
      expect(store.confirmedAt(watchAccountKey(accountB)), isNull);
    });

    testWidgets('ack for an unknown message id is ignored', (tester) async {
      final h = _Harness(tester);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      h.link.incoming.add(_ack('77777777-3333-4333-8333-00000000ffff'));
      await _elapse(tester, const Duration(milliseconds: 10));
      expect(h.container.read(watchStatusProvider), isA<WatchWaiting>());
    });

    testWidgets('a rejected ack and junk messages are ignored', (tester) async {
      final h = _Harness(tester);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      final id = _idOf(h.link.contexts.last, 'health_snapshot');
      h.link.incoming.add(_ack(id, result: 'rejected'));
      h.link.incoming.add('not json');
      h.link.incoming.add('{"schema_version":1}');
      await _elapse(tester, const Duration(milliseconds: 10));
      expect(h.container.read(watchStatusProvider), isA<WatchWaiting>());
      expect(tester.takeException(), isNull);
    });

    testWidgets('a paired watch without the app is not installed', (
      tester,
    ) async {
      final h = _Harness(tester, reachable: false);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      expect(h.container.read(watchStatusProvider), isA<WatchNotInstalled>());
      expect(h.link.calls, isEmpty);
    });

    testWidgets('unsupported device stays hidden and sends nothing', (
      tester,
    ) async {
      final h = _Harness(tester);
      h.link.deviceOverride = WatchDeviceStatus.unsupported;
      await h.start();
      await _elapse(tester, const Duration(seconds: 5));
      expect(h.link.calls, isEmpty);
      expect(h.container.read(watchStatusProvider), isA<WatchHidden>());
    });

    testWidgets('sign out clears confirmed time and status becomes hidden', (
      tester,
    ) async {
      final h = _Harness(tester);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      h.link.incoming.add(_ack(_idOf(h.link.contexts.last, 'health_snapshot')));
      await _elapse(tester, const Duration(milliseconds: 10));
      final store = await WatchStatusStore.open();
      await store.dismissInstallHint();
      expect(h.container.read(watchStatusProvider), isA<WatchSynced>());

      await h.auth.signOut();
      await _elapse(tester, const Duration(milliseconds: 10));
      expect(h.container.read(watchStatusProvider), isA<WatchHidden>());
      expect(store.confirmedAt(watchAccountKey(accountA)), isNull);
      expect(store.installHintDismissed, isFalse);
    });

    testWidgets('a confirmed time from an earlier launch is picked up', (
      tester,
    ) async {
      final earlier = DateTime(2026, 11, 23, 9);
      final store = await WatchStatusStore.open();
      await store.setConfirmedAt(watchAccountKey(accountA), earlier);
      final h = _Harness(tester);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      expect(h.container.read(watchStatusProvider), WatchSynced(earlier));
    });

    testWidgets('dismissing the install hint is remembered', (tester) async {
      final h = _Harness(tester, reachable: false);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      expect(
        h.container.read(watchLinkStateProvider).installHintDismissed,
        isFalse,
      );
      await h.container
          .read(watchLinkStateProvider.notifier)
          .dismissInstallHint();
      expect(
        h.container.read(watchLinkStateProvider).installHintDismissed,
        isTrue,
      );
      expect((await WatchStatusStore.open()).installHintDismissed, isTrue);
    });

    testWidgets('Not now stays hidden after a watch state change and resync', (
      tester,
    ) async {
      final h = _Harness(tester, reachable: false);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      await h.container
          .read(watchLinkStateProvider.notifier)
          .dismissInstallHint();
      h.link.stateChanges.add(null);
      await _elapse(tester, const Duration(seconds: 3));
      h.container.read(localNowProvider);
      expect(
        h.container.read(watchLinkStateProvider).installHintDismissed,
        isTrue,
      );
      h.health.replace(
        overview(ownerId: accountA, readAt: DateTime(2026, 11, 24, 7, 58)),
      );
      await _elapse(tester, const Duration(seconds: 3));
      expect(
        h.container.read(watchLinkStateProvider).installHintDismissed,
        isTrue,
      );
    });

    testWidgets(
      'the first send is remembered as unconfirmed, the oldest stays',
      (tester) async {
        final h = _Harness(tester);
        await h.start();
        await _elapse(tester, const Duration(seconds: 3));
        final store = await WatchStatusStore.open();
        final key = watchAccountKey(accountA);
        expect(store.unconfirmedSince(key), confirmedNow);
        h.health.replace(
          overview(ownerId: accountA, readAt: DateTime(2026, 11, 24, 7, 59)),
        );
        h.link.stateChanges.add(null);
        await _elapse(tester, const Duration(seconds: 3));
        expect(store.unconfirmedSince(key), confirmedNow);
      },
    );

    testWidgets('a confirming ack clears the unconfirmed time', (tester) async {
      final h = _Harness(tester);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      h.link.incoming.add(_ack(_idOf(h.link.contexts.last, 'health_snapshot')));
      await _elapse(tester, const Duration(milliseconds: 10));
      final store = await WatchStatusStore.open();
      expect(store.unconfirmedSince(watchAccountKey(accountA)), isNull);
    });

    testWidgets('sign out clears the unconfirmed time', (tester) async {
      final h = _Harness(tester);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      await h.auth.signOut();
      await _elapse(tester, const Duration(milliseconds: 10));
      final store = await WatchStatusStore.open();
      expect(store.unconfirmedSince(watchAccountKey(accountA)), isNull);
    });

    testWidgets('opening the app after 3 days away shows synced, not stale', (
      tester,
    ) async {
      final earlier = DateTime(2026, 11, 21, 9);
      final store = await WatchStatusStore.open();
      await store.setConfirmedAt(watchAccountKey(accountA), earlier);
      final h = _Harness(tester);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      expect(h.container.read(watchStatusProvider), WatchSynced(earlier));
    });

    testWidgets('an unconfirmed send 48 hours old turns stale until an ack', (
      tester,
    ) async {
      final earlier = DateTime(2026, 11, 20, 9);
      final store = await WatchStatusStore.open();
      final key = watchAccountKey(accountA);
      await store.setConfirmedAt(key, earlier);
      await store.setUnconfirmedSince(key, DateTime(2026, 11, 22, 8));
      final h = _Harness(tester);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      expect(h.container.read(watchStatusProvider), WatchStale(earlier));
      h.link.incoming.add(_ack(_idOf(h.link.contexts.last, 'health_snapshot')));
      await _elapse(tester, const Duration(milliseconds: 10));
      expect(h.container.read(watchStatusProvider), WatchSynced(confirmedNow));
    });

    testWidgets('a reachability change refreshes status and resends nothing', (
      tester,
    ) async {
      final h = _Harness(tester);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      expect(h.link.contexts, hasLength(1));
      expect(h.container.read(watchLinkStateProvider).device.reachable, isTrue);
      h.link.deviceOverride = const WatchDeviceStatus(
        supported: true,
        paired: true,
        installed: true,
        reachable: false,
      );
      h.link.reachabilityChanges.add(null);
      await _elapse(tester, const Duration(seconds: 3));
      expect(h.link.contexts, hasLength(1));
      expect(
        h.container.read(watchLinkStateProvider).device.reachable,
        isFalse,
      );
    });

    testWidgets('no message subscription while the device is unsupported', (
      tester,
    ) async {
      final h = _Harness(tester);
      h.link.deviceOverride = WatchDeviceStatus.unsupported;
      await h.start();
      await _elapse(tester, const Duration(seconds: 5));
      expect(h.link.messageListens, 0);
    });

    testWidgets('messages are subscribed once the device is supported', (
      tester,
    ) async {
      final h = _Harness(tester);
      await h.start();
      expect(h.link.messageListens, 0);
      await _elapse(tester, const Duration(seconds: 3));
      h.link.stateChanges.add(null);
      await _elapse(tester, const Duration(seconds: 3));
      expect(h.link.messageListens, 1);
    });
  });

  group('completed workouts from the watch', () {
    late Directory dir;
    late Store store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('beyondrep-controller-');
      store = Store(getObjectBoxModel(), directory: dir.path);
    });
    tearDown(() {
      store.close();
      dir.deleteSync(recursive: true);
    });

    String completedJson({String? key}) {
      final json = jsonDecode(
        File(
          '../../contracts/watch_link/v1/fixtures/valid/'
          'completed_workout.json',
        ).readAsStringSync(),
      ) as Map<String, Object?>;
      json['account_key'] = key ?? watchAccountKey(accountA);
      return jsonEncode(json);
    }

    testWidgets('a completed_workout from the watch is imported and acked', (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      h.link.stateChanges.add(null);
      await _elapse(tester, const Duration(seconds: 3));
      final before = h.link.calls.where((c) => c.kind == 'transfer').length;
      h.link.incoming.add(completedJson());
      await _elapse(tester, const Duration(milliseconds: 50));
      expect(store.box<WorkoutSessionEntity>().count(), 1);
      final transfers = h.link.calls.where((c) => c.kind == 'transfer');
      expect(transfers.length, before + 1);
      final ack = h.link.transferred(before) as Ack;
      expect(ack.result, 'stored');
      expect(ack.accountKey, watchAccountKey(accountA));
      expect(ack.ackedMessageId, '77777777-3333-4333-8333-000000000009');
    });

    testWidgets("another account's completed_workout gets no ack", (
      tester,
    ) async {
      final h = _Harness(tester, store: store);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      h.link.stateChanges.add(null);
      await _elapse(tester, const Duration(seconds: 3));
      h.link.incoming.add(completedJson(key: watchAccountKey(accountB)));
      await _elapse(tester, const Duration(milliseconds: 50));
      expect(store.box<WorkoutSessionEntity>().count(), 0);
      expect(h.link.calls.where((c) => c.kind == 'transfer'), isEmpty);
    });

    testWidgets('an ack message is still handled as before', (tester) async {
      final h = _Harness(tester, store: store);
      await h.start();
      await _elapse(tester, const Duration(seconds: 3));
      h.link.stateChanges.add(null);
      await _elapse(tester, const Duration(seconds: 3));
      h.link.incoming.add(_ack(_idOf(h.link.contexts.last, 'health_snapshot')));
      await _elapse(tester, const Duration(milliseconds: 10));
      expect(
        h.container.read(watchStatusProvider),
        WatchSynced(DateTime(2026, 11, 24, 8)),
      );
      expect(store.box<WorkoutSessionEntity>().count(), 0);
    });
  });
}
