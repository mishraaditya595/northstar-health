import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/account/account_auth_provider.dart';
import 'package:beyondrep/features/account/account_sign_in_page.dart';
import 'package:beyondrep/features/account/account_sync_page.dart';
import 'package:beyondrep/features/account/privacy_policy_link.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_outbox.dart';

import '../support/fake_account_auth.dart';

void main() {
  Future<void> pump(WidgetTester tester, PrivacyPolicyOpener open) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PrivacyPolicyLink(open: open)),
        ),
      );

  testWidgets('opens the published privacy policy', (tester) async {
    Uri? opened;
    await pump(tester, (uri) async {
      opened = uri;
      return true;
    });

    await tester.tap(find.text('Privacy policy'));
    await tester.pump();

    expect(opened, Uri.parse('https://beyondrep.in/privacy'));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('shows the address when no browser can open it', (tester) async {
    await pump(tester, (_) async => false);

    await tester.tap(find.text('Privacy policy'));
    await tester.pump();

    expect(
      find.text('Could not open a browser. Visit beyondrep.in/privacy.'),
      findsOneWidget,
    );
  });

  testWidgets('a thrown launch error is shown, not raised', (tester) async {
    await pump(tester, (_) async => throw Exception('no activity'));

    await tester.tap(find.text('Privacy policy'));
    await tester.pump();

    expect(
      find.text('Could not open a browser. Visit beyondrep.in/privacy.'),
      findsOneWidget,
    );
  });

  testWidgets('sign-in screen links the privacy policy', (tester) async {
    final api = FakeAuthApi();
    final auth = controller(api, FakeBoundAccountStore());
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();

    await tester.pumpWidget(
      MaterialApp(home: AccountSignInPage(controller: auth)),
    );
    expect(find.byType(PrivacyPolicyLink), findsOneWidget);
  });

  testWidgets('Account screen links the privacy policy', (tester) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final auth = controller(api, FakeBoundAccountStore()..saved = accountA);
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
          theme: BeyondRepTheme.build(Brightness.light),
          home: const AccountSyncPage(),
        ),
      ),
    );
    final link = find.byType(PrivacyPolicyLink);
    await tester.scrollUntilVisible(link, 160);
    expect(link, findsOneWidget);
  });
}
