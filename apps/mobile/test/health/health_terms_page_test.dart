import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/detail/health_terms_page.dart';
import 'package:beyondrep/features/health/domain/metric_explanations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_summary.dart';

Future<void> _pump(WidgetTester tester, HealthPlatformKind platform) async {
  tester.view.physicalSize = const Size(400, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        fakeHealthSummary(
          FakeHealthSummaryController(
            HealthConnected(readAt: DateTime(2026, 11, 24), platform: platform),
          ),
        ),
      ],
      child: MaterialApp(
        theme: BeyondRepTheme.build(Brightness.light),
        home: const HealthTermsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists every MetricKey sorted by title', (tester) async {
    await _pump(tester, HealthPlatformKind.appleHealth);
    final titles = [
      for (final k in MetricKey.values)
        explanationFor(k, HealthPlatformKind.appleHealth).title,
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    expect(find.text('Health terms'), findsOneWidget);
    var previousY = -1.0;
    for (final title in titles) {
      final finder = find.text(title);
      expect(finder, findsOneWidget, reason: title);
      final y = tester.getTopLeft(finder).dy;
      expect(y, greaterThan(previousY), reason: title);
      previousY = y;
    }
  });

  testWidgets('lists training load and workouts from other apps', (
    tester,
  ) async {
    await _pump(tester, HealthPlatformKind.healthConnect);
    expect(find.text('Training load'), findsOneWidget);
    expect(find.text('Workouts from other apps'), findsOneWidget);
    expect(
      find.text('Workouts other apps saved to Health Connect'),
      findsOneWidget,
    );
  });

  testWidgets('Health Connect shows Light sleep, Apple Health Core sleep', (
    tester,
  ) async {
    await _pump(tester, HealthPlatformKind.healthConnect);
    expect(find.text('Light sleep'), findsOneWidget);
    expect(find.text('Core sleep'), findsNothing);
    await _pump(tester, HealthPlatformKind.appleHealth);
    expect(find.text('Core sleep'), findsOneWidget);
    expect(find.text('Light sleep'), findsNothing);
  });

  testWidgets('tapping HRV opens its sheet without the terms link', (
    tester,
  ) async {
    await _pump(tester, HealthPlatformKind.appleHealth);
    final hrv = explanationFor(MetricKey.hrv, HealthPlatformKind.appleHealth);
    await tester.tap(find.text(hrv.title));
    await tester.pumpAndSettle();
    expect(find.text(hrv.what), findsOneWidget);
    expect(find.text('All health terms'), findsNothing);
  });
}
