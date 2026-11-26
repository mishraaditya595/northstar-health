import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/charts/score_ring.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/health/widgets/today_health_row.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/progress/workout_history_state.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
  List<String>? pushed,
  double width = 390,
  Brightness brightness = Brightness.dark,
  List<WorkoutSessionRecord> sessions = const [],
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(
          body: SingleChildScrollView(child: TodayHealthRow()),
        ),
      ),
      for (final path in [
        '/health/readiness',
        '/health/sleep',
        '/health/activity',
        '/health/heart',
        '/progress',
      ])
        GoRoute(
          path: path,
          builder: (_, state) {
            pushed?.add(state.uri.path);
            return Scaffold(body: Text('route $path'));
          },
        ),
    ],
  );
  addTearDown(router.dispose);
  tester.view.physicalSize = Size(width, 1200);
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
        localNowProvider.overrideWithValue(now),
        completedWorkoutHistoryProvider.overrideWith(
          (ref) async => WorkoutHistorySnapshot(sessions: sessions),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: BeyondRepTheme.build(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

HealthConnected connectedAt(DateTime at) =>
    HealthConnected(readAt: at, platform: HealthPlatformKind.appleHealth);

Section<ReadinessOverview> _ready(int value) => SectionData(
  ReadinessOverview(
    result: ReadinessReady(
      Readiness(
        value: value,
        band: readinessBandOf(value),
        parts: const [
          ReadinessPart(input: ReadinessInput.sleep, score: 50, weight: 1),
        ],
      ),
    ),
    hasHrv: false,
    hasRestingHr: false,
    hasSleep: true,
    hrvVsNormal: null,
    restingHrVsNormal: null,
    hrvBaseline: null,
    restingHrBaseline: null,
    hrvIsSdnn: true,
  ),
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

  testWidgets('grid shows Sleep, Steps, Resting HR and Workouts from the '
      'overview without its own reads', (tester) async {
    final reader = FakeHealthReader();
    final overviewController = FakeHealthOverviewController(overview());
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      reader: reader,
      overviewController: overviewController,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Steps'), findsOneWidget);
    expect(find.text('Resting HR'), findsOneWidget);
    expect(find.text('Workouts'), findsOneWidget);
    expect(find.text('Weight'), findsNothing);
    expect(find.text('6h 12m'), findsOneWidget);
    expect(find.text('8,214'), findsOneWidget);
    expect(find.text('54 bpm'), findsOneWidget);
    expect(find.text('Ended 6:31 AM'), findsOneWidget);
    expect(find.text('As of 7:42 AM'), findsOneWidget);
    expect(find.text('None yet today'), findsOneWidget);
    expect(find.text('From Apple Health · Apple Watch'), findsOneWidget);
    expect(reader.seriesCalls, isEmpty);
    expect(reader.sleepCalls, isEmpty);
    expect(reader.totalsCalls, isEmpty);
    expect(overviewController.refreshIfStaleCalls, 1);
  });

  testWidgets('the footer names no device when sleep and steps differ', (
    tester,
  ) async {
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      overviewController: FakeHealthOverviewController(
        overview(
          activity: SectionData(
            ActivityOverview(
              stepsToday: 8214,
              stepsDaily: fullActivity.stepsDaily,
              activeEnergyToday: null,
              activeEnergyDaily: const [],
              stepsWeekAverage: 9480,
              stepsSource: 'Synthetic phone',
            ),
          ),
        ),
      ),
    );
    expect(find.text('From Apple Health'), findsOneWidget);
  });

  testWidgets('the footer names no device that is the platform name', (
    tester,
  ) async {
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      overviewController: FakeHealthOverviewController(
        overview(
          platform: HealthPlatformKind.healthConnect,
          sleep: SectionData(sleepOverview(night(source: 'Health Connect'))),
          activity: SectionData(
            ActivityOverview(
              stepsToday: 8214,
              stepsDaily: fullActivity.stepsDaily,
              activeEnergyToday: null,
              activeEnergyDaily: const [],
              stepsWeekAverage: 9480,
              stepsSource: 'Health Connect',
            ),
          ),
        ),
      ),
    );
    expect(find.text('From Health Connect'), findsOneWidget);
  });

  testWidgets('the footer names Health Connect on Android', (tester) async {
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      overviewController: FakeHealthOverviewController(
        overview(platform: HealthPlatformKind.healthConnect),
      ),
    );
    expect(find.textContaining('From Health Connect'), findsOneWidget);
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
    // Three gaps plus Workouts with none today.
    expect(find.text('—'), findsNWidgets(4));
    expect(find.text('No sleep recorded last night'), findsOneWidget);
    expect(find.text('Not allowed · Manage'), findsOneWidget);
    expect(find.text("Couldn't read · Try again"), findsOneWidget);
    expect(find.text('0'), findsNothing);
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

  testWidgets('Android steps or resting HR not allowed beside other data '
      'reads Not allowed', (tester) async {
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      overviewController: FakeHealthOverviewController(
        overview(
          platform: HealthPlatformKind.healthConnect,
          heart: SectionData(
            HeartOverview(
              restingHr: null,
              restingHrDaily: const [],
              hrv: (day: DateTime(2026, 11, 24), value: 52),
              hrvDaily: [(day: DateTime(2026, 11, 24), value: 52)],
              vo2Max: null,
              vo2MaxDaily: const [],
              restingHrVsMonth: null,
              hrvVsNormal: null,
              hrvIsSdnn: false,
              restingHrGap: MetricGap.notAllowed,
            ),
          ),
          activity: SectionData(
            ActivityOverview(
              stepsToday: null,
              stepsDaily: const [],
              activeEnergyToday: 120,
              activeEnergyDaily: [(day: DateTime(2026, 11, 24), value: 120)],
              stepsWeekAverage: null,
              stepsGap: MetricGap.notAllowed,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Not allowed · Manage'), findsNWidgets(2));
    expect(find.text('No steps yet today'), findsNothing);
    expect(find.text('None in the last 30 days'), findsNothing);
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

  testWidgets('ready readiness shows hero with READINESS · FAIR and advice', (
    tester,
  ) async {
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      overviewController: FakeHealthOverviewController(
        overview(readiness: _ready(55)),
      ),
    );
    expect(find.text('READINESS · FAIR'), findsOneWidget);
    expect(find.text('55'), findsOneWidget);
    expect(find.text('Train as planned, watch effort'), findsOneWidget);
    expect(find.bySemanticsLabel('About Readiness'), findsOneWidget);
    // The grid keeps all four tiles beside the hero.
    expect(find.text('Resting HR'), findsOneWidget);
    expect(find.text('Workouts'), findsOneWidget);
  });

  testWidgets('hero tap navigates to /health/readiness', (tester) async {
    final pushed = <String>[];
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      pushed: pushed,
      overviewController: FakeHealthOverviewController(
        overview(readiness: _ready(82)),
      ),
    );
    await tester.tap(find.text('Good to train'));
    await tester.pumpAndSettle();
    expect(pushed, ['/health/readiness']);
  });

  testWidgets('Low hero uses the red ring colour', (tester) async {
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      overviewController: FakeHealthOverviewController(
        overview(readiness: _ready(41)),
      ),
    );
    expect(find.text('READINESS · LOW'), findsOneWidget);
    final ring = tester.widget<NsScoreRing>(find.byType(NsScoreRing));
    expect(ring.color, BeyondRepPalette.redDark);
  });

  testWidgets('building baseline shows the N more days row and no number', (
    tester,
  ) async {
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      overviewController: FakeHealthOverviewController(
        overview(
          readiness: const SectionData(
            ReadinessOverview(
              result: ReadinessNotReady(daysUntilBaseline: 4),
              hasHrv: true,
              hasRestingHr: false,
              hasSleep: true,
              hrvVsNormal: null,
              restingHrVsNormal: null,
              hrvBaseline: null,
              restingHrBaseline: null,
              hrvIsSdnn: true,
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('Readiness starts after 4 more days with data.'),
      findsOneWidget,
    );
    expect(find.byType(NsScoreRing), findsNothing);
    expect(find.textContaining('READINESS'), findsNothing);
  });

  testWidgets('not enough data and gaps show no hero and no row', (
    tester,
  ) async {
    for (final r in <Section<ReadinessOverview>>[
      const SectionGap(MetricGap.noData),
      const SectionData(
        ReadinessOverview(
          result: ReadinessNotReady(noSleep: true),
          hasHrv: false,
          hasRestingHr: false,
          hasSleep: false,
          hrvVsNormal: null,
          restingHrVsNormal: null,
          hrvBaseline: null,
          restingHrBaseline: null,
          hrvIsSdnn: true,
        ),
      ),
    ]) {
      await pumpRow(
        tester,
        FakeHealthSummaryController(connectedAt(now)),
        overviewController: FakeHealthOverviewController(
          overview(readiness: r),
        ),
      );
      expect(find.byType(NsScoreRing), findsNothing);
      expect(find.textContaining('Readiness starts'), findsNothing);
      expect(find.text('Sleep'), findsOneWidget);
      expect(find.text('Resting HR'), findsOneWidget);
    }
  });

  testWidgets('a readiness read yesterday shows no hero', (tester) async {
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      overviewController: FakeHealthOverviewController(
        overview(readiness: _ready(82), readAt: DateTime(2026, 11, 23, 22)),
      ),
    );
    expect(find.byType(NsScoreRing), findsNothing);
  });

  testWidgets("Workouts counts today's finished sessions and opens Progress", (
    tester,
  ) async {
    final pushed = <String>[];
    final started = DateTime(2026, 11, 24, 7, 30);
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      pushed: pushed,
      sessions: [
        WorkoutSessionRecord(
          uuid: 'a',
          name: 'Push day',
          status: WorkoutStatus.completed,
          startedAtUtc: started.toUtc(),
          originalOffsetMinutes: 0,
          revision: 1,
          completedAtUtc: started.add(const Duration(minutes: 32)).toUtc(),
        ),
      ],
    );
    expect(find.text('Push day · 32 min'), findsOneWidget);
    await tester.tap(find.text('Push day · 32 min'));
    await tester.pumpAndSettle();
    expect(pushed, ['/progress']);
  });

  testWidgets('data tiles open their Health detail', (tester) async {
    final pushed = <String>[];
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      pushed: pushed,
    );
    await tester.tap(find.text('Steps'));
    await tester.pumpAndSettle();
    expect(pushed, ['/health/activity']);
  });

  testWidgets('About Steps opens the sheet without opening the tile', (
    tester,
  ) async {
    final pushed = <String>[];
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      pushed: pushed,
    );
    await tester.tap(find.bySemanticsLabel('About Steps'));
    await tester.pumpAndSettle();
    expect(find.text('What it tells you'), findsOneWidget);
    expect(find.textContaining('Your daily average 9,'), findsOneWidget);
    expect(pushed, isEmpty);
  });

  testWidgets('text scale 2.0 uses one column and has no overflow', (
    tester,
  ) async {
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      textScale: 2,
      overviewController: FakeHealthOverviewController(
        overview(readiness: _ready(55)),
      ),
    );
    expect(tester.takeException(), isNull);
    final sleep = tester.getTopLeft(find.text('Sleep'));
    final steps = tester.getTopLeft(find.text('Steps'));
    expect(steps.dx, sleep.dx);
    expect(steps.dy, greaterThan(sleep.dy));
  });

  testWidgets('320 dp width uses one column and has no overflow', (
    tester,
  ) async {
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      width: 320,
      overviewController: FakeHealthOverviewController(
        overview(readiness: _ready(55)),
      ),
    );
    expect(tester.takeException(), isNull);
    final sleep = tester.getTopLeft(find.text('Sleep'));
    final steps = tester.getTopLeft(find.text('Steps'));
    expect(steps.dx, sleep.dx);
  });

  testWidgets('390 dp at normal text shows two columns', (tester) async {
    await pumpRow(tester, FakeHealthSummaryController(connectedAt(now)));
    final sleep = tester.getTopLeft(find.text('Sleep'));
    final steps = tester.getTopLeft(find.text('Steps'));
    expect(steps.dx, greaterThan(sleep.dx));
    expect(steps.dy, sleep.dy);
    final resting = tester.getTopLeft(find.text('Resting HR'));
    expect(resting.dy, greaterThan(sleep.dy));
  });

  testWidgets('the light theme renders without overflow', (tester) async {
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      brightness: Brightness.light,
      textScale: 1.3,
      overviewController: FakeHealthOverviewController(
        overview(readiness: _ready(41)),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
