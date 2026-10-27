import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/design/northstar_theme.dart';
import 'package:northstar_health/features/account/account_auth_provider.dart';
import 'package:northstar_health/features/account/account_sync_page.dart';
import 'package:northstar_health/features/sync/workout_conflict_resolution.dart';
import 'package:northstar_health/features/sync/workout_upload_coordinator.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_outbox.dart';

import '../support/fake_account_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shows account-local counts, paused cursor and does not claim synced',
    (tester) async {
      final api = FakeAuthApi()..sessionId = accountA;
      final auth = controller(api, FakeBoundAccountStore()..saved = accountA);
      addTearDown(auth.dispose);
      addTearDown(api.dispose);
      await auth.restore();

      var kicks = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountAuthControllerProvider.overrideWithValue(auth),
            workoutUploadKickProvider.overrideWithValue(() => kicks++),
            workoutSyncFlagsProvider.overrideWithValue(const {
              'w1': WorkoutSyncFlag.notSynced,
              'w2': WorkoutSyncFlag.needsReview,
              'w3': WorkoutSyncFlag.localOnly,
            }),
            blockedWorkoutCountProvider.overrideWithValue(2),
            workoutRestoreBlockedCodeProvider.overrideWithValue('invalid_page'),
          ],
          child: MaterialApp(
            theme: NorthstarTheme.build(Brightness.light),
            home: const Scaffold(body: AccountSyncPage()),
          ),
        ),
      );
      expect(find.text('Cloud session ready'), findsOneWidget);
      expect(find.text('1 queued for backup'), findsOneWidget);
      expect(find.text('1 need review'), findsOneWidget);
      expect(find.text('1 local-only workout'), findsOneWidget);
      // ListView lazily builds items below the initial viewport.
      await tester.scrollUntilVisible(
        find.textContaining('2 blocked upload operations'),
        160,
      );
      expect(
        find.text(
          '2 blocked upload operations require review '
          '(operations may share a workout).',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.text('Cloud restore paused'), 160);
      expect(find.text('Cloud restore paused'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Sync now'), -180);
      await tester.tap(find.text('Sync now'));
      await tester.pump();
      expect(kicks, 1);
      expect(find.textContaining('Sync requested'), findsOneWidget);
    },
  );

  testWidgets('expired session disables sync and preserves local counts', (
    tester,
  ) async {
    final api = FakeAuthApi()
      ..sessionId = accountA
      ..expired = true;
    final auth = controller(api, FakeBoundAccountStore()..saved = accountA);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    var kicks = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountAuthControllerProvider.overrideWithValue(auth),
          workoutUploadKickProvider.overrideWithValue(() => kicks++),
          workoutSyncFlagsProvider.overrideWithValue(const {
            'w1': WorkoutSyncFlag.notSynced,
          }),
        ],
        child: MaterialApp(
          theme: NorthstarTheme.build(Brightness.light),
          home: const Scaffold(body: AccountSyncPage()),
        ),
      ),
    );
    expect(find.text('Cloud backup paused'), findsOneWidget);
    expect(find.text('1 queued for backup'), findsOneWidget);
    final sync = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Sync now'),
    );
    expect(sync.onPressed, isNull);
    expect(kicks, 0);
  });

  testWidgets('sign out warns about pending work and keeps local partition', (
    tester,
  ) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final binding = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, binding);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountAuthControllerProvider.overrideWithValue(auth),
          workoutSyncFlagsProvider.overrideWithValue(const {
            'w1': WorkoutSyncFlag.notSynced,
          }),
        ],
        child: MaterialApp(
          theme: NorthstarTheme.build(Brightness.light),
          home: const Scaffold(body: AccountSyncPage()),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('Sign out of this device'), 220);
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Sign out of this device'),
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out of this device'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Some completed workouts still need backup'),
      findsOneWidget,
    );
    expect(binding.saved, accountA);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(auth.userId, accountA);
    expect(api.signedOut, false);

    await tester.scrollUntilVisible(find.text('Sign out of this device'), 220);
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Sign out of this device'),
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out of this device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out', skipOffstage: false).last);
    await tester.pumpAndSettle();
    expect(auth.userId, isNull);
    expect(binding.saved, isNull);
    expect(
      find.text('Signed out. Sign in to review account status.'),
      findsOneWidget,
    );
  });

  testWidgets('clean account explains uncertainty and disables review', (
    tester,
  ) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final binding = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, binding);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountAuthControllerProvider.overrideWithValue(auth),
          workoutSyncFlagsProvider.overrideWithValue(const {}),
        ],
        child: MaterialApp(
          theme: NorthstarTheme.build(Brightness.light),
          home: const AccountSyncPage(),
        ),
      ),
    );
    // Check the button before scrolling deeper into the now-longer export
    // section; slivers can recycle offscreen widgets after that scroll.
    await tester.scrollUntilVisible(find.text('Review sync issues'), 80);
    final review = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Review sync issues'),
    );
    expect(review.onPressed, isNull);
    await tester.scrollUntilVisible(
      find.textContaining('No unresolved sync issue is recorded'),
      -80,
    );
    expect(
      find.textContaining('does not verify that every workout is in the cloud'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(find.text('Sign out of this device'), 160);
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Sign out of this device'),
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out of this device'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Some completed workouts still need backup'),
      findsNothing,
    );
    expect(
      find.textContaining('All workouts, unfinished sessions'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(auth.userId, accountA);
    expect(binding.saved, accountA);
  });

  testWidgets('secure binding clear failure keeps account and shows message', (
    tester,
  ) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final binding = FakeBoundAccountStore()
      ..saved = accountA
      ..failClear = true;
    final auth = controller(api, binding);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountAuthControllerProvider.overrideWithValue(auth)],
        child: MaterialApp(
          theme: NorthstarTheme.build(Brightness.light),
          home: const AccountSyncPage(),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('Sign out of this device'), 220);
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Sign out of this device'),
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out of this device'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pump();
    expect(auth.userId, accountA);
    expect(binding.saved, accountA);
    expect(api.signedOut, false);
    expect(find.textContaining('Could not finish signing out'), findsOneWidget);
  });

  testWidgets('sign out is disabled while the secure clear is in flight', (
    tester,
  ) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final hold = Completer<void>();
    final binding = FakeBoundAccountStore()
      ..saved = accountA
      ..holdClear = hold;
    final auth = controller(api, binding);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountAuthControllerProvider.overrideWithValue(auth)],
        child: MaterialApp(
          theme: NorthstarTheme.build(Brightness.light),
          home: const AccountSyncPage(),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('Sign out of this device'), 220);
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Sign out of this device'),
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out of this device'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Sign out of this device'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pump();
    expect(auth.busy, true);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Sign out of this device'),
          )
          .onPressed,
      isNull,
    );
    hold.complete();
    await tester.pumpAndSettle();
    expect(auth.userId, isNull);
  });

  testWidgets('review action navigates to the existing recovery route', (
    tester,
  ) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final auth = controller(api, FakeBoundAccountStore()..saved = accountA);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    final router = GoRouter(
      initialLocation: '/today/account',
      routes: [
        GoRoute(
          path: '/today/account',
          builder: (_, _) => const AccountSyncPage(),
        ),
        GoRoute(
          path: '/today/sync/review',
          builder: (_, _) =>
              const Scaffold(body: Text('Recovery route reached')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountAuthControllerProvider.overrideWithValue(auth),
          workoutSyncFlagsProvider.overrideWithValue(const {
            'w1': WorkoutSyncFlag.needsReview,
          }),
        ],
        child: MaterialApp.router(
          theme: NorthstarTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('Review sync issues'), 180);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Review sync issues'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Review sync issues'));
    await tester.pumpAndSettle();
    expect(find.text('Recovery route reached'), findsOneWidget);
  });

  testWidgets('refresh action re-reads modified device state', (tester) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final auth = controller(api, FakeBoundAccountStore()..saved = accountA);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    Map<String, WorkoutSyncFlag> flags = {'w1': WorkoutSyncFlag.notSynced};
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountAuthControllerProvider.overrideWithValue(auth),
          workoutSyncFlagsProvider.overrideWith((ref) => flags),
        ],
        child: MaterialApp(
          theme: NorthstarTheme.build(Brightness.light),
          home: const AccountSyncPage(),
        ),
      ),
    );
    expect(find.text('1 queued for backup'), findsOneWidget);
    flags = {};
    expect(find.text('1 queued for backup'), findsOneWidget);
    await tester.tap(find.text('Refresh status'));
    await tester.pump();
    expect(find.text('0 queued for backup'), findsOneWidget);
    expect(find.text('Status re-read from this device.'), findsOneWidget);
  });

  testWidgets('unsigned page never touches a native store', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: AccountSyncPage())),
      ),
    );
    expect(find.text('Sign in to view account status.'), findsOneWidget);
  });
}
