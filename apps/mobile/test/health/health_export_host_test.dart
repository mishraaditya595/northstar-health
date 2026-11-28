import 'package:beyondrep/features/account/account_auth_controller.dart';
import 'package:beyondrep/features/account/account_auth_provider.dart';
import 'package:beyondrep/features/health/application/health_export_host.dart';
import 'package:beyondrep/features/health/application/workout_health_export_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_account_auth.dart';

void main() {
  late FakeAuthApi api;
  late AccountAuthController auth;
  var kicks = 0;

  Future<void> boot({required bool signedIn}) async {
    api = FakeAuthApi();
    if (signedIn) api.sessionId = accountA;
    auth = controller(
      api,
      FakeBoundAccountStore()..saved = signedIn ? accountA : null,
    );
    await auth.restore();
    kicks = 0;
  }

  tearDown(() async {
    auth.dispose();
    await api.dispose();
  });

  Widget harness() => ProviderScope(
    overrides: [
      accountAuthControllerProvider.overrideWithValue(auth),
      healthExportKickProvider.overrideWithValue(() => kicks++),
    ],
    child: const MaterialApp(home: HealthExportHost(child: SizedBox())),
  );

  testWidgets('kicks after the first frame and on resume', (tester) async {
    await boot(signedIn: true);
    await tester.pumpWidget(harness());
    await tester.pump();
    expect(kicks, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(kicks, 2);
  });

  testWidgets('kicks when the signed-in user changes to non-null', (
    tester,
  ) async {
    await boot(signedIn: false);
    await tester.pumpWidget(harness());
    await tester.pump();
    final before = kicks;
    await auth.requestCode('a@example.test');
    await auth.verifyCode('123456');
    await tester.pump();
    expect(auth.userId, isNotNull);
    expect(kicks, before + 1);
  });

  testWidgets('does not kick again when the user stays the same', (
    tester,
  ) async {
    await boot(signedIn: true);
    await tester.pumpWidget(harness());
    await tester.pump();
    final before = kicks;
    api.emitSession(accountA);
    await tester.pump();
    expect(kicks, before);
  });
}
