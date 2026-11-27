import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/dialogs.dart';
import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/features/account/account_auth_controller.dart';
import 'package:beyondrep/features/account/account_auth_provider.dart';
import 'package:beyondrep/features/watch/application/live_watch_workout.dart';
import 'package:beyondrep/features/watch/application/watch_sync_controller.dart';
import 'package:beyondrep/features/watch/data/watch_live_link.dart';
import 'package:beyondrep/features/watch/domain/watch_account_key.dart';
import 'package:beyondrep/features/watch/domain/watch_message.dart';
import 'package:beyondrep/features/watch/widgets/live_watch_auto_open.dart';
import 'package:beyondrep/features/watch/widgets/live_watch_workout_card.dart';
import 'package:beyondrep/features/watch/widgets/watch_workout_mirror_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

/// A `session_state` built from the shared fixture, so it stays valid.
String _state({
  int at = 0,
  String status = 'active',
  String session = _session,
  List<String> applied = const [],
  String? endReason,
  int? restSeconds,
}) {
  final json = jsonDecode(
    File('../../contracts/watch_link/v1/fixtures/valid/session_state.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  json['account_key'] = watchAccountKey(accountA);
  json['message_id'] =
      '99999999-3333-4333-8333-${at.toString().padLeft(12, '0')}';
  json['sent_at_utc'] = _t0.add(Duration(seconds: at)).toIso8601String();
  final body = json['body']! as Map<String, Object?>;
  body['session_id'] = session;
  body['status'] = status;
  body['started_at_utc'] = _t0.toIso8601String();
  body.remove('rest_deadline_utc');
  if (status == 'ended') {
    body.remove('current_set_id');
    body['end_reason'] = endReason ?? 'completed';
  }
  if (applied.isNotEmpty) body['applied_command_ids'] = applied;
  if (restSeconds != null) {
    for (final e in body['exercises']! as List) {
      for (final set in (e! as Map)['sets']! as List) {
        if ((set! as Map)['set_id'] == _set2) set['rest_seconds'] = restSeconds;
      }
    }
  }
  return jsonEncode(json);
}

class _Harness {
  _Harness(this.tester) {
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
      await close();
      await api.dispose();
      await link.dispose();
    });
  }

  bool _closed = false;

  /// The controller's 1 s timer must be gone before a test body ends.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    auth.dispose();
  }

  final WidgetTester tester;
  late final FakeAuthApi api;
  late final FakeBoundAccountStore bound;
  late final AccountAuthController auth;
  late final FakeWatchLiveLink link;
  late final ProviderContainer container;
  Duration elapsed = Duration.zero;
  late GoRouter router;

  Future<void> pump({
    String initial = '/train/watch-workout',
    double width = 400,
    double textScale = 1,
    Widget? home,
  }) async {
    await auth.restore();
    container.read(liveWatchWorkoutProvider);
    router = GoRouter(
      initialLocation: initial,
      routes: [
        ShellRoute(
          builder: (_, state, child) =>
              LiveWatchAutoOpen(location: state.uri.path, child: child),
          routes: [
            GoRoute(
              path: '/train',
              builder: (_, _) => Scaffold(
                body: Column(
                  children: [
                    const Text('Train home'),
                    const LiveWatchWorkoutCard(),
                    home ?? const SizedBox(),
                  ],
                ),
              ),
            ),
            GoRoute(
              path: '/today',
              builder: (_, _) => Scaffold(
                body: Column(
                  children: [
                    const Text('Today home'),
                    Builder(
                      builder: (context) => TextButton(
                        onPressed: () => context.push(liveWatchWorkoutRoute),
                        child: const Text('Open watch workout'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            GoRoute(
              path: liveWatchWorkoutRoute,
              builder: (_, _) => const WatchWorkoutMirrorPage(),
            ),
          ],
        ),
      ],
    );
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: BeyondRepTheme.build(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> receive(String json) async {
    link.receive(json);
    await tester.pump();
  }

  List<SessionCommand> get commands => [
    for (final json in link.sent)
      WatchMessage.fromJson(jsonDecode(json) as Map<String, Object?>)
          as SessionCommand,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the workout, completed values and the current set', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump();
    await h.receive(_state());
    expect(find.text('Synthetic push day'), findsOneWidget);
    expect(find.text('Apple Watch'), findsWidgets);
    expect(find.text('Synthetic press'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-current-set')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-set-$_set2')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('live-set-$_set2')),
        matching: find.byKey(const ValueKey('live-current-set')),
      ),
      findsOneWidget,
    );
    final load = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('weight-$_set1')),
        matching: find.byType(EditableText),
      ),
    );
    expect(load.controller.text, '60.0');
    await h.close();
  });

  testWidgets('logging a set shows Saving until the watch applied it', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump();
    await h.receive(_state());
    await tester.enterText(find.byKey(const ValueKey('weight-$_set2')), '62.5');
    await tester.enterText(find.byKey(const ValueKey('reps-$_set2')), '7');
    await tester.tap(find.byTooltip('Save set 2'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    final sent = h.commands.single;
    expect(sent.command, 'log_set');
    expect(sent.set?['set_id'], _set2);
    await h.receive(_state(at: 2, applied: [sent.commandId]));
    expect(find.text('Saving…'), findsNothing);
    await h.close();
  });

  testWidgets('out of reach: banner shown and controls are off', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump();
    await h.receive(_state());
    h.link.disconnect();
    await tester.pump();
    expect(find.text('Apple Watch out of reach'), findsOneWidget);
    final finish = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Finish'),
    );
    expect(finish.onPressed, isNull);
    await tester.tap(find.byTooltip('Save set 2'), warnIfMissed: false);
    await tester.pump();
    expect(h.link.sent, isEmpty);
    await h.close();
  });

  testWidgets('discard asks first and sends nothing when kept', (tester) async {
    final h = _Harness(tester);
    await h.pump();
    await h.receive(_state());
    await tester.tap(find.byTooltip('Discard workout'));
    await tester.pumpAndSettle();
    expect(find.text('Discard workout?'), findsOneWidget);
    await tester.tap(find.text('Keep training'));
    await tester.pumpAndSettle();
    expect(h.link.sent, isEmpty);
    await tester.tap(find.byTooltip('Discard workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard workout'));
    await tester.pumpAndSettle();
    expect(h.commands.single.command, 'discard');
    await h.close();
  });

  testWidgets('finish sends the command, then ended returns to Train', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump();
    await h.receive(_state());
    await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle();
    expect(h.commands.single.command, 'finish');
    await h.receive(_state(at: 3, status: 'ended'));
    await tester.pumpAndSettle();
    expect(find.text('Train home'), findsOneWidget);
    expect(find.text('Saved on your Apple Watch'), findsOneWidget);
    await h.close();
  });

  testWidgets('the rest button uses the planned rest of the set, else 90 s', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump();
    await h.receive(_state());
    expect(find.text('Start 90 s rest'), findsOneWidget);
    await tester.tap(find.text('Start 90 s rest'));
    await tester.pump();
    expect(h.commands.last.command, 'start_rest');
    expect(h.commands.last.restSeconds, 90);
    await h.receive(_state(at: 2, restSeconds: 120));
    expect(find.text('Start 120 s rest'), findsOneWidget);
    await tester.tap(find.text('Start 120 s rest'));
    await tester.pump();
    expect(h.commands.last.restSeconds, 120);
    await h.close();
  });

  testWidgets('ended returns to the page the person came from', (tester) async {
    final h = _Harness(tester);
    await h.pump(initial: '/today');
    await tester.tap(find.text('Open watch workout'));
    await tester.pumpAndSettle();
    await h.receive(_state());
    expect(find.text('Apple Watch workout'), findsOneWidget);
    await h.receive(_state(at: 3, status: 'ended'));
    await tester.pumpAndSettle();
    expect(find.text('Today home'), findsOneWidget);
    expect(find.text('Train home'), findsNothing);
    expect(find.text('Saved on your Apple Watch'), findsOneWidget);
    await h.close();
  });

  testWidgets('a fresh workout opens the page once per session', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump(initial: '/train');
    expect(find.text('Train home'), findsOneWidget);
    await h.receive(_state());
    await tester.pumpAndSettle();
    expect(find.text('Apple Watch workout'), findsOneWidget);
    h.router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Train home'), findsOneWidget);
    await h.receive(_state(at: 4));
    await tester.pumpAndSettle();
    expect(find.text('Apple Watch workout'), findsNothing);
    // The Train card still offers it.
    expect(find.text('Workout on your Apple Watch'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Apple Watch workout'), findsOneWidget);
    await h.close();
  });

  testWidgets(
    'a second workout in the same foreground does not open the page, coming back to the foreground does',
    (tester) async {
      final h = _Harness(tester);
      await h.pump(initial: '/train');
      await h.receive(_state());
      await tester.pumpAndSettle();
      expect(find.text('Apple Watch workout'), findsOneWidget);
      h.router.pop();
      await tester.pumpAndSettle();
      const other = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
      await h.receive(_state(at: 5, session: other));
      await tester.pumpAndSettle();
      expect(find.text('Apple Watch workout'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Apple Watch workout'), findsOneWidget);
      await h.close();
    },
  );

  testWidgets('the first fresh state after coming back opens the page', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump(initial: '/train');
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pumpAndSettle();
    await h.receive(_state());
    await tester.pumpAndSettle();
    expect(find.text('Apple Watch workout'), findsOneWidget);
    await h.close();
  });

  testWidgets('never opens over a dialog, opens on the next state after it', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump(
      initial: '/train',
      home: Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () => showNsConfirm(
            context,
            title: 'Test dialog',
            message: 'Synthetic',
            cancelLabel: 'No',
            confirmLabel: 'Yes',
          ),
          child: const Text('Ask'),
        ),
      ),
    );
    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    await h.receive(_state());
    await tester.pumpAndSettle();
    expect(find.text('Test dialog'), findsOneWidget);
    expect(find.text('Apple Watch workout'), findsNothing);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    await h.receive(_state(at: 3));
    await tester.pumpAndSettle();
    expect(find.text('Apple Watch workout'), findsOneWidget);
    await h.close();
  });

  testWidgets('an account switch forgets which sessions were opened', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump(initial: '/train');
    await h.receive(_state());
    await tester.pumpAndSettle();
    expect(h.container.read(liveWatchOpenedSessionsProvider), {_session});
    await h.auth.signOut();
    h.api.verifiedId = accountB;
    await tester.pump();
    expect(h.container.read(liveWatchOpenedSessionsProvider), isEmpty);
    await h.close();
  });

  testWidgets('a start button opens the mirror while the watch is live', (
    tester,
  ) async {
    final h = _Harness(tester);
    var started = false;
    await h.pump(
      initial: '/train',
      home: Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () {
            if (openLiveWatchWorkoutInstead(context, ref)) return;
            started = true;
          },
          child: const Text('Start test'),
        ),
      ),
    );
    await tester.tap(find.text('Start test'));
    await tester.pump();
    expect(started, isTrue);
    await h.receive(_state());
    await tester.pumpAndSettle();
    h.router.pop();
    await tester.pumpAndSettle();
    started = false;
    await tester.tap(find.text('Start test'));
    await tester.pumpAndSettle();
    expect(started, isFalse);
    expect(find.text('Apple Watch workout'), findsOneWidget);
    await h.close();
  });

  testWidgets('tablet width uses two columns without overflow', (tester) async {
    final h = _Harness(tester);
    await h.pump(width: 1000);
    await h.receive(_state());
    expect(tester.takeException(), isNull);
    expect(find.text('Synthetic press'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Finish'), findsOneWidget);
    await h.close();
  });

  testWidgets('200 percent text has no overflow', (tester) async {
    final h = _Harness(tester);
    await h.pump(textScale: 2);
    await h.receive(_state());
    expect(tester.takeException(), isNull);
    await h.close();
  });
}
