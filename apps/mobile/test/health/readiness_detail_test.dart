import 'dart:io';

import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/charts/bar_series.dart';
import 'package:beyondrep/core/design/charts/trend_label.dart';
import 'package:beyondrep/features/health/application/health_details.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_connection_repository.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/detail/readiness_detail_page.dart';
import 'package:beyondrep/features/health/domain/daily_series.dart';
import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/health/domain/sleep_nights.dart';
import 'package:beyondrep/features/health/domain/sleep_score.dart';
import 'package:beyondrep/features/health/widgets/detail_layout.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart' hide Baseline;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

SleepSegment _seg(DateTime from, DateTime to, SleepStage stage) => (
  from: from,
  to: to,
  stage: stage,
  source: 'Synthetic watch',
  sourceKey: 'watch',
);

/// Staged night 23:00 -> 06:30 ending on [date].
List<SleepSegment> _staged(DateTime date) {
  DateTime at(int h, [int m = 0]) =>
      DateTime(date.year, date.month, date.day, h, m);
  return [
    _seg(at(-1), at(0, 30), SleepStage.light),
    _seg(at(0, 30), at(1, 30), SleepStage.deep),
    _seg(at(1, 30), at(3), SleepStage.light),
    _seg(at(3), at(4), SleepStage.rem),
    _seg(at(4), at(6), SleepStage.light),
    _seg(at(6), at(6, 30), SleepStage.rem),
  ];
}

/// Staged nights ending on each day from [first] (an offset) to today.
List<SleepSegment> _nights(int first) => [
  for (var i = first; i <= 0; i++) ..._staged(_day(i)),
];

HealthSample _sample(DateTime at, double value) =>
    (from: at, to: at, value: value, source: 'Synthetic watch');

/// HRV at 3 AM (overnight) and resting HR at 7 AM on each day from [first]
/// to yesterday, plus today's 50 ms and 54 bpm.
void _heartFrom(FakeHealthReader reader, int first) {
  reader.series[HealthSeriesType.hrv] = [
    for (var i = first; i < 0; i++)
      _sample(_day(i).add(const Duration(hours: 3)), i.isEven ? 42 : 38),
    _sample(DateTime(2026, 11, 24, 3), 50),
  ];
  reader.series[HealthSeriesType.restingHeartRate] = [
    for (var i = first; i < 0; i++)
      _sample(_day(i).add(const Duration(hours: 7)), i.isEven ? 59 : 57),
    _sample(DateTime(2026, 11, 24, 7), 54),
  ];
}

/// The overview the page would get from [segments]; its heart lists and
/// readiness come from [reader]'s samples as the overview builds them.
HealthOverview _overview(List<SleepSegment> segments, FakeHealthReader reader) {
  final nights = [
    for (final n in buildNights(segments))
      if (!n.date.isBefore(_day(-30))) n,
  ];
  final last = nights.last;
  final score = scoreSleep(
    last,
    priorNights: nights.sublist(0, nights.length - 1),
  );
  final hrvDaily = hrvDailyOf(
    reader.series[HealthSeriesType.hrv] ?? const [],
    nights,
  );
  final rhrDaily = reduceDaily(
    reader.series[HealthSeriesType.restingHeartRate] ?? const [],
    DailyReduction.latest,
  );
  final today = _day(0);
  return HealthOverview(
    ownerId: _owner,
    readAt: _now,
    platform: reader.platform,
    readableFrom: null,
    needsMoreAccess: false,
    sleep: SectionData(
      SleepOverview(
        lastNight: last,
        score: score,
        sleepAvgHr: null,
        nights: nights,
        vsWeek: null,
      ),
    ),
    heart: SectionData(fullHeart),
    activity: SectionData(fullActivity),
    body: SectionData(fullBody),
    readiness: SectionData(
      ReadinessOverview(
        result: scoreReadiness(
          today: today,
          lastNight: last,
          sleepScore: score,
          priorNights: nights.sublist(0, nights.length - 1),
          hrvDaily: hrvDaily,
          restingHrDaily: rhrDaily,
        ),
        hasHrv: true,
        hasRestingHr: true,
        hasSleep: true,
        hrvVsNormal: null,
        restingHrVsNormal: null,
        hrvBaseline: baselineOf(hrvDaily, today, sdFloor: hrvSdFloor),
        restingHrBaseline: baselineOf(rhrDaily, today, sdFloor: rhrSdFloor),
        hrvIsSdnn: reader.platform == HealthPlatformKind.appleHealth,
      ),
    ),
  );
}

/// A ready overview with fixed parts and baselines for the Today rows.
HealthOverview _todayOverview({
  HealthPlatformKind platform = HealthPlatformKind.appleHealth,
  bool restingHr = true,
  DateTime? readAt,
}) {
  // sleepOverview's vsWeek is 36 min under the 7-night average: 6h 48m.
  return HealthOverview(
    ownerId: _owner,
    readAt: readAt ?? overviewReadAt,
    platform: platform,
    readableFrom: null,
    needsMoreAccess: false,
    sleep: SectionData(sleepOverview(night())),
    heart: SectionData(fullHeart),
    activity: SectionData(fullActivity),
    body: SectionData(fullBody),
    readiness: SectionData(
      ReadinessOverview(
        result: ReadinessReady(
          Readiness(
            value: 78,
            band: ReadinessBand.good,
            parts: [
              const ReadinessPart(
                input: ReadinessInput.hrv,
                score: 85,
                weight: 0.4,
                z: 1,
              ),
              if (restingHr)
                const ReadinessPart(
                  input: ReadinessInput.restingHr,
                  score: 77.4,
                  weight: 0.25,
                  z: -0.5,
                ),
              const ReadinessPart(
                input: ReadinessInput.sleep,
                score: 74,
                weight: 0.25,
              ),
              const ReadinessPart(
                input: ReadinessInput.sleepDebt,
                score: 60,
                weight: 0.1,
              ),
            ],
          ),
        ),
        hasHrv: true,
        hasRestingHr: restingHr,
        hasSleep: true,
        hrvVsNormal: null,
        restingHrVsNormal: null,
        hrvBaseline: const Baseline(mean: 46, sd: 3, days: 20),
        restingHrBaseline: restingHr
            ? const Baseline(mean: 57.6, sd: 1.5, days: 20)
            : null,
        hrvIsSdnn: platform == HealthPlatformKind.appleHealth,
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  HealthOverview overview,
  FakeHealthReader reader, {
  double textScale = 1,
  Brightness brightness = Brightness.light,
  FakeHealthOverviewController? controller,
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fakeHealthOverview(
          controller ?? FakeHealthOverviewController(overview),
        ),
        healthReaderProvider.overrideWithValue(reader),
        healthOwnerIdProvider.overrideWithValue(_owner),
        healthClockProvider.overrideWithValue(() => _now),
        localNowProvider.overrideWithValue(_now),
      ],
      child: MaterialApp(
        theme: BeyondRepTheme.build(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const ReadinessDetailPage(),
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
  group('Today', () {
    testWidgets('one row per part with its normal range and share', (
      tester,
    ) async {
      await _pump(tester, _todayOverview(), FakeHealthReader());

      expect(find.text('Good to train'), findsOneWidget);
      expect(find.text('HRV (SDNN)'), findsOneWidget);
      expect(
        find.text('52 ms today · your normal 43–49 ms · 40% of the score'),
        findsOneWidget,
      );
      expect(find.text('Resting HR'), findsOneWidget);
      expect(
        find.text('54 bpm today · your normal 56–59 bpm · 25% of the score'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.widgetWithText(DetailRow, 'Resting HR'),
          matching: find.text('77'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('6h 12m asleep · sleep score 74 · 25% of the score'),
        findsOneWidget,
      );
      expect(
        find.text('6h 12m vs 6h 48m 7-night average · 10% of the score'),
        findsOneWidget,
      );
      expect(find.text('How readiness works'), findsOneWidget);
      expect(find.textContaining('not medical advice'), findsOneWidget);
      expect(find.textContaining('14 days'), findsOneWidget);
    });

    testWidgets('Android names RMSSD', (tester) async {
      await _pump(
        tester,
        _todayOverview(platform: HealthPlatformKind.healthConnect),
        FakeHealthReader(platform: HealthPlatformKind.healthConnect),
      );

      expect(find.text('HRV (RMSSD)'), findsOneWidget);
      expect(find.text('HRV (SDNN)'), findsNothing);
      expect(find.textContaining('RMSSD'), findsWidgets);
    });

    testWidgets('a part that dropped out says why', (tester) async {
      await _pump(tester, _todayOverview(restingHr: false), FakeHealthReader());

      expect(
        find.descendant(
          of: find.widgetWithText(DetailRow, 'Resting HR'),
          matching: find.text('Not counted'),
        ),
        findsOneWidget,
      );
      expect(find.text('No resting HR today yet.'), findsOneWidget);
    });

    testWidgets('not ready reuses the card copy', (tester) async {
      final o = _todayOverview();
      final notReady = HealthOverview(
        ownerId: o.ownerId,
        readAt: o.readAt,
        platform: o.platform,
        readableFrom: null,
        needsMoreAccess: false,
        sleep: o.sleep,
        heart: o.heart,
        activity: o.activity,
        body: o.body,
        readiness: const SectionData(
          ReadinessOverview(
            result: ReadinessNotReady(noHrvOrRhrToday: true),
            hasHrv: false,
            hasRestingHr: false,
            hasSleep: true,
            hrvVsNormal: null,
            restingHrVsNormal: null,
            hrvBaseline: null,
            restingHrBaseline: null,
            hrvIsSdnn: true,
          ),
        ),
      );
      await _pump(tester, notReady, FakeHealthReader());

      expect(find.text('Not enough data for a score'), findsOneWidget);
      expect(find.text('How readiness works'), findsOneWidget);
    });

    testWidgets('explains that older days are scored without sleep HR', (
      tester,
    ) async {
      await _pump(tester, _todayOverview(), FakeHealthReader());

      expect(
        find.textContaining('days before the period without sleep heart rate'),
        findsOneWidget,
      );
    });

    testWidgets("yesterday's overview never shows yesterday's score", (
      tester,
    ) async {
      final controller = FakeHealthOverviewController(
        _todayOverview(readAt: DateTime(2026, 11, 23, 7, 42)),
      );
      await _pump(
        tester,
        _todayOverview(),
        FakeHealthReader(),
        controller: controller,
      );

      expect(find.text('Good to train'), findsNothing);
      expect(find.text('78'), findsNothing);
      expect(find.text('How readiness works'), findsNothing);
      expect(find.text("Couldn't read · Try again"), findsOneWidget);
      await tester.tap(find.text("Couldn't read · Try again"));
      await tester.pumpAndSettle();
      expect(controller.refreshCalls, 1);
    });

    testWidgets('a re-read in flight shows loading, not the old score', (
      tester,
    ) async {
      final controller = FakeHealthOverviewController(
        _todayOverview(readAt: DateTime(2026, 11, 23, 7, 42)),
      );
      await _pump(
        tester,
        _todayOverview(),
        FakeHealthReader(),
        controller: controller,
      );
      controller.setLoading();
      await tester.pump();

      expect(find.byType(DetailLoading), findsOneWidget);
      expect(find.text('Good to train'), findsNothing);
      expect(find.text("Couldn't read · Try again"), findsNothing);
    });
  });

  group('7 and 30 days', () {
    testWidgets('7 days reads HRV and resting HR once, nothing else extra', (
      tester,
    ) async {
      final reader = FakeHealthReader()..sleep = _nights(-40);
      _heartFrom(reader, -40);
      await _pump(tester, _overview(_nights(-40), reader), reader);
      reader
        ..seriesCalls.clear()
        ..sleepCalls.clear();

      await _selectRange(tester, '7 days');

      final byType = <HealthSeriesType, int>{};
      for (final c in reader.seriesCalls) {
        byType.update(c.$1, (n) => n + 1, ifAbsent: () => 1);
      }
      expect(byType, {
        HealthSeriesType.hrv: 1,
        HealthSeriesType.restingHeartRate: 1,
        // The sleep tab's night-window reads, one per night of the week.
        HealthSeriesType.heartRate: 7,
      });
      final hrv = reader.seriesCalls.firstWhere(
        (c) => c.$1 == HealthSeriesType.hrv,
      );
      expect(hrv.$2, _day(-44));
      expect(hrv.$3, _now);
      expect(reader.sleepCalls, isEmpty);

      // Switching away and back does not read again.
      final calls = reader.seriesCalls.length;
      await _selectRange(tester, 'Today');
      await _selectRange(tester, '7 days');
      expect(reader.seriesCalls.length, calls);
    });

    testWidgets('days without a baseline draw no bar and skip the average', (
      tester,
    ) async {
      // Heart data from day -16: day -2 is the first with 14 earlier days.
      final reader = FakeHealthReader()..sleep = _nights(-40);
      _heartFrom(reader, -16);
      await _pump(tester, _overview(_nights(-40), reader), reader);
      await _selectRange(tester, '7 days');

      final bars = tester.widget<NsBarChart>(find.byType(NsBarChart)).bars;
      expect(bars, hasLength(7));
      expect(bars.map((b) => b.segments.isEmpty), [
        true,
        true,
        true,
        true,
        false,
        false,
        false,
      ]);
      final scored = bars.where((b) => b.segments.isNotEmpty);
      final avg = scored.fold(0.0, (a, b) => a + b.total) / scored.length;
      expect(find.text('${avg.round()}'), findsOneWidget);
      expect(find.text('Scored on 3 of 7 days'), findsOneWidget);
      expect(find.byType(NsTrendLabel), findsNothing);
    });

    testWidgets('the previous period shows with 5 scored days', (tester) async {
      final reader = FakeHealthReader()..sleep = _nights(-40);
      _heartFrom(reader, -40);
      await _pump(tester, _overview(_nights(-40), reader), reader);
      await _selectRange(tester, '7 days');

      expect(find.text('Scored on 7 of 7 days'), findsOneWidget);
      expect(find.byType(NsTrendLabel), findsOneWidget);
      expect(find.textContaining('previous 7 days'), findsOneWidget);
    });

    testWidgets('the previous period hides with under 5 scored days', (
      tester,
    ) async {
      // From day -24: the previous week scores only days -10 to -7.
      final reader = FakeHealthReader()..sleep = _nights(-40);
      _heartFrom(reader, -24);
      await _pump(tester, _overview(_nights(-40), reader), reader);
      await _selectRange(tester, '7 days');

      expect(find.text('Scored on 7 of 7 days'), findsOneWidget);
      expect(find.byType(NsTrendLabel), findsNothing);
    });

    testWidgets('30 days has a bar slot per day and the 70 line', (
      tester,
    ) async {
      final reader = FakeHealthReader()..sleep = _nights(-70);
      _heartFrom(reader, -70);
      await _pump(tester, _overview(_nights(-70), reader), reader);
      await _selectRange(tester, '30 days');

      final chart = tester.widget<NsBarChart>(find.byType(NsBarChart));
      expect(chart.bars, hasLength(30));
      expect(chart.referenceValue, 70);
      expect(chart.referenceLabel, 'Good to train');
      expect(find.text('Scored on 30 of 30 days'), findsOneWidget);
    });

    test(
      '30 days scores every previous-period day on full baselines',
      () async {
        final reader = FakeHealthReader()
          ..applyWindows = true
          ..sleep = _nights(-100);
        _heartFrom(reader, -100);
        final overview = _overview(_nights(-100), reader);
        final c = ProviderContainer(
          overrides: [
            fakeHealthOverview(FakeHealthOverviewController(overview)),
            healthReaderProvider.overrideWithValue(reader),
            healthOwnerIdProvider.overrideWithValue(_owner),
            healthClockProvider.overrideWithValue(() => _now),
          ],
        );
        addTearDown(c.dispose);
        final provider = readinessHistoryProvider(SleepRange.month);
        c.listen(provider, (_, _) {});
        final history = (await c.read(provider.future))!;

        expect(history, hasLength(60));
        expect(history.every((d) => d.result is ReadinessReady), isTrue);

        // Independent expectation: every day scored against the full HRV and
        // resting HR history, with the nights the 30 day tab reads (day -59
        // on) and no sleep heart rate, as for the previous period.
        final nights = [
          for (final n in buildNights(_nights(-100)))
            if (!n.date.isBefore(_day(-59))) n,
        ];
        final hrvDaily = hrvDailyOf(
          reader.series[HealthSeriesType.hrv]!,
          buildNights(_nights(-100)),
        );
        final rhrDaily = reduceDaily(
          reader.series[HealthSeriesType.restingHeartRate]!,
          DailyReduction.latest,
        );
        final restingHr =
            (overview.heart as SectionData<HeartOverview>).value.restingHrDaily;
        int expected(int offset) {
          final night = nights.firstWhere((n) => n.date == _day(offset));
          final result = scoreReadiness(
            today: _day(offset),
            lastNight: night,
            sleepScore: scoreSleep(
              night,
              priorNights: [
                for (final n in nights)
                  if (n.date.isBefore(night.date)) n,
              ],
              restingHr: restingHr
                  .where((d) => !d.day.isAfter(night.date))
                  .lastOrNull
                  ?.value,
            ),
            priorNights: [
              for (final n in nights)
                if (n.date.isBefore(night.date)) n,
            ],
            hrvDaily: hrvDaily,
            restingHrDaily: rhrDaily,
          );
          return (result as ReadinessReady).readiness.value;
        }

        final previous = history
            .where((d) => d.day.isBefore(_day(-29)))
            .toList();
        expect(previous, hasLength(30));
        expect(previous.first.day, _day(-59));
        for (final d in previous) {
          final offset = d.day.difference(_day(0)).inDays;
          expect(
            (d.result as ReadinessReady).readiness.value,
            expected(offset),
            reason: 'day $offset',
          );
        }
      },
    );

    testWidgets('no overflow at text scale 2.0 in dark mode', (tester) async {
      final reader = FakeHealthReader()..sleep = _nights(-40);
      _heartFrom(reader, -40);
      await _pump(
        tester,
        _overview(_nights(-40), reader),
        reader,
        textScale: 2,
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      await _selectRange(tester, '7 days');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a failed history offers Try again', (tester) async {
    final reader = FakeHealthReader()..sleep = _nights(-40);
    _heartFrom(reader, -40);
    // The history's own reads are guarded; a failure comes from the sleep
    // range providers it awaits.
    var builds = 0;
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fakeHealthOverview(
            FakeHealthOverviewController(_overview(_nights(-40), reader)),
          ),
          healthReaderProvider.overrideWithValue(reader),
          healthOwnerIdProvider.overrideWithValue(_owner),
          healthClockProvider.overrideWithValue(() => _now),
          localNowProvider.overrideWithValue(_now),
          sleepRangeHrProvider.overrideWith((ref, range) {
            builds++;
            throw StateError('synthetic history bug');
          }),
        ],
        child: MaterialApp(
          theme: BeyondRepTheme.build(Brightness.light),
          home: const ReadinessDetailPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectRange(tester, '7 days');

    expect(find.text("Couldn't read · Try again"), findsOneWidget);
    expect(find.byType(DetailLoading), findsNothing);
    final before = builds;
    await tester.tap(find.text("Couldn't read · Try again"));
    await tester.pumpAndSettle();
    expect(builds, greaterThan(before));
  });

  test('history is dropped when the account changes', () async {
    final reader = FakeHealthReader()..sleep = _nights(-40);
    _heartFrom(reader, -40);
    final c = ProviderContainer(
      overrides: [
        fakeHealthOverview(
          FakeHealthOverviewController(_overview(_nights(-40), reader)),
        ),
        healthReaderProvider.overrideWithValue(reader),
        healthOwnerIdProvider.overrideWith((ref) => ref.watch(_ownerProvider)),
        healthClockProvider.overrideWithValue(() => _now),
      ],
    );
    addTearDown(c.dispose);
    final provider = readinessHistoryProvider(SleepRange.week);
    c.listen(provider, (_, _) {});
    expect(await c.read(provider.future), hasLength(14));

    c.read(_ownerProvider.notifier).set('other-owner');
    expect(c.read(provider).isLoading, isTrue);
    expect(await c.read(provider.future), isNull);
  });

  group('history today matches the overview', () {
    late Directory root;
    late Store store;

    setUp(() {
      root = Directory.systemTemp.createTempSync('beyondrep-readiness-');
      store = Store(getObjectBoxModel(), directory: '${root.path}/db');
    });
    tearDown(() {
      store.close();
      root.deleteSync(recursive: true);
    });

    test("day -30's whole night counts on a windowed reader", () async {
      final repo = ObjectBoxHealthConnectionRepository(store)
        ..connect(_owner, DateTime(2026, 9, 1));
      // HRV on 13 recent days plus one sample at 23:30 on day -31, inside
      // the night ending day -30: the 14th baseline day only if both read it.
      final reader = FakeHealthReader()
        ..applyWindows = true
        ..sleep = _nights(-70)
        ..series[HealthSeriesType.hrv] = [
          _sample(DateTime(2026, 10, 24, 23, 30), 40),
          for (var i = -13; i < 0; i++)
            _sample(_day(i).add(const Duration(hours: 3)), i.isEven ? 42 : 38),
          _sample(DateTime(2026, 11, 24, 3), 50),
        ];
      final c = ProviderContainer(
        overrides: [
          healthReaderProvider.overrideWithValue(reader),
          healthConnectionRepositoryProvider.overrideWithValue(repo),
          healthOwnerIdProvider.overrideWithValue(_owner),
          healthClockProvider.overrideWithValue(() => _now),
        ],
      );
      addTearDown(c.dispose);
      c.listen(healthOverviewProvider, (_, _) {});
      final overview = (await c.read(healthOverviewProvider.future))!;
      final r = (overview.readiness as SectionData<ReadinessOverview>).value;
      expect(r.hrvBaseline!.days, 14);
      final expected = r.result as ReadinessReady;

      final provider = readinessHistoryProvider(SleepRange.week);
      c.listen(provider, (_, _) {});
      final today = (await c.read(provider.future))!.last.result;
      expect(
        (today as ReadinessReady).readiness.value,
        expected.readiness.value,
      );
    });

    for (final range in [SleepRange.week, SleepRange.month]) {
      test('on the ${range.name} tab', () async {
        final repo = ObjectBoxHealthConnectionRepository(store)
          ..connect(_owner, DateTime(2026, 9, 1));
        final reader = FakeHealthReader()
          ..sleep = _nights(-70)
          ..series[HealthSeriesType.heartRate] = [
            _sample(DateTime(2026, 11, 24, 2), 50),
            _sample(DateTime(2026, 11, 24, 4), 54),
          ];
        _heartFrom(reader, -70);
        reader.applyWindows = true;
        final c = ProviderContainer(
          overrides: [
            healthReaderProvider.overrideWithValue(reader),
            healthConnectionRepositoryProvider.overrideWithValue(repo),
            healthOwnerIdProvider.overrideWithValue(_owner),
            healthClockProvider.overrideWithValue(() => _now),
          ],
        );
        addTearDown(c.dispose);
        c.listen(healthOverviewProvider, (_, _) {});
        final overview = (await c.read(healthOverviewProvider.future))!;
        final expected =
            (overview.readiness as SectionData<ReadinessOverview>).value.result
                as ReadinessReady;

        final provider = readinessHistoryProvider(range);
        c.listen(provider, (_, _) {});
        final history = (await c.read(provider.future))!;
        expect(history, hasLength(2 * range.nights));
        expect(history.last.day, _day(0));
        final today = history.last.result as ReadinessReady;
        expect(today.readiness.value, expected.readiness.value);
        expect(
          [for (final p in today.readiness.parts) (p.input, p.score, p.weight)],
          [
            for (final p in expected.readiness.parts)
              (p.input, p.score, p.weight),
          ],
        );
      });
    }
  });
}
