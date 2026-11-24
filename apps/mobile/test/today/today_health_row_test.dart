import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/widgets/today_health_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_overview.dart';
import '../support/fake_health_reader.dart';
import '../support/fake_health_summary.dart';
import '../support/health_overview_fixtures.dart';

final now = DateTime(2026, 11, 24, 18, 20);

Future<void> pumpRow(
  WidgetTester tester,
  FakeHealthSummaryController controller, {
  double textScale = 1,
  FakeHealthReader? reader,
  FakeHealthOverviewController? overviewController,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fakeHealthSummary(controller),
        fakeHealthOverview(
          overviewController ?? FakeHealthOverviewController(overview()),
        ),
        healthReaderProvider.overrideWithValue(reader ?? FakeHealthReader()),
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

HealthConnected connectedAt(DateTime at) =>
    HealthConnected(readAt: at, platform: HealthPlatformKind.appleHealth);

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

  testWidgets('connected renders sleep, steps and resting HR from the '
      'overview without its own reads', (tester) async {
    final reader = FakeHealthReader();
    final overviewController = FakeHealthOverviewController(overview());
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      textScale: 2,
      reader: reader,
      overviewController: overviewController,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Steps'), findsOneWidget);
    expect(find.text('Resting HR'), findsOneWidget);
    expect(find.text('Weight'), findsNothing);
    expect(find.text('6h 12m'), findsOneWidget);
    expect(find.text('8,214'), findsOneWidget);
    expect(find.text('54 bpm'), findsOneWidget);
    expect(find.text('Apple Watch · ended 6:31 AM'), findsOneWidget);
    expect(find.text('Apple Health · as of 7:42 AM'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(reader.seriesCalls, isEmpty);
    expect(reader.sleepCalls, isEmpty);
    expect(reader.totalsCalls, isEmpty);
    expect(overviewController.refreshIfStaleCalls, 1);
  });

  testWidgets('gaps show a dash and a reason, never 0', (tester) async {
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      overviewController: FakeHealthOverviewController(
        overview(
          platform: HealthPlatformKind.healthConnect,
          sleep: const SectionGap(MetricGap.noData),
          heart: const SectionGap(MetricGap.notAllowed),
          activity: const SectionGap(MetricGap.failed),
        ),
      ),
    );
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('No sleep recorded last night'), findsOneWidget);
    expect(find.text('Not allowed · Manage'), findsOneWidget);
    expect(find.text("Couldn't read · Try again"), findsOneWidget);
  });

  testWidgets('an older night or resting HR is not shown as today', (
    tester,
  ) async {
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      overviewController: FakeHealthOverviewController(
        overview(
          sleep: SectionData(
            sleepOverview(night(date: DateTime(2026, 11, 22))),
          ),
          heart: SectionData(
            HeartOverview(
              restingHr: (day: DateTime(2026, 11, 21), value: 58),
              restingHrDaily: [(day: DateTime(2026, 11, 21), value: 58)],
              hrv: null,
              hrvDaily: const [],
              vo2Max: null,
              vo2MaxDaily: const [],
              restingHrVsMonth: null,
              hrvVsNormal: null,
              hrvIsSdnn: true,
            ),
          ),
          activity: const SectionGap(MetricGap.unsupported),
        ),
      ),
    );
    expect(find.text('No sleep recorded last night'), findsOneWidget);
    expect(find.text('58 bpm'), findsOneWidget);
    expect(find.text('21 Nov'), findsOneWidget);
    expect(find.text('Not available on this device'), findsOneWidget);
  });

  testWidgets('Not allowed opens Manage; Couldn\'t read re-reads', (
    tester,
  ) async {
    final summary = FakeHealthSummaryController(connectedAt(now));
    final overviewController = FakeHealthOverviewController(
      overview(
        platform: HealthPlatformKind.healthConnect,
        heart: const SectionGap(MetricGap.notAllowed),
        activity: const SectionGap(MetricGap.failed),
      ),
    );
    await pumpRow(tester, summary, overviewController: overviewController);
    await tester.tap(find.text('Not allowed · Manage'));
    await tester.pumpAndSettle();
    expect(summary.manageCalls, 1);
    await tester.tap(find.text("Couldn't read · Try again"));
    await tester.pumpAndSettle();
    expect(overviewController.refreshCalls, 1);
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
