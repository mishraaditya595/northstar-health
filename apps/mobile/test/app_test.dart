import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/app/floating_nav_bar.dart';
import 'package:northstar_health/app/northstar_app.dart';

void main() {
  testWidgets('Today shows fictional metrics and four tabs', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: NorthstarApp()));
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

    await tester.pumpWidget(const ProviderScope(child: NorthstarApp()));
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
}
