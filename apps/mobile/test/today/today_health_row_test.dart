import 'dart:async';

import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/charts/score_ring.dart';
import 'package:beyondrep/core/design/stats.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/domain/energy.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/health/widgets/readiness_hero.dart';
import 'package:beyondrep/features/health/widgets/today_health_row.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/progress/workout_history_state.dart';
import 'package:beyondrep/features/health/domain/outside_workouts.dart';
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
  Future<WorkoutHistorySnapshot> Function()? history,
  String? owner,
  DateTime? clock,
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
        if (owner != null) healthOwnerIdProvider.overrideWithValue(owner),
        healthClockProvider.overrideWithValue(() => clock ?? now),
        localNowProvider.overrideWithValue(clock ?? now),
        completedWorkoutHistoryProvider.overrideWith(
          (ref) =>
              history?.call() ??
              Future.value(WorkoutHistorySnapshot(sessions: sessions)),
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

  testWidgets('Workouts shows a dash and no claim while history loads', (
    tester,
  ) async {
    final never = Completer<WorkoutHistorySnapshot>();
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      history: () => never.future,
    );
    expect(find.text('Workouts'), findsOneWidget);
    expect(find.text('None yet today'), findsNothing);
  });

  testWidgets('Workouts shows no claim after a history error', (tester) async {
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      history: () => Future.error(StateError('synthetic')),
    );
    expect(find.text('Workouts'), findsOneWidget);
    expect(find.text('None yet today'), findsNothing);
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

  testWidgets('ready energy shows hero with ENERGY NOW · FAIR and advice', (
    tester,
  ) async {
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      overviewController: FakeHealthOverviewController(
        overview(readiness: _ready(55)),
      ),
    );
    expect(find.text('ENERGY NOW · FAIR'), findsOneWidget);
    expect(find.text('55'), findsOneWidget);
    expect(find.text('Train as planned, watch effort'), findsOneWidget);
    expect(find.bySemanticsLabel('About Energy'), findsOneWidget);
    // The grid keeps all four tiles beside the hero.
    expect(find.text('Resting HR'), findsOneWidget);
    expect(find.text('Workouts'), findsOneWidget);
  });

  group('energy hero', () {
    Energy energyOf(int value, int start) => Energy(
      value: value,
      band: readinessBandOf(value),
      start: start,
      items: const [],
    );

    HealthOverview withEnergy(
      int value,
      int start, {
      EnergyLearning learning = const EnergyLearning(),
      DateTime? wake,
      DateTime? readAt,
    }) {
      final startSection = _ready(start);
      return overview(
        readiness: startSection,
        readAt: readAt,
        energy: energySection(
          startSection,
          energy: energyOf(value, start),
          learning: learning,
          wake: wake ?? DateTime(2026, 11, 24, 6, 31),
        ),
      );
    }

    Future<void> pumpWith(
      WidgetTester tester,
      HealthOverview o, {
      double textScale = 1,
      double width = 390,
    }) => pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      overviewController: FakeHealthOverviewController(o),
      textScale: textScale,
      width: width,
    );

    testWidgets('shows energy now, the change since morning and a label', (
      tester,
    ) async {
      await pumpWith(tester, withEnergy(62, 78));
      expect(find.text('62'), findsOneWidget);
      expect(find.text('ENERGY NOW · FAIR'), findsOneWidget);
      expect(find.text('Train as planned, watch effort'), findsOneWidget);
      expect(
        find.text('Started today at 78 · down 16 since morning'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Energy now 62 of 100, Train as planned, watch effort. '
          'Started today at 78 · down 16 since morning. See why',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows the learning text in the hero', (tester) async {
      await pumpWith(
        tester,
        withEnergy(62, 78, learning: const EnergyLearning(workoutsNeeded: 12)),
      );
      const text =
          'Still learning your patterns: 12 more workouts for a calibrated score.';
      expect(find.text(text), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(text))),
        findsOneWidget,
      );
    });

    testWidgets('a building start shows the N more days row', (tester) async {
      await pumpWith(
        tester,
        overview(
          readiness: const SectionData(
            ReadinessOverview(
              result: ReadinessNotReady(daysUntilBaseline: 2),
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
      );
      expect(
        find.text('Energy starts after 2 more days with data.'),
        findsOneWidget,
      );
      expect(find.byType(NsScoreRing), findsNothing);
    });

    testWidgets('a ready start without a waking day shows no hero', (
      tester,
    ) async {
      final start = _ready(80);
      await pumpWith(
        tester,
        overview(
          readiness: start,
          energy: SectionData(
            EnergyOverview(
              day: DateTime(2026, 11, 24),
              wake: null,
              start: (start as SectionData<ReadinessOverview>).value,
              energy: null,
              learning: const EnergyLearning(),
            ),
          ),
        ),
      );
      expect(find.byType(NsScoreRing), findsNothing);
      expect(find.textContaining('ENERGY NOW'), findsNothing);
      expect(find.text('80'), findsNothing);
    });

    testWidgets('after midnight the waking day still shows its energy', (
      tester,
    ) async {
      final late = DateTime(2026, 11, 25, 0, 30);
      await pumpRow(
        tester,
        FakeHealthSummaryController(connectedAt(late)),
        clock: late,
        overviewController: FakeHealthOverviewController(
          withEnergy(
            62,
            78,
            wake: DateTime(2026, 11, 24, 7),
            readAt: DateTime(2026, 11, 25, 0, 28),
          ),
        ),
      );
      expect(find.text('ENERGY NOW · FAIR'), findsOneWidget);
    });

    testWidgets('text scale 2.0 at 320 dp with the learning line', (
      tester,
    ) async {
      await pumpWith(
        tester,
        withEnergy(62, 78, learning: const EnergyLearning(workoutsNeeded: 12)),
        textScale: 2,
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no text mentions readiness', (tester) async {
      await pumpWith(
        tester,
        withEnergy(62, 78, learning: const EnergyLearning(workoutsNeeded: 3)),
      );
      expect(find.textContaining('Readiness'), findsNothing);
      expect(find.textContaining('READINESS'), findsNothing);
    });
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

  testWidgets('tapping the hero chevron opens /health/readiness', (
    tester,
  ) async {
    final pushed = <String>[];
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      pushed: pushed,
      overviewController: FakeHealthOverviewController(
        overview(readiness: _ready(82)),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(ReadinessHero),
        matching: find.byIcon(Icons.chevron_right),
      ),
    );
    await tester.pumpAndSettle();
    expect(pushed, ['/health/readiness']);
  });

  testWidgets('the hero at 2x text has no overflow and no overlap', (
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
    final text = [
      tester.getRect(find.text('ENERGY NOW · FAIR')),
      tester.getRect(find.text('Train as planned, watch effort')),
    ];
    final controls = [
      tester.getRect(find.bySemanticsLabel('About Energy')),
      tester.getRect(
        find.descendant(
          of: find.byType(ReadinessHero),
          matching: find.byIcon(Icons.chevron_right),
        ),
      ),
    ];
    for (final rect in controls) {
      for (final t in text) {
        expect(rect.overlaps(t), isFalse);
      }
    }
  });

  testWidgets('Low hero uses the red ring colour', (tester) async {
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      overviewController: FakeHealthOverviewController(
        overview(readiness: _ready(41)),
      ),
    );
    expect(find.text('ENERGY NOW · LOW'), findsOneWidget);
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
      find.text('Energy starts after 4 more days with data.'),
      findsOneWidget,
    );
    expect(find.byType(NsScoreRing), findsNothing);
    expect(find.textContaining('ENERGY NOW'), findsNothing);
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
      expect(find.textContaining('Energy starts'), findsNothing);
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

  testWidgets('a merged outside workout does not raise the Workouts count, a '
      'standalone one does', (tester) async {
    final started = DateTime(2026, 11, 24, 7, 30);
    OutsideWorkout outside(String id, DateTime start) => OutsideWorkout(
      id: id,
      kind: OutsideWorkoutKind.running,
      start: start.toUtc(),
      end: start.add(const Duration(minutes: 30)).toUtc(),
      source: 'Synthetic app',
    );
    await pumpRow(
      tester,
      FakeHealthSummaryController(connectedAt(now)),
      owner: 'synthetic-owner',
      overviewController: FakeHealthOverviewController(
        overview(
          workouts: SectionData(
            WorkoutsOverview(
              outside: [
                // Inside the 07:30 session: merged.
                outside('merged', started.add(const Duration(minutes: 5))),
                // Mid-afternoon, no session: standalone.
                outside('alone', DateTime(2026, 11, 24, 15)),
              ],
            ),
          ),
        ),
      ),
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
    expect(
      find.byWidgetPredicate(
        (w) => w is StatTile && w.label == 'Workouts' && w.value == '2',
      ),
      findsOneWidget,
    );
    expect(find.text('Push day · 32 min'), findsOneWidget);
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
