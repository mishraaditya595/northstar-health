import 'dart:async';

import 'package:beyondrep/app/beyondrep_app.dart';
import 'package:beyondrep/app/floating_nav_bar.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/health_page.dart';
import 'package:beyondrep/features/health/widgets/sleep_card.dart';
import 'package:beyondrep/features/health/widgets/heart_card.dart';
import 'package:beyondrep/features/health/widgets/activity_card.dart';
import 'package:beyondrep/features/health/widgets/body_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fake_health_overview.dart';
import '../support/fake_health_summary.dart';
import '../support/health_overview_fixtures.dart';

final clock = DateTime(2026, 11, 24, 7, 45);

HealthConnected summary(HealthPlatformKind platform) =>
    HealthConnected(readAt: clock, platform: platform);

Future<FakeHealthOverviewController> pumpHealth(
  WidgetTester tester,
  HealthOverview? value, {
  bool pending = false,
  double width = 390,
  double height = 2400,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  HealthPlatformKind platform = HealthPlatformKind.appleHealth,
  FakeHealthSummaryController? summaryController,
  DateTime? now,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final overview = FakeHealthOverviewController(value, pending: pending);
  final router = GoRouter(
    initialLocation: '/health',
    routes: [
      GoRoute(
        path: '/health',
        builder: (_, _) => const Scaffold(body: HealthPage()),
      ),
      for (final name in ['sleep', 'heart', 'activity', 'body'])
        GoRoute(
          path: '/health/$name',
          builder: (_, _) => Scaffold(body: Text('detail $name')),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      // A fresh scope per pump, so a second pump in one test uses its own
      // fakes instead of keeping the first scope's.
      key: UniqueKey(),
      overrides: [
        fakeHealthSummary(
          summaryController ?? FakeHealthSummaryController(summary(platform)),
        ),
        fakeHealthOverview(overview),
        healthClockProvider.overrideWithValue(() => now ?? clock),
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
  return overview;
}

void main() {
  testWidgets('connected overview shows sleep score, stages and trend', (
    tester,
  ) async {
    await pumpHealth(tester, overview());
    expect(
      find.text('Tue 24 Nov · Apple Health · updated 7:42 AM'),
      findsOneWidget,
    );
    expect(find.text('74'), findsOneWidget);
    expect(find.text('6h 12m'), findsOneWidget);
    expect(find.text('Deep'), findsOneWidget);
    expect(find.text('Core'), findsOneWidget);
    expect(find.text('REM'), findsOneWidget);
    expect(find.text('Sleep HR'), findsOneWidget);
    expect(find.text('51 bpm'), findsOneWidget);
    expect(find.text('▼ 36m vs 7-day avg'), findsOneWidget);
    expect(find.text('Apple Watch · 11:48 PM – 6:31 AM'), findsOneWidget);
    // Heart, Activity, Body.
    expect(find.text('HRV (SDNN)'), findsOneWidget);
    expect(find.text('▼ 3 bpm this month · better'), findsOneWidget);
    expect(find.text('▲ 6 ms vs normal'), findsOneWidget);
    expect(find.text('VO₂ max 44.1'), findsOneWidget);
    expect(find.text('8,214'), findsOneWidget);
    expect(find.text('steps · avg 9,480'), findsOneWidget);
    expect(find.text('412 active kcal'), findsOneWidget);
    expect(find.text('▼ 0.9 kg in 30 days'), findsOneWidget);
    expect(find.text('Body fat 17.2%'), findsOneWidget);
  });

  testWidgets('phone-only shows explanations not zeros', (tester) async {
    await pumpHealth(tester, phoneOnly());
    expect(
      find.text(
        'No sleep recorded. A watch, ring or sleep app that writes to '
        'Apple Health fills this in.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        "iPhone alone doesn't measure heart rate. Shown when a wearable "
        'provides it.',
      ),
      findsOneWidget,
    );
    expect(find.text('—'), findsNWidgets(2));
    expect(find.textContaining('0 bpm'), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(find.text('6,930'), findsOneWidget);
    expect(find.text('Active calories need a watch'), findsOneWidget);
    expect(find.text('81.0'), findsOneWidget);
  });

  testWidgets('Health Connect phone-only names the platform', (tester) async {
    await pumpHealth(
      tester,
      phoneOnly(platform: HealthPlatformKind.healthConnect),
      platform: HealthPlatformKind.healthConnect,
    );
    expect(
      find.textContaining('writes to Health Connect fills this in.'),
      findsOneWidget,
    );
    expect(
      find.text('Shown when a watch or ring provides it.'),
      findsOneWidget,
    );
  });

  testWidgets('sleep without stages shows time asleep and why', (tester) async {
    await pumpHealth(
      tester,
      overview(
        sleep: SectionData(
          sleepOverview(
            night(deep: 0, light: 0, rem: 0, awake: 0),
            staged: false,
          ),
        ),
      ),
    );
    expect(find.text('6h 12m'), findsOneWidget);
    expect(
      find.text('Stages need a watch or ring that records them.'),
      findsOneWidget,
    );
    expect(find.text('Deep'), findsNothing);
  });

  testWidgets('an older last night is not shown as last night', (tester) async {
    await pumpHealth(
      tester,
      overview(
        sleep: SectionData(sleepOverview(night(date: DateTime(2026, 11, 21)))),
      ),
    );
    expect(find.text('No sleep recorded last night.'), findsOneWidget);
    expect(find.text('Last recorded 21 Nov'), findsOneWidget);
    expect(find.text('6h 12m'), findsNothing);
    expect(find.textContaining('vs 7-day avg'), findsNothing);
  });

  testWidgets("cards use the overview's day, not the clock's", (tester) async {
    // Read at 7:42 AM on 24 Nov, shown just after midnight: last night is
    // still the night of the date line, as on the detail pages.
    await pumpHealth(tester, overview(), now: DateTime(2026, 11, 25, 0, 10));
    expect(find.text('6h 12m'), findsOneWidget);
    expect(find.text('No sleep recorded last night.'), findsNothing);
  });

  testWidgets('needsAccess shows Allow more data and calls requestMoreAccess '
      'once', (tester) async {
    final c = await pumpHealth(
      tester,
      overview(
        needsMoreAccess: true,
        heart: const SectionGap(MetricGap.needsAccess),
      ),
    );
    expect(find.text('Allow more data'), findsOneWidget);
    await tester.tap(find.text('Allow more data'));
    await tester.pumpAndSettle();
    expect(c.requestMoreAccessCalls, 1);
  });

  testWidgets('needsMoreAccess with data on every card prompts once', (
    tester,
  ) async {
    final c = await pumpHealth(tester, overview(needsMoreAccess: true));
    expect(find.text('Allow more data'), findsOneWidget);
    await tester.tap(find.text('Allow more data'));
    await tester.pumpAndSettle();
    expect(c.requestMoreAccessCalls, 1);
  });

  testWidgets('Not allowed taps Manage, failed taps Try again', (tester) async {
    final summaryController = FakeHealthSummaryController(
      summary(HealthPlatformKind.healthConnect),
    );
    final c = await pumpHealth(
      tester,
      overview(
        platform: HealthPlatformKind.healthConnect,
        sleep: const SectionGap(MetricGap.notAllowed),
        body: const SectionGap(MetricGap.failed),
        activity: const SectionGap(MetricGap.unsupported),
      ),
      platform: HealthPlatformKind.healthConnect,
      summaryController: summaryController,
    );
    expect(find.text('Not available on this device'), findsOneWidget);
    await tester.tap(find.text('Not allowed · Manage'));
    await tester.pumpAndSettle();
    expect(summaryController.manageCalls, 1);
    await tester.tap(find.text("Couldn't read · Try again"));
    await tester.pumpAndSettle();
    expect(c.refreshCalls, 1);
  });

  testWidgets('Android Phase 3 upgrade: a declined metric reads Not allowed '
      'on its card', (tester) async {
    // HRV and active calories were declined; resting HR and steps are read.
    await pumpHealth(
      tester,
      overview(
        platform: HealthPlatformKind.healthConnect,
        heart: SectionData(
          HeartOverview(
            restingHr: (day: DateTime(2026, 11, 24), value: 54),
            restingHrDaily: daily(10, (i) => 56),
            hrv: null,
            hrvDaily: const [],
            vo2Max: null,
            vo2MaxDaily: const [],
            restingHrVsMonth: null,
            hrvVsNormal: null,
            hrvIsSdnn: false,
            hrvGap: MetricGap.notAllowed,
          ),
        ),
        activity: SectionData(
          ActivityOverview(
            stepsToday: 8214,
            stepsDaily: daily(7, (i) => 8000),
            activeEnergyToday: null,
            activeEnergyDaily: const [],
            stepsWeekAverage: 8000,
            energyGap: MetricGap.notAllowed,
          ),
        ),
        body: SectionData(
          BodyOverview(
            weight: null,
            weightDaily: const [],
            bodyFat: (day: DateTime(2026, 11, 22), value: 17.2),
            weightVsMonth: null,
            weightGap: MetricGap.failed,
          ),
        ),
        sleep: SectionData(
          SleepOverview(
            lastNight: night(),
            score: null,
            sleepAvgHr: null,
            nights: [night()],
            vsWeek: null,
            sleepHrGap: MetricGap.notAllowed,
          ),
        ),
      ),
      platform: HealthPlatformKind.healthConnect,
    );
    expect(find.text('None in 30 days'), findsNothing);
    expect(find.text('Not allowed · Manage'), findsOneWidget);
    expect(find.text('Active calories need a watch'), findsNothing);
    expect(find.text('Active calories: Not allowed · Manage'), findsOneWidget);
    expect(find.text('No weight in 30 days'), findsNothing);
    expect(find.text("Weight: Couldn't read · Try again"), findsOneWidget);
    expect(find.text('Sleep HR: Not allowed · Manage'), findsOneWidget);
  });

  testWidgets('body fat that could not be read says why on the card', (
    tester,
  ) async {
    await pumpHealth(
      tester,
      overview(
        body: SectionData(
          BodyOverview(
            weight: (day: DateTime(2026, 11, 24), value: 78.4),
            weightDaily: daily(30, (i) => 78),
            bodyFat: null,
            weightVsMonth: null,
            bodyFatGap: MetricGap.needsAccess,
          ),
        ),
      ),
    );
    expect(
      find.text("Body fat: BeyondRep isn't allowed to read this yet."),
      findsOneWidget,
    );
  });

  testWidgets('no active calories and no gap still says it needs a watch', (
    tester,
  ) async {
    await pumpHealth(tester, phoneOnly());
    expect(find.text('Active calories need a watch'), findsOneWidget);
    expect(find.textContaining('Not allowed'), findsNothing);
  });

  testWidgets('loading overview shows placeholders, no values', (tester) async {
    await pumpHealth(tester, null, pending: true);
    expect(find.bySemanticsLabel('Sleep loading'), findsOneWidget);
    expect(find.bySemanticsLabel('Body loading'), findsOneWidget);
    expect(find.text('6h 12m'), findsNothing);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('iOS steps of 0 today show no steps, never 0', (tester) async {
    await pumpHealth(
      tester,
      overview(
        activity: SectionData(
          ActivityOverview(
            stepsToday: null,
            stepsDaily: daily(7, (i) => 7000 + i * 100),
            activeEnergyToday: 300,
            activeEnergyDaily: daily(7, (i) => 300),
            stepsWeekAverage: 7300,
          ),
        ),
      ),
    );
    expect(find.text('No steps yet today'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp(r'^Activity: no steps yet today')),
      findsOneWidget,
    );
  });

  testWidgets('Allow more data stays visible but disabled while busy', (
    tester,
  ) async {
    final summaryController = FakeHealthSummaryController(
      summary(HealthPlatformKind.appleHealth),
    );
    await pumpHealth(
      tester,
      overview(heart: const SectionGap(MetricGap.needsAccess)),
      summaryController: summaryController,
    );
    final button = find.widgetWithText(TextButton, 'Allow more data');
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    summaryController.buildGate = Completer<void>();
    ProviderScope.containerOf(tester.element(find.byType(HealthPage)))
        .invalidate(healthSummaryProvider);
    await tester.pump();
    expect(button, findsOneWidget);
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    summaryController.buildGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('sleep semantics skip sleep heart rate when unknown', (
    tester,
  ) async {
    await pumpHealth(
      tester,
      overview(
        sleep: SectionData(
          SleepOverview(
            lastNight: night(),
            score: null,
            sleepAvgHr: null,
            nights: [night()],
            vsWeek: null,
          ),
        ),
      ),
    );
    final label = tester.getSemantics(find.byType(SleepCard)).label;
    expect(label, startsWith('Sleep: 6h 12m asleep.'));
    expect(label, isNot(contains('heart rate')));
    expect(label, isNot(contains('—')));
  });

  testWidgets('stage label is Core on Apple Health, Light on Health Connect', (
    tester,
  ) async {
    await pumpHealth(tester, overview());
    expect(find.text('Core'), findsOneWidget);
    expect(find.text('Light'), findsNothing);
    await pumpHealth(
      tester,
      overview(platform: HealthPlatformKind.healthConnect),
      platform: HealthPlatformKind.healthConnect,
    );
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Core'), findsNothing);
  });

  testWidgets('tapping Sleep navigates to /health/sleep', (tester) async {
    await pumpHealth(tester, overview());
    await tester.tap(find.byType(SleepCard));
    await tester.pumpAndSettle();
    expect(find.text('detail sleep'), findsOneWidget);
  });

  testWidgets('each data card opens its detail route', (tester) async {
    for (final (type, name) in [
      (HeartCard, 'heart'),
      (ActivityCard, 'activity'),
      (BodyCard, 'body'),
    ]) {
      await pumpHealth(tester, overview());
      await tester.ensureVisible(find.byType(type));
      await tester.tap(find.byType(type));
      await tester.pumpAndSettle();
      expect(find.text('detail $name'), findsOneWidget);
    }
  });

  testWidgets('a card with no data does not open a detail', (tester) async {
    await pumpHealth(tester, phoneOnly());
    await tester.tap(find.byType(SleepCard));
    await tester.pumpAndSettle();
    expect(find.text('detail sleep'), findsNothing);
  });

  testWidgets('tablet width puts Sleep and Heart side by side', (tester) async {
    await pumpHealth(tester, overview(), width: 800);
    final sleep = tester.getTopLeft(find.byType(SleepCard));
    final heart = tester.getTopLeft(find.byType(HeartCard));
    final activity = tester.getTopLeft(find.byType(ActivityCard));
    final body = tester.getTopLeft(find.byType(BodyCard));
    expect(heart.dy, sleep.dy);
    expect(heart.dx, greaterThan(sleep.dx));
    expect(body.dy, activity.dy);
    expect(activity.dy, greaterThan(sleep.dy));
  });

  testWidgets('phone width stacks Sleep above Heart', (tester) async {
    await pumpHealth(tester, overview());
    final sleep = tester.getTopLeft(find.byType(SleepCard));
    final heart = tester.getTopLeft(find.byType(HeartCard));
    expect(heart.dy, greaterThan(sleep.dy));
    expect(heart.dx, sleep.dx);
  });

  for (final brightness in Brightness.values) {
    testWidgets('text scale 2.0 and $brightness render without overflow', (
      tester,
    ) async {
      for (final value in [overview(), phoneOnly()]) {
        await pumpHealth(tester, value, textScale: 2, brightness: brightness);
        expect(tester.takeException(), isNull);
        await pumpHealth(
          tester,
          value,
          textScale: 2,
          brightness: brightness,
          width: 800,
          height: 5000,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('cards expose a readable semantics label', (tester) async {
    await pumpHealth(tester, overview());
    expect(
      find.bySemanticsLabel(RegExp(r'^Sleep: 6h 12m asleep, score 74')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Heart: resting heart rate 54 bpm')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Activity: 8,214 steps today')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Body: weight 78.4 kg')),
      findsOneWidget,
    );
  });

  testWidgets('app routes register the four detail pages under Health', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: BeyondRepApp()));
    await tester.pumpAndSettle();
    final router = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    ).read(routerProvider);
    for (final (path, title) in [
      ('/health/sleep', 'Sleep'),
      ('/health/heart', 'Heart'),
      ('/health/activity', 'Activity'),
      ('/health/body', 'Body'),
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, title), findsOneWidget);
      final nav = tester.widget<FloatingNavBar>(find.byType(FloatingNavBar));
      expect(nav.selectedIndex, 3, reason: path);
    }
  });
}
