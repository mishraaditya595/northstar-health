import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/train/train_library_state.dart';
import 'package:beyondrep/features/train/train_page.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/health/domain/trend.dart';
import 'package:beyondrep/features/health/widgets/readiness_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fake_health_overview.dart';
import '../support/health_overview_fixtures.dart';

const _down = TrendResult(
  direction: TrendDirection.down,
  tone: TrendTone.worse,
  delta: -6,
);

Section<ReadinessOverview> _ready(int value) => SectionData(
  ReadinessOverview(
    result: ReadinessReady(
      Readiness(
        value: value,
        band: readinessBandOf(value),
        parts: const [
          ReadinessPart(input: ReadinessInput.hrv, score: 40, weight: .5),
          ReadinessPart(input: ReadinessInput.sleep, score: 50, weight: .5),
        ],
      ),
    ),
    hasHrv: true,
    hasRestingHr: false,
    hasSleep: true,
    hrvVsNormal: _down,
    restingHrVsNormal: null,
    hrvBaseline: null,
    restingHrBaseline: null,
    hrvIsSdnn: true,
  ),
);

final _notReady = SectionData(
  const ReadinessOverview(
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
);

class _Failing extends FakeHealthOverviewController {
  _Failing() : super(null);

  @override
  Future<HealthOverview?> build() async => throw StateError('read failed');
}

Future<void> _pump(
  WidgetTester tester,
  FakeHealthOverviewController controller, {
  double textScale = 1,
  double width = 390,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: ReadinessNote()),
      ),
      GoRoute(
        path: '/health/readiness',
        builder: (_, _) => const Scaffold(body: Text('detail readiness')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [fakeHealthOverview(controller)],
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
  await tester.pumpAndSettle();
}

HealthOverview? _with(Section<ReadinessOverview> r) => overview(readiness: r);

List<String> _texts(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
];

void main() {
  testWidgets('low shows the full card', (tester) async {
    await _pump(tester, FakeHealthOverviewController(_with(_ready(48))));
    expect(find.text('Recovery is low today'), findsOneWidget);
    expect(
      find.text('HRV (SDNN) below your normal · slept 6h 12m'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Consider dropping a set per exercise or keeping effort around RPE 7.',
      ),
      findsOneWidget,
    );
    expect(find.text('Your plans are not changed'), findsOneWidget);
    expect(find.text('See why'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Readiness 48 of 100')), findsWidgets);
  });

  testWidgets('fair shows a chip row', (tester) async {
    await _pump(tester, FakeHealthOverviewController(_with(_ready(64))));
    expect(
      find.text('Readiness 64 · Train as planned, watch effort'),
      findsOneWidget,
    );
    expect(find.text('See why'), findsOneWidget);
    expect(find.text('Recovery is low today'), findsNothing);
  });

  testWidgets('good shows a chip row', (tester) async {
    await _pump(tester, FakeHealthOverviewController(_with(_ready(82))));
    expect(
      find.text('Readiness 82 · Good to train as planned'),
      findsOneWidget,
    );
    expect(find.text('See why'), findsOneWidget);
  });

  for (final (name, controller) in [
    ('NotReady', FakeHealthOverviewController(_with(_notReady))),
    (
      'a gap',
      FakeHealthOverviewController(_with(const SectionGap(MetricGap.noData))),
    ),
    ('not connected', FakeHealthOverviewController(null)),
    ('loading', FakeHealthOverviewController(null, pending: true)),
    ('an error', _Failing()),
  ]) {
    testWidgets('renders nothing for $name', (tester) async {
      await _pump(tester, controller);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_texts(tester), isEmpty);
    });
  }

  testWidgets('See why opens the readiness detail', (tester) async {
    await _pump(tester, FakeHealthOverviewController(_with(_ready(48))));
    await tester.tap(find.text('See why'));
    await tester.pumpAndSettle();
    expect(find.text('detail readiness'), findsOneWidget);
  });

  testWidgets('copy avoids directive and medical words', (tester) async {
    for (final v in [48, 64, 82]) {
      await _pump(tester, FakeHealthOverviewController(_with(_ready(v))));
      final all = _texts(tester).join(' ').toLowerCase();
      for (final word in [
        'must',
        'should rest',
        'diagnos',
        'illness',
        'sick',
        'medical',
        'doctor',
        'overtrain',
      ]) {
        expect(all, isNot(contains(word)), reason: '$v: $word');
      }
    }
  });

  for (final v in [48, 64, 82]) {
    for (final brightness in Brightness.values) {
      testWidgets('readiness $v fits 2x text at 390 px, $brightness', (
        tester,
      ) async {
        await _pump(
          tester,
          FakeHealthOverviewController(_with(_ready(v))),
          textScale: 2,
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('See why'), findsOneWidget);
      });
    }
  }

  testWidgets('Train still renders when the health overview fails', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const TrainPage())],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fakeHealthOverview(_Failing()),
          localNowProvider.overrideWithValue(DateTime(2026, 11, 24, 9)),
          trainLibraryProvider.overrideWith(
            (ref) async =>
                const WorkoutLibrarySnapshot(exercises: [], plans: []),
          ),
          activeWorkoutProvider.overrideWith(
            (ref) => const AsyncData<ActiveWorkoutView?>(null),
          ),
        ],
        child: MaterialApp.router(
          theme: BeyondRepTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start training'), findsOneWidget);
    expect(find.text('Recovery is low today'), findsNothing);
    expect(find.text('See why'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Try again'), findsNothing);
  });
}
