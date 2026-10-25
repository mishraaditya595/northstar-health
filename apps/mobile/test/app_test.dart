import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/app/northstar_app.dart';
import 'package:northstar_health/features/account/account_auth_controller.dart';
import 'package:northstar_health/features/account/account_auth_provider.dart';

import 'support/fake_account_auth.dart';

Widget signedInApp() => ProviderScope(
  overrides: [
    accountAuthControllerProvider.overrideWithValue(
      AccountAuthController(FakeAuthApi(), FakeBoundAccountStore()),
    ),
  ],
  child: const NorthstarApp(),
);

void main() {
  testWidgets('Today shows fictional metrics and four tabs', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(signedInApp());
    await tester.pumpAndSettle();

    expect(find.text('SHOW UP.\nGET STRONG.'), findsOneWidget);
    expect(find.textContaining('FICTIONAL DEMO DATA'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Train'), findsOneWidget);
  });

  testWidgets('Tablet uses navigation rail', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(signedInApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
