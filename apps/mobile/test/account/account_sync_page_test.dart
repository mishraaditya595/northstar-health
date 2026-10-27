import 'package:flutter/material.dart';
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
      expect(find.text('1 local-only workouts'), findsOneWidget);
      expect(find.text('Cloud restore paused'), findsOneWidget);
      expect(
        find.text(
          '2 blocked upload operations require review '
          '(operations may share a workout).',
        ),
        findsOneWidget,
      );
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
    await tester.scrollUntilVisible(
      find.text('Sign out of this device'),
      220,
    );
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

    await tester.scrollUntilVisible(
      find.text('Sign out of this device'),
      220,
    );
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

  testWidgets('unsigned page never touches a native store', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: AccountSyncPage())),
      ),
    );
    expect(find.text('Sign in to view account status.'), findsOneWidget);
  });
}
