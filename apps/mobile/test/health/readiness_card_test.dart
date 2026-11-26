import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/charts/score_ring.dart';
import 'package:beyondrep/core/design/hero_frame.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/health/domain/trend.dart';
import 'package:beyondrep/features/health/health_page.dart';
import 'package:beyondrep/features/health/widgets/readiness_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fake_health_overview.dart';
import '../support/fake_health_summary.dart';
import '../support/health_overview_fixtures.dart';

final clock = DateTime(2026, 11, 24, 7, 45);

const _up = TrendResult(
  direction: TrendDirection.up,
  tone: TrendTone.better,
  delta: 6,
);
const _flat = TrendResult(
  direction: TrendDirection.flat,
  tone: TrendTone.same,
  delta: 0.4,
);

ReadinessPart _part(ReadinessInput input) =>
    ReadinessPart(input: input, score: 70, weight: 0.25);

/// A ready score; drop [hrv] or [restingHr] to leave that input out.
Section<ReadinessOverview> ready({
  int value = 77,
  bool hrv = true,
  bool restingHr = true,
  bool sdnn = true,
}) => SectionData(
  ReadinessOverview(
    result: ReadinessReady(
      Readiness(
        value: value,
        band: readinessBandOf(value),
        parts: [
          if (hrv) _part(ReadinessInput.hrv),
          if (restingHr) _part(ReadinessInput.restingHr),
          _part(ReadinessInput.sleep),
        ],
      ),
    ),
    hasHrv: hrv,
    hasRestingHr: restingHr,
    hasSleep: true,
    hrvVsNormal: hrv ? _up : null,
    restingHrVsNormal: restingHr ? _flat : null,
    hrvBaseline: null,
    restingHrBaseline: null,
    hrvIsSdnn: sdnn,
  ),
);

Section<ReadinessOverview> notReady({
  bool noSleep = false,
  bool noHrvOrRhrToday = false,
  int? daysUntilBaseline,
  bool hasHrv = false,
  bool hasRestingHr = false,
  bool sdnn = true,
}) => SectionData(
  ReadinessOverview(
    result: ReadinessNotReady(
      noSleep: noSleep,
      noHrvOrRhrToday: noHrvOrRhrToday,
      daysUntilBaseline: daysUntilBaseline,
    ),
    hasHrv: hasHrv,
    hasRestingHr: hasRestingHr,
    hasSleep: !noSleep,
    hrvVsNormal: null,
    restingHrVsNormal: null,
    hrvBaseline: null,
    restingHrBaseline: null,
    hrvIsSdnn: sdnn,
  ),
);

Future<(FakeHealthOverviewController, FakeHealthSummaryController)> pump(
  WidgetTester tester,
  HealthOverview? value, {
  bool pending = false,
  double width = 390,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  HealthPlatformKind platform = HealthPlatformKind.appleHealth,
}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final overview = FakeHealthOverviewController(value, pending: pending);
  final summary = FakeHealthSummaryController(
    HealthConnected(readAt: clock, platform: platform),
  );
  final router = GoRouter(
    initialLocation: '/health',
    routes: [
      GoRoute(
        path: '/health',
        builder: (_, _) => const Scaffold(body: HealthPage()),
      ),
      // Stub until the readiness detail page exists.
      GoRoute(
        path: '/health/readiness',
        builder: (_, _) => const Scaffold(body: Text('detail readiness')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        fakeHealthSummary(summary),
        fakeHealthOverview(overview),
        healthClockProvider.overrideWithValue(() => clock),
        localNowProvider.overrideWithValue(clock),
      ],
      child: MaterialApp.router(
        theme: BeyondRepTheme.build(brightness),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  if (pending) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
  return (overview, summary);
}

void main() {
  testWidgets('the Low ring is red on the Health tab', (tester) async {
    await pump(tester, overview(readiness: ready(value: 41)));
    final ring = tester.widget<NsScoreRing>(find.byType(NsScoreRing));
    expect(ring.color, BeyondRepPalette.redDark);
  });

  testWidgets('ready: ring, band words, reasons and three chips', (
    tester,
  ) async {
    await pump(tester, overview(readiness: ready()));
    expect(find.text('READINESS'), findsOneWidget);
    expect(find.text('77'), findsOneWidget);
    expect(find.text('Good to train'), findsOneWidget);
    expect(
      find.text(
        'HRV (SDNN) above your normal · resting HR about your normal · '
        'slept 6h 12m',
      ),
      findsOneWidget,
    );
    expect(find.text('HRV (SDNN)'), findsWidgets);
    expect(find.text('52 ms'), findsOneWidget);
    // The Heart card also has a Resting HR label.
    expect(find.text('Resting HR'), findsNWidgets(2));
    expect(find.text('54 bpm'), findsOneWidget);
    expect(find.text('Sleep'), findsWidgets);
    expect(find.text('▲ better'), findsOneWidget);
    expect(find.text('● same'), findsOneWidget);
    expect(find.text('▼ worse'), findsOneWidget);
    expect(find.textContaining('Based on'), findsNothing);
    expect(
      find.bySemanticsLabel(
        RegExp(
          r'^Readiness 77 of 100, Good to train, HRV \(SDNN\) above your '
          r'normal',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('band words at 70, 69 and 49', (tester) async {
    for (final (value, words) in [
      (70, 'Good to train'),
      (69, 'Train as planned, watch effort'),
      (49, 'Recovery low'),
    ]) {
      await pump(tester, overview(readiness: ready(value: value)));
      expect(find.text(words), findsOneWidget);
      expect(find.text('$value'), findsOneWidget);
    }
  });

  testWidgets('no resting HR: based on HRV and sleep, chip shows a dash', (
    tester,
  ) async {
    await pump(tester, overview(readiness: ready(restingHr: false)));
    expect(
      find.text(
        'HRV (SDNN) above your normal · slept 6h 12m\nBased on HRV and sleep',
      ),
      findsOneWidget,
    );
    expect(find.text('—'), findsOneWidget);
    expect(find.text('None today'), findsOneWidget);
  });

  testWidgets('no HRV: based on sleep and resting HR', (tester) async {
    await pump(tester, overview(readiness: ready(hrv: false)));
    expect(
      find.text(
        'Resting HR about your normal · slept 6h 12m\n'
        'Based on sleep and resting HR',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Health Connect names RMSSD', (tester) async {
    await pump(
      tester,
      overview(
        platform: HealthPlatformKind.healthConnect,
        readiness: ready(sdnn: false),
      ),
      platform: HealthPlatformKind.healthConnect,
    );
    expect(
      find.textContaining('HRV (RMSSD) above your normal'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(NsHeroFrame),
        matching: find.textContaining('SDNN'),
      ),
      findsNothing,
    );
  });

  testWidgets('tapping the ready hero opens /health/readiness', (tester) async {
    await pump(tester, overview(readiness: ready()));
    await tester.tap(find.text('Good to train'));
    await tester.pumpAndSettle();
    expect(find.text('detail readiness'), findsOneWidget);
  });

  testWidgets('baseline building says how many days are left', (tester) async {
    await pump(
      tester,
      overview(readiness: notReady(daysUntilBaseline: 5, hasHrv: true)),
    );
    expect(
      find.text('Readiness starts after 5 more days with data.'),
      findsOneWidget,
    );
    expect(find.text('Building your normal for HRV (SDNN).'), findsOneWidget);
    expect(find.text('Good to train'), findsNothing);
    await tester.tap(
      find.text('Readiness starts after 5 more days with data.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('detail readiness'), findsNothing);
  });

  testWidgets('not enough data on iPhone lists what is missing', (
    tester,
  ) async {
    await pump(tester, overview(readiness: notReady(noHrvOrRhrToday: true)));
    expect(find.text('Not enough data for a score'), findsOneWidget);
    expect(
      find.textContaining(
        'A watch or ring that syncs to Apple Health provides these.',
      ),
      findsOneWidget,
    );
    expect(find.text('Sleep: 6h 12m'), findsOneWidget);
    expect(find.text('HRV: none'), findsOneWidget);
    expect(find.text('Resting HR: none'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Readiness: Not enough data for a score')),
      findsOneWidget,
    );
  });

  testWidgets('phone only on Health Connect: every input none, no zeros', (
    tester,
  ) async {
    await pump(
      tester,
      phoneOnly(platform: HealthPlatformKind.healthConnect),
      platform: HealthPlatformKind.healthConnect,
    );
    expect(find.text('Not enough data for a score'), findsOneWidget);
    expect(
      find.textContaining(
        'A watch or ring that syncs to Health Connect provides these.',
      ),
      findsOneWidget,
    );
    expect(find.text('Sleep: none'), findsOneWidget);
    expect(find.text('HRV: none'), findsOneWidget);
    expect(find.text('Resting HR: none'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('Not allowed taps Manage, failed taps Try again', (tester) async {
    final (_, summary) = await pump(
      tester,
      overview(readiness: const SectionGap(MetricGap.notAllowed)),
    );
    expect(
      find.bySemanticsLabel(RegExp('No Readiness data. Not allowed · Manage')),
      findsOneWidget,
    );
    await tester.tap(find.text('Not allowed · Manage'));
    await tester.pumpAndSettle();
    expect(summary.manageCalls, 1);

    final (c, _) = await pump(
      tester,
      overview(readiness: const SectionGap(MetricGap.failed)),
    );
    await tester.tap(find.text("Couldn't read · Try again"));
    await tester.pumpAndSettle();
    expect(c.refreshCalls, 1);
  });

  testWidgets("yesterday's score is not shown today; Try again re-reads", (
    tester,
  ) async {
    final (c, _) = await pump(
      tester,
      overview(readiness: ready(), readAt: DateTime(2026, 11, 23, 7, 42)),
    );
    expect(find.text('77'), findsNothing);
    expect(find.text('Good to train'), findsNothing);
    expect(find.text("Couldn't read · Try again"), findsOneWidget);
    await tester.tap(find.text("Couldn't read · Try again"));
    await tester.pumpAndSettle();
    expect(c.refreshCalls, 1);
  });

  testWidgets('a re-read in flight shows loading, not the old score', (
    tester,
  ) async {
    final (c, _) = await pump(
      tester,
      overview(readiness: ready(), readAt: DateTime(2026, 11, 23, 7, 42)),
    );
    c.setLoading();
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('Loading readiness')), findsOneWidget);
    expect(find.text('77'), findsNothing);
    expect(find.text("Couldn't read · Try again"), findsNothing);
  });

  testWidgets('loading shows a readiness spinner, no score', (tester) async {
    await pump(tester, null, pending: true);
    expect(find.bySemanticsLabel(RegExp('Loading readiness')), findsOneWidget);
    expect(find.text('Good to train'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('text scale 2.0 at 320 px, $brightness, no overflow', (
      tester,
    ) async {
      for (final readiness in [
        ready(),
        ready(restingHr: false),
        ready(value: 55),
        notReady(daysUntilBaseline: 5, hasHrv: true),
        notReady(noSleep: true, noHrvOrRhrToday: true),
        const SectionGap<ReadinessOverview>(MetricGap.failed),
      ]) {
        await pump(
          tester,
          overview(readiness: readiness),
          width: 320,
          textScale: 2,
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('ready readiness card has an About Readiness button', (
    tester,
  ) async {
    await pump(tester, overview(readiness: ready()));
    expect(find.bySemanticsLabel('About Readiness'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('About Readiness'));
    await tester.pumpAndSettle();
    expect(find.text('What it tells you'), findsOneWidget);
    expect(find.text('detail readiness'), findsNothing);
  });

  testWidgets('not enough data card has an About Readiness button', (
    tester,
  ) async {
    await pump(tester, overview());
    expect(find.bySemanticsLabel('About Readiness'), findsOneWidget);
  });

  group('readinessReasons training load', () {
    Readiness withRatio(double? ratio) => Readiness(
      value: 70,
      band: ReadinessBand.good,
      parts: [
        _part(ReadinessInput.sleep),
        if (ratio != null) _part(ReadinessInput.trainingLoad),
      ],
      loadRatio: ratio,
    );
    final data = (ready() as SectionData<ReadinessOverview>).value;

    test('adds training load above your usual when r is 1.4', () {
      final text = readinessReasons(overview(), data, withRatio(1.4));
      expect(text, endsWith('Slept 6h 12m · training load above your usual'));
    });

    test('says nothing at r 1.3 or without the part', () {
      expect(
        readinessReasons(overview(), data, withRatio(1.3)),
        isNot(contains('training load')),
      );
      expect(
        readinessReasons(overview(), data, withRatio(null)),
        isNot(contains('training load')),
      );
    });
  });
}
