import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/design/northstar_theme.dart';
import 'package:northstar_health/features/account/account_auth_provider.dart';
import 'package:northstar_health/features/account/account_sync_page.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_outbox.dart';

import '../support/fake_account_auth.dart';

Future<void> scrollTo(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text(label), 150);
  await tester.ensureVisible(find.text(label));
}

void main() {
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

    await scrollTo(tester, 'Cancel account deletion');
    expect(find.text('Verify and permanently delete'), findsOneWidget);
    expect(api.deleteRequestedFor, isNull);
    await tester.tap(find.text('Cancel account deletion'));
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
