import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/design/northstar_theme.dart';
import 'package:northstar_health/features/account/account_auth_provider.dart';
import 'package:northstar_health/features/account/account_sync_page.dart';
import 'package:northstar_health/features/account/account_sign_in_page.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_outbox.dart';

import '../support/fake_account_auth.dart';

Future<void> scrollTo(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text(label), 150);
  await tester.ensureVisible(find.text(label));
}

void main() {
  testWidgets('confirmed cleanup failure blocks account entry until retry', (
    tester,
  ) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore();
    final cleanup = FakeConfirmedDeletionCleanupStore()..saved = accountA;
    final cleaner = FakeLocalAccountDataCleaner()..failErase = true;
    final auth = controller(api, bound, cleanup: cleanup, cleaner: cleaner);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    expect(auth.confirmedLocalCleanupPending, true);

    await tester.pumpWidget(
      MaterialApp(home: AccountSignInPage(controller: auth)),
    );
    await tester.pumpAndSettle();
    expect(find.text('FINISH DATA REMOVAL'), findsOneWidget);
    expect(find.text('Retry local data removal'), findsOneWidget);
    expect(
      find.text('Erase local workouts and use another account'),
      findsNothing,
    );
    final signIn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Send sign-in code'),
    );
    expect(signIn.onPressed, isNull);

    cleaner.failErase = false;
    await tester.tap(find.text('Retry local data removal'));
    await tester.pumpAndSettle();
    expect(cleaner.erased, [accountA]);
    expect(cleanup.saved, isNull);
    expect(auth.confirmedLocalCleanupPending, false);
    expect(auth.userId, isNull);
  });

  testWidgets(
    'recovery shows both choices; cancelling either does not modify storage',
    (tester) async {
      final api = FakeAuthApi();
      final bound = FakeBoundAccountStore()..saved = accountA;
      final recovery = FakeDeletionRecoveryStore()..saved = accountA;
      final cleaner = FakeLocalAccountDataCleaner();
      final auth = controller(api, bound, recovery: recovery, cleaner: cleaner);
      addTearDown(auth.dispose);
      addTearDown(api.dispose);
      await auth.restore();
      expect(auth.userId, isNull);
      await tester.pumpWidget(
        MaterialApp(home: AccountSignInPage(controller: auth)),
      );
      await tester.pumpAndSettle();

      const keepLabel = 'Use another account (keep old data locked)';
      const eraseLabel = 'Erase local data and leave';
      expect(find.text('RECOVER ORIGINAL ACCOUNT'), findsOneWidget);
      expect(find.text('Send recovery code'), findsOneWidget);
      expect(find.text('Send sign-in code'), findsNothing);
      expect(find.text(keepLabel), findsOneWidget);
      expect(find.text(eraseLabel), findsOneWidget);

      await tester.ensureVisible(find.text(keepLabel));
      await tester.tap(find.text(keepLabel));
      await tester.pumpAndSettle();
      expect(
        find.text('Use another account and keep local data?'),
        findsOneWidget,
      );
      expect(
        find.textContaining('locked to the original'),
        findsOneWidget,
      );
      await tester.tap(find.text('Keep recovering'));
      await tester.pumpAndSettle();
      expect(cleaner.erased, isEmpty);
      expect(auth.deletionRecoveryPending, true);
      expect(bound.saved, accountA);
      expect(recovery.saved, accountA);

      await tester.ensureVisible(find.text(eraseLabel));
      await tester.tap(find.text(eraseLabel));
      await tester.pumpAndSettle();
      expect(find.text('Erase local data and leave recovery?'), findsOneWidget);
      expect(
        find.textContaining('permanently erase this device'),
        findsOneWidget,
      );
      await tester.tap(find.text('Keep recovering'));
      await tester.pumpAndSettle();
      expect(cleaner.erased, isEmpty);
      expect(auth.deletionRecoveryPending, true);
      expect(bound.saved, accountA);
      expect(recovery.saved, accountA);

      await tester.tap(find.text(eraseLabel));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, eraseLabel).last,
      );
      await tester.pumpAndSettle();
      expect(cleaner.erased, [accountA]);
      expect(recovery.saved, isNull);
      expect(bound.saved, isNull);
      expect(auth.userId, isNull);
      expect(find.text('Send sign-in code'), findsOneWidget);
    },
  );

  testWidgets(
    'keep-locked choice exits recovery without invoking local cleanup',
    (tester) async {
      final api = FakeAuthApi();
      final bound = FakeBoundAccountStore()..saved = accountA;
      final recovery = FakeDeletionRecoveryStore()..saved = accountA;
      final cleaner = FakeLocalAccountDataCleaner();
      final auth = controller(api, bound, recovery: recovery, cleaner: cleaner);
      addTearDown(auth.dispose);
      addTearDown(api.dispose);
      await auth.restore();
      await tester.pumpWidget(
        MaterialApp(home: AccountSignInPage(controller: auth)),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Use another account (keep old data locked)'),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('not be transferred'),
        findsOneWidget,
      );
      await tester.tap(find.text('Use another account'));
      await tester.pumpAndSettle();
      expect(auth.deletionRecoveryPending, false);
      expect(auth.userId, isNull);
      expect(recovery.saved, isNull);
      expect(bound.saved, isNull);
      expect(cleaner.erased, isEmpty);
      expect(find.text('Send sign-in code'), findsOneWidget);
    },
  );

  testWidgets('delete asks about unsynced data before even sending an OTP', (
    tester,
  ) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountAuthControllerProvider.overrideWithValue(auth),
          workoutSyncFlagsProvider.overrideWithValue(const {
            'unsent': WorkoutSyncFlag.notSynced,
            'local': WorkoutSyncFlag.localOnly,
          }),
        ],
        child: MaterialApp(
          theme: NorthstarTheme.build(Brightness.light),
          home: const AccountSyncPage(),
        ),
      ),
    );
    await scrollTo(tester, 'Permanently delete account');
    await tester.tap(find.text('Permanently delete account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('waiting for backup'), findsOneWidget);
    expect(
      find.textContaining('Export your cloud workout history FIRST'),
      findsOneWidget,
    );
    expect(api.deletionCodeSentTo, isNull);
    expect(bound.saved, accountA);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.deletionCodeSentTo, isNull);

    await scrollTo(tester, 'Permanently delete account');
    await tester.tap(find.text('Permanently delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send deletion code'));
    await tester.pumpAndSettle();
    expect(api.deletionCodeSentTo, 'owner@example.invalid');
    expect(api.deleteRequestedFor, isNull);
    expect(auth.deletionCodeSent, true);

    expect(api.deleteRequestedFor, isNull);
    // Use the real UI action, rather than invoking the controller directly.
    // A single text match avoids duplicate ancestor TextButton finders.
    final cancel = find.text('Cancel account deletion');
    await tester.scrollUntilVisible(
      cancel,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(cancel);
    await tester.pumpAndSettle();
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(auth.deletionCodeSent, false);
    expect(bound.saved, accountA);
  });

  testWidgets('expired session cannot start permanent deletion', (
    tester,
  ) async {
    final api = FakeAuthApi()
      ..sessionId = accountA
      ..expired = true;
    final auth = controller(api, FakeBoundAccountStore()..saved = accountA);
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
    await scrollTo(tester, 'Permanently delete account');
    final delete = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Permanently delete account'),
    );
    expect(delete.onPressed, isNull);
    expect(api.deletionCodeSentTo, isNull);
    expect(api.deleteRequestedFor, isNull);
  });
}
