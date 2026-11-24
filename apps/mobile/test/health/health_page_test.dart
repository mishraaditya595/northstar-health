import 'dart:async';

import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/health_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_overview.dart';
import '../support/fake_health_summary.dart';
import '../support/health_overview_fixtures.dart';

const connectBody =
    "See today's sleep, steps, resting heart rate and weight. "
    'Read-only; stays on this phone.';
const iosHint =
    "Missing something? Check BeyondRep's access in the Health app.";
const disconnectHint =
    'To stop BeyondRep reading health data on this phone, turn it off in '
    'Health settings.';

final now = DateTime(2026, 11, 24, 18, 20);

HealthConnected connected(
  Map<HealthMetric, HealthReading> readings, {
  HealthPlatformKind platform = HealthPlatformKind.appleHealth,
}) => HealthConnected(readings: readings, readAt: now, platform: platform);

final mixed = connected({
  HealthMetric.sleep: HealthMeasured(
    value: 378,
    measuredAt: DateTime(2026, 11, 24, 6, 52),
    source: 'Apple Watch',
  ),
  HealthMetric.steps: const HealthNoData(),
  HealthMetric.restingHeartRate: const HealthNotAllowed(),
  HealthMetric.weight: const HealthReadFailed(),
}, platform: HealthPlatformKind.healthConnect);

Future<void> pumpPage(
  WidgetTester tester,
  FakeHealthSummaryController controller, {
  double width = 390,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool settle = true,
  DateTime? clock,
  FakeHealthOverviewController? overviewController,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      // Fresh scope per pump so a second pump uses its own fakes.
      key: UniqueKey(),
      overrides: [
        fakeHealthSummary(controller),
        fakeHealthOverview(
          overviewController ?? FakeHealthOverviewController(overview()),
        ),
        healthClockProvider.overrideWithValue(() => clock ?? now),
      ],
      child: MaterialApp(
        theme: BeyondRepTheme.build(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(body: HealthPage()),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  testWidgets('not connected shows the connect card, no demo content', (
    tester,
  ) async {
    final c = FakeHealthSummaryController(
      const HealthNotConnected(
        availability: HealthAvailability.available,
        platform: HealthPlatformKind.appleHealth,
      ),
    );
    await pumpPage(tester, c);
    expect(find.textContaining(connectBody), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.textContaining('FICTIONAL DEMO DATA'), findsNothing);
    expect(find.text('Imported activities'), findsNothing);
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(c.connectCalls, 1);
  });

  testWidgets('failed connect shows a message and re-enables Connect', (
    tester,
  ) async {
    final c = FakeHealthSummaryController(
      const HealthNotConnected(
        availability: HealthAvailability.available,
        platform: HealthPlatformKind.appleHealth,
      ),
    )..connectResult = false;
    await pumpPage(tester, c);
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't open health permissions. Try again."),
      findsOneWidget,
    );
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(c.connectCalls, 2);
  });

  testWidgets('needs install offers Get Health Connect', (tester) async {
    final c = FakeHealthSummaryController(
      const HealthNotConnected(
        availability: HealthAvailability.needsInstall,
        platform: HealthPlatformKind.healthConnect,
      ),
    );
    await pumpPage(tester, c);
    expect(find.text('Get Health Connect'), findsOneWidget);
    await tester.tap(find.text('Get Health Connect'));
    expect(c.connectCalls, 1);
  });

  testWidgets('unsupported explains and has no action', (tester) async {
    final c = FakeHealthSummaryController(
      const HealthNotConnected(
        availability: HealthAvailability.unsupported,
        platform: HealthPlatformKind.healthConnect,
      ),
    );
    await pumpPage(tester, c);
    expect(
      find.textContaining("Health Connect isn't available on this phone"),
      findsOneWidget,
    );
    expect(find.text('Connect'), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('connected renders the overview, not the summary readings', (
    tester,
  ) async {
    await pumpPage(tester, FakeHealthSummaryController(mixed));
    expect(find.text('6h 12m'), findsOneWidget);
    expect(find.text('6h 18m'), findsNothing, reason: 'Phase 3 card');
    expect(find.text('Resting heart rate'), findsNothing);
  });

  testWidgets('iOS hint appears once when a card has no data', (tester) async {
    await pumpPage(
      tester,
      FakeHealthSummaryController(connected(const {})),
      overviewController: FakeHealthOverviewController(phoneOnly()),
    );
    expect(find.textContaining(iosHint), findsOneWidget);
  });

  testWidgets('no iOS hint on Android or when every card has data', (
    tester,
  ) async {
    await pumpPage(tester, FakeHealthSummaryController(connected(const {})));
    expect(find.textContaining(iosHint), findsNothing);
    await pumpPage(
      tester,
      FakeHealthSummaryController(mixed),
      overviewController: FakeHealthOverviewController(
        phoneOnly(platform: HealthPlatformKind.healthConnect),
      ),
    );
    expect(find.textContaining(iosHint), findsNothing);
  });

  group('refresh when shown', () {
    HealthConnected readAt(DateTime at) => HealthConnected(
      readings: mixed.readings,
      readAt: at,
      platform: mixed.platform,
    );

    testWidgets('a reading older than 5 minutes is re-read', (tester) async {
      final c = FakeHealthSummaryController(
        readAt(now.subtract(const Duration(minutes: 6))),
      );
      await pumpPage(tester, c);
      expect(c.buildCalls, 2);
    });

    testWidgets('a reading from another calendar day is re-read', (
      tester,
    ) async {
      final c = FakeHealthSummaryController(
        readAt(DateTime(2026, 11, 23, 23, 58)),
      );
      await pumpPage(tester, c, clock: DateTime(2026, 11, 24, 0, 1));
      expect(c.buildCalls, 2);
    });

    testWidgets('a fresh same-day reading is not re-read', (tester) async {
      final c = FakeHealthSummaryController(
        readAt(now.subtract(const Duration(minutes: 4))),
      );
      await pumpPage(tester, c);
      expect(c.buildCalls, 1);
    });
  });

  testWidgets('app resume rebuilds the summary and refreshes a stale '
      'overview', (tester) async {
    final c = FakeHealthSummaryController(mixed);
    final o = FakeHealthOverviewController(overview());
    await pumpPage(tester, c, overviewController: o);
    expect(o.refreshIfStaleCalls, 1, reason: 'first show');
    final before = c.buildCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(c.buildCalls, before + 1);
    expect(o.refreshIfStaleCalls, 2);
    expect(o.refreshCalls, 0);
  });

  testWidgets('Disconnect calls the controller and shows the hint', (
    tester,
  ) async {
    final c = FakeHealthSummaryController(mixed);
    await pumpPage(tester, c);
    expect(find.text(disconnectHint), findsOneWidget);
    await tester.ensureVisible(find.text('Disconnect'));
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(c.disconnectCalls, 1);
  });

  testWidgets('pull to refresh refreshes summary and overview', (tester) async {
    final c = FakeHealthSummaryController(mixed);
    final o = FakeHealthOverviewController(overview());
    await pumpPage(tester, c, overviewController: o);
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(c.refreshCalls, 1);
    expect(o.refreshCalls, 1);
  });

  testWidgets('a failed overview refresh does not escape pull to refresh', (
    tester,
  ) async {
    final c = FakeHealthSummaryController(mixed);
    final o = _FailingRefresh(overview());
    await pumpPage(tester, c, overviewController: o);
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(o.refreshCalls, 1);
    expect(c.refreshCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double tap on Connect fires once while in flight', (
    tester,
  ) async {
    final c = FakeHealthSummaryController(
      const HealthNotConnected(
        availability: HealthAvailability.available,
        platform: HealthPlatformKind.appleHealth,
      ),
    )..connectGate = Completer<void>();
    await pumpPage(tester, c);
    await tester.tap(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(c.connectCalls, 1);
    c.connectGate!.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(c.connectCalls, 2);
  });

  testWidgets('actions are disabled while the summary is reloading', (
    tester,
  ) async {
    final c = FakeHealthSummaryController(mixed);
    final o = FakeHealthOverviewController(
      overview(
        sleep: const SectionGap(MetricGap.notAllowed),
        body: const SectionGap(MetricGap.failed),
      ),
    );
    await pumpPage(tester, c, overviewController: o);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HealthPage)),
    );
    // Reload keeps the previous value; the cards must still render.
    c.buildGate = Completer<void>();
    container.invalidate(healthSummaryProvider);
    await tester.pump();
    expect(container.read(healthSummaryProvider).isLoading, isTrue);
    expect(find.text('Not allowed · Manage'), findsOneWidget);
    await tester.tap(find.text("Couldn't read · Try again"));
    await tester.tap(find.text('Not allowed · Manage'));
    await tester.pump();
    expect(o.refreshCalls, 0);
    expect(c.manageCalls, 0);
    c.buildGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('first load shows a progress indicator, no demo values', (
    tester,
  ) async {
    await pumpPage(tester, FakeHealthSummaryController(null), settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('6h 18m'), findsNothing);
  });

  testWidgets('dark theme at 2x text scale renders without overflow', (
    tester,
  ) async {
    await pumpPage(
      tester,
      FakeHealthSummaryController(mixed),
      brightness: Brightness.dark,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Sleep'), findsOneWidget);
  });

  testWidgets('connected while the overview loads shows placeholders only', (
    tester,
  ) async {
    await pumpPage(
      tester,
      FakeHealthSummaryController(mixed),
      overviewController: FakeHealthOverviewController(null, pending: true),
      settle: false,
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Heart loading'), findsOneWidget);
    expect(find.text('6h 12m'), findsNothing);
    expect(find.text('6h 18m'), findsNothing);
    expect(find.text('Disconnect'), findsOneWidget);
  });

  testWidgets('an overview error offers Try again', (tester) async {
    final o = _ThrowingOverview();
    await pumpPage(
      tester,
      FakeHealthSummaryController(mixed),
      overviewController: o,
    );
    expect(find.text("Couldn't read health data."), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('loading')), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(o.refreshCalls, 1);
  });
}

class _FailingRefresh extends FakeHealthOverviewController {
  _FailingRefresh(super.initial);

  @override
  Future<void> refresh() async {
    await super.refresh();
    throw StateError('read failed');
  }
}

class _ThrowingOverview extends FakeHealthOverviewController {
  _ThrowingOverview() : super(null);

  @override
  Future<HealthOverview?> build() async => throw StateError('read failed');
}
