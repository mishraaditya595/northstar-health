import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/app/floating_nav_bar.dart';
import 'package:northstar_health/app/northstar_app.dart';
import 'package:northstar_health/features/account/account_auth_controller.dart';
import 'package:northstar_health/features/account/account_auth_provider.dart';

import 'support/fake_account_auth.dart';

Widget signedInApp([AccountAuthController? auth]) => ProviderScope(
  overrides: [
    accountAuthControllerProvider.overrideWithValue(
      auth ?? AccountAuthController(FakeAuthApi(), FakeBoundAccountStore()),
    ),
  ],
  child: const NorthstarApp(),
);

void main() {
  testWidgets('sign-out asks first and keeps the account on cancel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = AccountAuthController(
      FakeAuthApi()..sessionId = accountA,
      bound,
    );
    addTearDown(auth.dispose);
    await auth.restore();
    await tester.pumpWidget(signedInApp(auth));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Account and backup'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Account')),
      findsOneWidget,
    );
    expect(find.byType(BackButton), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Sign out of this device'), 180);
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Sign out of this device'),
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out of this device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(auth.userId, accountA);

    await tester.scrollUntilVisible(find.text('Sign out of this device'), 180);
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Sign out of this device'),
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out of this device'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(auth.userId, isNull);
    expect(bound.saved, isNull);
  });

  testWidgets('Account back button returns to Today', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(signedInApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Account and backup'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Full Body A'), findsOneWidget);
    expect(find.text('Cloud session ready'), findsNothing);
  });

  testWidgets('Today shows fictional metrics and four tabs', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(signedInApp());
    await tester.pumpAndSettle();

    expect(find.text('Full Body A'), findsOneWidget);
    expect(find.textContaining('FICTIONAL DEMO DATA'), findsOneWidget);
    expect(find.byType(FloatingNavBar), findsOneWidget);
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
    expect(find.byType(FloatingNavBar), findsNothing);
  });

  testWidgets('Switching tabs leaves no outgoing page mounted', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: NorthstarApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Train'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Energy check-in'), findsNothing);
  });

  testWidgets('Workout screen hides the bottom nav', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: NorthstarApp()));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingNavBar), findsOneWidget);

    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
        .read(routerProvider)
        .go('/train/workout');
    await tester.pumpAndSettle();

    expect(find.text('Workout in progress'), findsOneWidget);
    expect(find.byType(FloatingNavBar), findsNothing);
  });

  testWidgets('Workout screen hides the tablet rail too', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: NorthstarApp()));
    await tester.pumpAndSettle();
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
        .read(routerProvider)
        .go('/train/workout');
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsNothing);
  });
}
