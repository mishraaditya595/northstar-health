import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/charts/bar_series.dart';
import 'package:beyondrep/core/design/charts/trend_label.dart';
import 'package:beyondrep/features/health/application/health_details.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/detail/sleep_detail_page.dart';
import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:beyondrep/features/health/domain/sleep_nights.dart';
import 'package:beyondrep/features/health/domain/sleep_score.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fake_health_overview.dart';
import '../support/fake_health_reader.dart';
import '../support/health_overview_fixtures.dart';

const _owner = 'synthetic-owner';

class _Owner extends Notifier<String?> {
  @override
  String? build() => _owner;

  void set(String? owner) => state = owner;
}

final _ownerProvider = NotifierProvider<_Owner, String?>(_Owner.new);
final _now = DateTime(2026, 11, 24, 7, 42);

DateTime _day(int offset) => DateTime(2026, 11, 24 + offset);

SleepSegment _seg(DateTime from, DateTime to, SleepStage stage) =>
    (from: from, to: to, stage: stage, source: 'Synthetic watch');

/// Staged night 23:00 -> 06:30 ending on [date]; 450 min asleep, minus
/// [shortBy] minutes cut from the start.
List<SleepSegment> _staged(DateTime date, {int shortBy = 0}) {
  DateTime at(int h, [int m = 0]) =>
      DateTime(date.year, date.month, date.day, h, m);
  return [
    _seg(at(-1, shortBy), at(0, 30), SleepStage.light),
    _seg(at(0, 30), at(1, 30), SleepStage.deep),
    _seg(at(1, 30), at(3), SleepStage.light),
    _seg(at(3), at(4), SleepStage.rem),
    _seg(at(4), at(6), SleepStage.light),
    _seg(at(6), at(6, 30), SleepStage.rem),
  ];
}

/// Phone-only night 23:00 -> 06:00 with no stages.
List<SleepSegment> _unstaged(DateTime date) => [
  _seg(
    DateTime(date.year, date.month, date.day - 1, 23),
    DateTime(date.year, date.month, date.day, 6),
    SleepStage.asleepUnspecified,
  ),
];

/// Last night 11:48 PM -> 6:31 AM with one 10 min wake: 6h 33m asleep.
List<SleepSegment> _lastNight() {
  DateTime at(int h, int m) => DateTime(2026, 11, 24, h, m);
  return [
    _seg(DateTime(2026, 11, 23, 23, 48), at(0, 30), SleepStage.light),
    _seg(at(0, 30), at(1, 33), SleepStage.deep),
    _seg(at(1, 33), at(3, 0), SleepStage.light),
    _seg(at(3, 0), at(3, 10), SleepStage.awake),
    _seg(at(3, 10), at(4, 43), SleepStage.rem),
    _seg(at(4, 43), at(6, 31), SleepStage.light),
  ];
}

/// [days] staged prior nights plus last night.
List<SleepSegment> _history(int days) => [
  for (var i = -days; i < 0; i++) ..._staged(_day(i)),
  ..._lastNight(),
];

HealthSample _sample(DateTime at, double value) =>
    (from: at, to: at, value: value, source: 'Synthetic watch');

/// The overview the page would get: the last 31 nights of [segments].
HealthOverview _overview(
  List<SleepSegment> segments, {
  HealthPlatformKind platform = HealthPlatformKind.appleHealth,
  DateTime? readableFrom,
}) {
  final nights = [
    for (final n in buildNights(segments))
      if (!n.date.isBefore(_day(-30))) n,
  ];
  final last = nights.last;
  return HealthOverview(
    ownerId: _owner,
    readAt: _now,
    platform: platform,
    readableFrom: readableFrom,
    needsMoreAccess: false,
    sleep: SectionData(
      SleepOverview(
        lastNight: last,
        score: scoreSleep(
          last,
          priorNights: nights.sublist(0, nights.length - 1),
        ),
        sleepAvgHr: null,
        nights: nights,
        vsWeek: null,
      ),
    ),
    heart: SectionData(fullHeart),
    activity: SectionData(fullActivity),
    body: SectionData(fullBody),
  );
}

Future<void> _pump(
  WidgetTester tester,
  HealthOverview overview,
  FakeHealthReader reader, {
  double textScale = 1,
  Brightness brightness = Brightness.light,
  GoRouter? router,
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Widget scale(BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fakeHealthOverview(FakeHealthOverviewController(overview)),
        healthReaderProvider.overrideWithValue(reader),
        healthOwnerIdProvider.overrideWithValue(_owner),
        healthClockProvider.overrideWithValue(() => _now),
      ],
      child: router == null
          ? MaterialApp(
              theme: BeyondRepTheme.build(brightness),
              builder: scale,
              home: const SleepDetailPage(),
            )
          : MaterialApp.router(
              theme: BeyondRepTheme.build(brightness),
              builder: scale,
              routerConfig: router,
            ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectRange(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('last-night view shows timeline semantics and contributors', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final reader = FakeHealthReader()
      ..series[HealthSeriesType.heartRate] = [
        _sample(DateTime(2026, 11, 24, 1), 50),
        _sample(DateTime(2026, 11, 24, 3, 10), 46),
        _sample(DateTime(2026, 11, 24, 5), 55),
      ];
    await _pump(tester, _overview(_history(14)), reader);

    expect(find.text('6h 33m asleep'), findsOneWidget);
    expect(find.text('In bed 6h 43m · 98% efficient'), findsOneWidget);
    expect(find.text('11:48 PM – 6:31 AM · Synthetic watch'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Sleep stages, 11:48 PM to 6:31 AM')),
      findsOneWidget,
    );
    expect(find.text('16% · normal 15–20%'), findsOneWidget);
    expect(find.text('24% · normal 20–25%'), findsOneWidget);
    expect(find.text('Core'), findsWidgets);
    expect(find.text('Avg 50 · lowest 46 bpm at 3:10 AM'), findsOneWidget);
    expect(find.text('What made the score'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('Short · 6h 33m of ~7h 30m'), findsOneWidget);
    expect(find.text('Bedtime consistency'), findsOneWidget);
    expect(find.text('48 min later than usual'), findsOneWidget);
    expect(find.text('Deep sleep'), findsOneWidget);
    expect(find.text('REM sleep'), findsOneWidget);
    expect(find.text('Efficiency'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('Android names light sleep Light', (tester) async {
    await _pump(
      tester,
      _overview(_history(14), platform: HealthPlatformKind.healthConnect),
      FakeHealthReader(platform: HealthPlatformKind.healthConnect),
    );

    expect(find.text('Light'), findsOneWidget);
  });

  testWidgets('extras absent hides breathing/oxygen/temperature tiles', (
    tester,
  ) async {
    await _pump(tester, _overview(_history(14)), FakeHealthReader());

    expect(find.text('Breathing'), findsNothing);
    expect(find.text('Blood oxygen'), findsNothing);
    expect(find.text('Wrist temp'), findsNothing);
  });

  testWidgets('extras present show breathing, oxygen and temp deviation', (
    tester,
  ) async {
    final reader = FakeHealthReader()
      ..series[HealthSeriesType.respiratoryRate] = [
        _sample(DateTime(2026, 11, 24, 2), 14.0),
        _sample(DateTime(2026, 11, 24, 4), 14.4),
      ]
      ..series[HealthSeriesType.bloodOxygen] = [
        _sample(DateTime(2026, 11, 24, 3), 96),
      ]
      ..series[HealthSeriesType.sleepingWristTemperature] = [
        for (var i = -8; i < 0; i++)
          _sample(_day(i).add(const Duration(hours: 3)), 36.0),
        _sample(DateTime(2026, 11, 24, 3), 36.2),
      ];
    await _pump(tester, _overview(_history(14)), reader);

    expect(find.text('Breathing'), findsOneWidget);
    expect(find.text('14.2 /min'), findsOneWidget);
    expect(find.text('96%'), findsOneWidget);
    expect(find.text('+0.2 °C'), findsOneWidget);
  });

  testWidgets('nights without stages draw single-segment bars', (tester) async {
    final segments = [
      for (var i = -13; i < -6; i++) ..._staged(_day(i)),
      ..._unstaged(_day(-6)),
      ..._staged(_day(-5)),
      // No night on day -4.
      ..._unstaged(_day(-3)),
      ..._staged(_day(-2)),
      ..._staged(_day(-1)),
      ..._lastNight(),
    ];
    await _pump(tester, _overview(segments), FakeHealthReader());
    await _selectRange(tester, '7 days');

    final bars = tester.widget<NsBarChart>(find.byType(NsBarChart)).bars;
    expect(bars.map((b) => b.segments.length), [1, 3, 0, 1, 3, 3, 3]);
    expect(bars.last.highlight, isTrue);
  });

  testWidgets('sleep HR is read once for the whole range', (tester) async {
    final reader = FakeHealthReader();
    final overview = _overview(_history(14));
    await _pump(tester, overview, reader);
    reader.seriesCalls.clear();

    await _selectRange(tester, '7 days');

    final hr = reader.seriesCalls.where(
      (c) => c.$1 == HealthSeriesType.heartRate,
    );
    final nights = (overview.sleep as SectionData<SleepOverview>).value.nights;
    final week = nights.where((n) => !n.date.isBefore(_day(-6))).toList();
    expect(hr.single, (
      HealthSeriesType.heartRate,
      week.first.start,
      week.last.end,
    ));
  });

  testWidgets('30 days shows the comparison when the previous period is '
      'readable', (tester) async {
    final reader = FakeHealthReader()..sleep = _history(60);
    await _pump(tester, _overview(_history(60)), reader);
    await _selectRange(tester, '30 days');

    expect(find.byType(NsTrendLabel), findsOneWidget);
  });

  testWidgets('30 days on Android without history hides the comparison', (
    tester,
  ) async {
    final reader = FakeHealthReader(platform: HealthPlatformKind.healthConnect)
      ..sleep = _history(60);
    await _pump(
      tester,
      _overview(
        _history(60),
        platform: HealthPlatformKind.healthConnect,
        readableFrom: DateTime(2026, 10, 5),
      ),
      reader,
    );
    await _selectRange(tester, '30 days');

    expect(find.byType(NsBarChart), findsOneWidget);
    expect(find.byType(NsTrendLabel), findsNothing);
  });

  testWidgets('range view shows averages and usual bedtime', (tester) async {
    await _pump(tester, _overview(_history(14)), FakeHealthReader());
    await _selectRange(tester, '7 days');

    expect(find.text('Averages'), findsOneWidget);
    expect(find.text('Sleep score'), findsOneWidget);
    expect(find.text('Usual bedtime'), findsOneWidget);
    expect(find.text('11:00 PM ± 0 min'), findsOneWidget);
  });

  testWidgets('no overflow at text scale 2.0 in dark mode', (tester) async {
    await _pump(
      tester,
      _overview(_history(60)),
      FakeHealthReader()..sleep = _history(60),
      textScale: 2,
      brightness: Brightness.dark,
    );
    expect(tester.takeException(), isNull);
    for (final label in ['7 days', '30 days']) {
      await tester.ensureVisible(find.text(label));
      await _selectRange(tester, label);
      expect(tester.takeException(), isNull);
    }
  });

  group('back button', () {
    GoRouter router(String initial) {
      final r = GoRouter(
        initialLocation: initial,
        routes: [
          GoRoute(path: '/health', builder: (_, _) => const Text('Health tab')),
          GoRoute(
            path: '/health/sleep',
            builder: (_, _) => const SleepDetailPage(),
          ),
        ],
      );
      addTearDown(r.dispose);
      return r;
    }

    testWidgets('pops back after a push from the Health tab', (tester) async {
      final r = router('/health');
      await _pump(
        tester,
        _overview(_history(14)),
        FakeHealthReader(),
        router: r,
      );
      r.push('/health/sleep');
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Health tab'), findsOneWidget);
    });

    testWidgets('goes to the Health tab when opened directly', (tester) async {
      final r = router('/health/sleep');
      await _pump(
        tester,
        _overview(_history(14)),
        FakeHealthReader(),
        router: r,
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Health tab'), findsOneWidget);
    });
  });

  test("extras are dropped when the account changes", () async {
    final reader = FakeHealthReader()
      ..series[HealthSeriesType.respiratoryRate] = [
        _sample(DateTime(2026, 11, 24, 2), 14.0),
      ];
    final c = ProviderContainer(
      overrides: [
        fakeHealthOverview(
          FakeHealthOverviewController(_overview(_history(14))),
        ),
        healthReaderProvider.overrideWithValue(reader),
        healthOwnerIdProvider.overrideWith((ref) => ref.watch(_ownerProvider)),
        healthClockProvider.overrideWithValue(() => _now),
      ],
    );
    addTearDown(c.dispose);
    c.listen(sleepNightExtrasProvider, (_, _) {});
    expect(
      (await c.read(sleepNightExtrasProvider.future))!.respiratoryRate,
      14,
    );

    c.read(_ownerProvider.notifier).set('other-owner');
    expect(c.read(sleepNightExtrasProvider).isLoading, isTrue);
    expect(await c.read(sleepNightExtrasProvider.future), isNull);
  });
}
