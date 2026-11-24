import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/widgets/today_health_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_summary.dart';

final now = DateTime(2026, 11, 24, 18, 20);

Future<void> pumpRow(
  WidgetTester tester,
  FakeHealthSummaryController controller, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fakeHealthSummary(controller),
        healthClockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(
        theme: BeyondRepTheme.build(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(child: TodayHealthRow()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

HealthConnected connectedAt(DateTime at) => HealthConnected(
  readings: {for (final m in HealthMetric.values) m: const HealthNoData()},
  readAt: at,
  platform: HealthPlatformKind.appleHealth,
);

void main() {
  testWidgets('a stale reading is re-read when the row is shown', (
    tester,
  ) async {
    final c = FakeHealthSummaryController(
      connectedAt(now.subtract(const Duration(minutes: 6))),
    );
    await pumpRow(tester, c);
    expect(c.buildCalls, 2);
  });

  testWidgets('a fresh reading is not re-read when the row is shown', (
    tester,
  ) async {
    final c = FakeHealthSummaryController(
      connectedAt(now.subtract(const Duration(minutes: 4))),
    );
    await pumpRow(tester, c);
    expect(c.buildCalls, 1);
  });

  testWidgets('not connected shows a compact Connect card', (tester) async {
    final c = FakeHealthSummaryController(
      const HealthNotConnected(
        availability: HealthAvailability.available,
        platform: HealthPlatformKind.appleHealth,
      ),
    );
    await pumpRow(tester, c);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Sleep'), findsNothing);
    await tester.tap(find.text('Connect'));
    expect(c.connectCalls, 1);
  });

  testWidgets('connected shows sleep, steps and resting HR only', (
    tester,
  ) async {
    final c = FakeHealthSummaryController(
      HealthConnected(
        readings: {
          HealthMetric.sleep: HealthMeasured(
            value: 378,
            measuredAt: DateTime(2026, 11, 24, 6, 52),
            source: 'Apple Watch',
          ),
          HealthMetric.steps: HealthMeasured(
            value: 6420,
            measuredAt: now,
            source: 'x',
          ),
          HealthMetric.restingHeartRate: const HealthNoData(),
          HealthMetric.weight: HealthMeasured(
            value: 74.2,
            measuredAt: DateTime(2026, 11, 22),
            source: 'Withings',
          ),
        },
        readAt: now,
        platform: HealthPlatformKind.appleHealth,
      ),
    );
    await pumpRow(tester, c, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Steps'), findsOneWidget);
    expect(find.text('Resting HR'), findsOneWidget);
    expect(find.text('Weight'), findsNothing);
    expect(find.text('6h 18m'), findsOneWidget);
    expect(find.text('6,420'), findsOneWidget);
    expect(find.textContaining('52 min shorter'), findsNothing);
  });

  testWidgets('app resume rebuilds the summary', (tester) async {
    final c = FakeHealthSummaryController(
      const HealthNotConnected(
        availability: HealthAvailability.available,
        platform: HealthPlatformKind.appleHealth,
      ),
    );
    await pumpRow(tester, c);
    final before = c.buildCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(c.buildCalls, before + 1);
  });
}
