import 'dart:async';

import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/health_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_summary.dart';

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
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fakeHealthSummary(controller),
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

  testWidgets('connected mixed states render four cards, never 0', (
    tester,
  ) async {
    final c = FakeHealthSummaryController(mixed);
    await pumpPage(tester, c);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Steps'), findsOneWidget);
    expect(find.text('Resting heart rate'), findsOneWidget);
    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('6h 18m'), findsOneWidget);
    expect(find.text('Apple Watch · ended 6:52 AM'), findsOneWidget);
    expect(find.text('No steps yet today'), findsOneWidget);
    expect(find.text('Not allowed · Manage'), findsOneWidget);
    expect(find.text("Couldn't read · Try again"), findsOneWidget);
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('0'), findsNothing);
    expect(find.textContaining(iosHint), findsNothing, reason: 'Android');
  });

  testWidgets('Not allowed taps manage, Try again taps refresh', (
    tester,
  ) async {
    final c = FakeHealthSummaryController(mixed);
    await pumpPage(tester, c);
    await tester.tap(find.text('Not allowed · Manage'));
    await tester.pumpAndSettle();
    expect(c.manageCalls, 1);
    expect(c.connectCalls, 0);
    await tester.tap(find.text("Couldn't read · Try again"));
    await tester.pumpAndSettle();
    expect(c.refreshCalls, 1);
  });

  testWidgets('iOS hint appears once when any metric has no data', (
    tester,
  ) async {
    final c = FakeHealthSummaryController(
      connected({for (final m in HealthMetric.values) m: const HealthNoData()}),
    );
    await pumpPage(tester, c);
    expect(find.textContaining(iosHint), findsOneWidget);
  });

  testWidgets('iOS steps of 0 show as no data', (tester) async {
    final c = FakeHealthSummaryController(
      connected({
        HealthMetric.steps: HealthMeasured(
          value: 0,
          measuredAt: now,
          source: 'x',
        ),
      }),
    );
    await pumpPage(tester, c);
    expect(find.text('No steps yet today'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('iOS steps of 0 alone still shows the hint once', (tester) async {
    final c = FakeHealthSummaryController(
      connected({
        for (final m in HealthMetric.values)
          m: HealthMeasured(value: 0 + 70, measuredAt: now, source: 'x'),
        HealthMetric.steps: HealthMeasured(
          value: 0,
          measuredAt: now,
          source: 'x',
        ),
      }),
    );
    await pumpPage(tester, c);
    expect(find.textContaining(iosHint), findsOneWidget);
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

  testWidgets('app resume rebuilds the summary', (tester) async {
    final c = FakeHealthSummaryController(mixed);
    await pumpPage(tester, c);
    final before = c.buildCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(c.buildCalls, before + 1);
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

  testWidgets('pull to refresh refreshes', (tester) async {
    final c = FakeHealthSummaryController(mixed);
    await pumpPage(tester, c);
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(c.refreshCalls, 1);
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
    await pumpPage(tester, c);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HealthPage)),
    );
    // Reload keeps the previous value; the cards must still render from it.
    c.buildGate = Completer<void>();
    container.invalidate(healthSummaryProvider);
    await tester.pump();
    expect(container.read(healthSummaryProvider).isLoading, isTrue);
    expect(find.text('6h 18m'), findsOneWidget);
    await tester.tap(find.text("Couldn't read · Try again"));
    await tester.tap(find.text('Not allowed · Manage'));
    await tester.pump();
    expect(c.refreshCalls, 0);
    expect(c.connectCalls, 0);
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

  testWidgets('tablet width lays cards out in two columns', (tester) async {
    await pumpPage(tester, FakeHealthSummaryController(mixed), width: 900);
    final sleep = tester.getTopLeft(find.text('Sleep'));
    final steps = tester.getTopLeft(find.text('Steps'));
    final hr = tester.getTopLeft(find.text('Resting heart rate'));
    expect(steps.dx, greaterThan(sleep.dx));
    expect(steps.dy, sleep.dy);
    expect(hr.dx, sleep.dx);
    expect(hr.dy, greaterThan(sleep.dy));
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
}
