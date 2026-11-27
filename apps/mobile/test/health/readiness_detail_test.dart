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
import 'package:beyondrep/features/health/domain/energy.dart';
import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/health/domain/sleep_nights.dart';
import 'package:beyondrep/features/health/domain/outside_workouts.dart';
import 'package:beyondrep/features/health/domain/sleep_score.dart';
import 'package:beyondrep/features/health/domain/training_load.dart';
import 'package:beyondrep/features/progress/data/objectbox_workout_history_repository.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:beyondrep/features/health/widgets/detail_layout.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart' hide Baseline;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_overview.dart';
import '../support/fake_health_reader.dart';
import '../support/health_overview_fixtures.dart';

const _owner = 'synthetic-owner';

class _History implements WorkoutHistoryRepository {
  _History(this.sessions);
  final List<WorkoutSessionRecord> sessions;

  @override
  WorkoutHistorySnapshot readCompleted() =>
      WorkoutHistorySnapshot(sessions: sessions);

  @override
  Future<WorkoutHistorySnapshot> readCompletedAsync() async => readCompleted();
}

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
HealthOverview _overview(
  List<SleepSegment> segments,
  FakeHealthReader reader, {
  List<WorkoutSessionRecord> logged = const [],
  List<OutsideWorkout> outside = const [],
}) {
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
  final readiness = SectionData(
    ReadinessOverview(
      result: scoreReadiness(
        today: today,
        lastNight: last,
        sleepScore: score,
        priorNights: nights.sublist(0, nights.length - 1),
        hrvDaily: hrvDaily,
        restingHrDaily: rhrDaily,
        loadSessions: loadSessions(logged, mergeWorkouts(logged, outside)),
      ),
      loadSessions: loadSessions(logged, mergeWorkouts(logged, outside)),
      hasHrv: true,
      hasRestingHr: true,
      hasSleep: true,
      hrvVsNormal: null,
      restingHrVsNormal: null,
      hrvBaseline: baselineOf(hrvDaily, today, sdFloor: hrvSdFloor),
      restingHrBaseline: baselineOf(rhrDaily, today, sdFloor: rhrSdFloor),
      hrvIsSdnn: reader.platform == HealthPlatformKind.appleHealth,
    ),
  );
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
    workouts: SectionData(WorkoutsOverview(outside: outside)),
    readiness: readiness,
    energy: energySection(
      readiness,
      wake: DateTime(2026, 11, 24, 6, 31),
      day: today,
    ),
  );
}

/// A ready overview with fixed parts and baselines for the Today rows.
HealthOverview _todayOverview({
  HealthPlatformKind platform = HealthPlatformKind.appleHealth,
  bool restingHr = true,
  double? loadRatio,
  DateTime? readAt,
  Energy? energy,
  EnergyLearning learning = const EnergyLearning(),
}) {
  // sleepOverview's vsWeek is 36 min under the 7-night average: 6h 48m.
  final at = readAt ?? overviewReadAt;
  final readiness = _todayReadiness(
    platform: platform,
    restingHr: restingHr,
    loadRatio: loadRatio,
  );
  return HealthOverview(
    ownerId: _owner,
    readAt: at,
    platform: platform,
    readableFrom: null,
    needsMoreAccess: false,
    sleep: SectionData(sleepOverview(night())),
    heart: SectionData(fullHeart),
    activity: SectionData(fullActivity),
    body: SectionData(fullBody),
    readiness: readiness,
    energy: energySection(
      readiness,
      energy: energy,
      learning: learning,
      wake: DateTime(at.year, at.month, at.day, 6, 31),
      day: DateTime(at.year, at.month, at.day),
    ),
  );
}

SectionData<ReadinessOverview> _todayReadiness({
  required HealthPlatformKind platform,
  required bool restingHr,
  required double? loadRatio,
}) {
  return SectionData(
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
            if (loadRatio != null)
              const ReadinessPart(
                input: ReadinessInput.trainingLoad,
                score: 80,
                weight: 0.15,
              ),
          ],
          loadRatio: loadRatio,
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

Energy _energy62() => Energy(
  value: 62,
  band: ReadinessBand.fair,
  start: 78,
  items: [
    EnergyItem(
      kind: EnergyItemKind.workout,
      points: -9,
      at: DateTime(2026, 11, 24, 7, 10),
    ),
    const EnergyItem(kind: EnergyItemKind.activeDay, points: -8),
    const EnergyItem(kind: EnergyItemKind.awake, points: -1, awakeHours: 10),
    EnergyItem(
      kind: EnergyItemKind.nap,
      points: 3,
      at: DateTime(2026, 11, 24, 14, 40),
    ),
  ],
);

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
      expect(find.text('Why you started at 78'), findsOneWidget);
      expect(find.text('How energy works'), findsOneWidget);
      expect(find.text('How readiness works'), findsNothing);
      expect(find.textContaining('not medical advice'), findsOneWidget);
      expect(
        find.textContaining('A measure counts once it has 3 days'),
        findsOneWidget,
      );
    });

    testWidgets('Today shows energy, the change line and every item', (
      tester,
    ) async {
      await _pump(
        tester,
        _todayOverview(energy: _energy62()),
        FakeHealthReader(),
      );

      expect(find.text('Energy'), findsWidgets);
      expect(find.text('62'), findsOneWidget);
      expect(
        find.text('Started today at 78 · down 16 since morning'),
        findsOneWidget,
      );
      expect(find.text('Since you woke'), findsOneWidget);
      expect(find.text('Woke at 6:31 AM'), findsOneWidget);
      for (final (label, points) in [
        ('Workout at 7:10 AM', '−9'),
        ('Active day so far', '−8'),
        ('Awake 10 hours', '−1'),
        ('Nap at 2:40 PM', '+3'),
      ]) {
        expect(
          find.descendant(
            of: find.widgetWithText(DetailRow, label),
            matching: find.text(points),
          ),
          findsOneWidget,
          reason: label,
        );
      }
      expect(find.text('Why you started at 78'), findsOneWidget);
      expect(find.textContaining('Naps add back'), findsNothing);
      expect(find.textContaining('Still learning'), findsNothing);
    });

    testWidgets('a capped nap explains the cap', (tester) async {
      await _pump(
        tester,
        _todayOverview(
          energy: Energy(
            value: 70,
            band: ReadinessBand.good,
            start: 78,
            items: [
              EnergyItem(
                kind: EnergyItemKind.workout,
                points: -8,
                at: DateTime(2026, 11, 24, 7, 10),
              ),
              EnergyItem(
                kind: EnergyItemKind.nap,
                points: 0 + 8,
                at: DateTime(2026, 11, 24, 14, 40),
                capped: true,
              ),
            ],
          ),
        ),
        FakeHealthReader(),
      );

      expect(find.text('Nap at 2:40 PM (capped)'), findsOneWidget);
      expect(
        find.text(
          'Naps add back up to 10 points, and never more than the day has '
          'used.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('no items says nothing has changed', (tester) async {
      await _pump(tester, _todayOverview(), FakeHealthReader());

      expect(find.text('Since you woke'), findsOneWidget);
      expect(
        find.text('Nothing has changed your energy since you woke.'),
        findsOneWidget,
      );
      expect(find.byType(DetailRow), findsWidgets);
      expect(
        find.text('Started today at 78 · no change since morning'),
        findsOneWidget,
      );
    });

    testWidgets('a waived awake dip is explained, otherwise nothing is', (
      tester,
    ) async {
      const waived =
          'You usually train around now, so time awake costs '
          'nothing today.';
      await _pump(
        tester,
        _todayOverview(
          energy: const Energy(
            value: 70,
            band: ReadinessBand.fair,
            start: 78,
            items: [],
            awakeWaived: true,
          ),
        ),
        FakeHealthReader(),
      );
      expect(find.text(waived), findsOneWidget);
    });

    testWidgets('no waived caption without a waived dip', (tester) async {
      await _pump(tester, _todayOverview(), FakeHealthReader());
      expect(find.textContaining('You usually train around now'), findsNothing);
    });

    testWidgets('a tuned energy says so under the change line', (tester) async {
      const tuned = 'Tuned to your last 90 days.';
      await _pump(
        tester,
        _todayOverview(
          energy: const Energy(
            value: 70,
            band: ReadinessBand.fair,
            start: 78,
            items: [],
            tuned: true,
          ),
        ),
        FakeHealthReader(),
      );
      expect(find.text(tuned), findsOneWidget);
    });

    testWidgets('an untuned energy has no tuned caption', (tester) async {
      await _pump(tester, _todayOverview(), FakeHealthReader());
      expect(find.text('Tuned to your last 90 days.'), findsNothing);
    });

    testWidgets('How energy works explains the tuning', (tester) async {
      await _pump(tester, _todayOverview(), FakeHealthReader());
      expect(
        find.textContaining(
          'tunes how much workouts and active calories lower your energy',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('never saved.'), findsOneWidget);
    });

    testWidgets('learning note shows days and workouts', (tester) async {
      await _pump(
        tester,
        _todayOverview(
          learning: const EnergyLearning(workoutsNeeded: 12, daysNeeded: 9),
        ),
        FakeHealthReader(),
      );

      expect(
        find.text(
          'Still learning your patterns: 12 more workouts and 9 more days '
          'of data for a calibrated score.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('lists Training load with its About button when the part '
        'exists', (tester) async {
      await _pump(tester, _todayOverview(loadRatio: 1.1), FakeHealthReader());
      expect(find.text('Training load'), findsOneWidget);
      expect(
        find.text('Last 7 days at 110% of your usual · 15% of the score'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('About Training load'), findsOneWidget);
    });

    testWidgets('has no Training load row without the part', (tester) async {
      await _pump(tester, _todayOverview(), FakeHealthReader());
      expect(find.text('Training load'), findsNothing);
      expect(find.bySemanticsLabel('About Training load'), findsNothing);
    });

    testWidgets('About buttons on the how-it-works panel and each input', (
      tester,
    ) async {
      await _pump(tester, _todayOverview(), FakeHealthReader());
      expect(find.bySemanticsLabel('About Energy'), findsOneWidget);
      expect(
        find.bySemanticsLabel('About Heart rate variability (HRV)'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('About Resting heart rate'), findsOneWidget);
      // The sleep row and the sleep-vs-week row both explain time asleep.
      expect(find.bySemanticsLabel('About Time asleep'), findsNWidgets(2));
      await tester.tap(
        find.bySemanticsLabel('About Heart rate variability (HRV)'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text("We'll show your usual range after 14 days of data."),
        findsOneWidget,
      );
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

    testWidgets('a baseline short of 3 days says so', (tester) async {
      final o = _todayOverview();
      final r = (o.readiness as SectionData<ReadinessOverview>).value;
      final short = SectionData(
        ReadinessOverview(
          result: ReadinessReady(
            Readiness(
              value: 78,
              band: ReadinessBand.good,
              parts: const [
                ReadinessPart(
                  input: ReadinessInput.sleep,
                  score: 74,
                  weight: 1,
                ),
              ],
            ),
          ),
          hasHrv: true,
          hasRestingHr: true,
          hasSleep: true,
          hrvVsNormal: null,
          restingHrVsNormal: null,
          hrvBaseline: null,
          restingHrBaseline: null,
          hrvIsSdnn: r.hrvIsSdnn,
        ),
      );
      final ov = overview(
        sleep: o.sleep,
        readiness: short,
        energy: energySection(
          short,
          wake: DateTime(2026, 11, 24, 6, 31),
          day: DateTime(2026, 11, 24),
        ),
        readAt: o.readAt,
      );
      await _pump(tester, ov, FakeHealthReader());
      expect(
        find.text('Your normal needs 3 days of HRV in the last 30.'),
        findsOneWidget,
      );
      expect(
        find.text('Your normal needs 3 days of resting HR in the last 30.'),
        findsOneWidget,
      );
    });

    testWidgets('not ready reuses the card copy', (tester) async {
      final o = _todayOverview();
      const notReadyReadiness = SectionData(
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
      );
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
        readiness: notReadyReadiness,
        energy: energySection(notReadyReadiness),
      );
      await _pump(tester, notReady, FakeHealthReader());

      expect(find.text('Not enough data for a score'), findsOneWidget);
      expect(find.text('How energy works'), findsOneWidget);
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

    testWidgets("yesterday's overview never shows yesterday's energy", (
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
      expect(find.text('Since you woke'), findsNothing);
      expect(find.text('How energy works'), findsNothing);
      expect(find.text("Couldn't read · Try again"), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^No Energy data\.')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('No Readiness data')), findsNothing);
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
      expect(find.text('Since you woke'), findsNothing);
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
      // Heart data from day -5: day -2 is the first with 3 earlier days.
      final reader = FakeHealthReader()..sleep = _nights(-40);
      _heartFrom(reader, -5);
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

    testWidgets('the range panel is Starting energy and says when empty', (
      tester,
    ) async {
      final reader = FakeHealthReader()..sleep = _nights(-40);
      await _pump(tester, _overview(_nights(-40), reader), reader);
      await _selectRange(tester, '7 days');
      expect(find.text('Starting energy'), findsOneWidget);
      expect(find.text('No starting energy in these 7 days.'), findsOneWidget);
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
      // From day -13: the previous week scores only days -10 to -7.
      final reader = FakeHealthReader()..sleep = _nights(-40);
      _heartFrom(reader, -13);
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

    test("today's trend point equals the hero after the history changes "
        'without an overview refresh', () async {
      DateTime at(int back) => DateTime(2026, 11, 24 - back, 9);
      WorkoutSessionRecord logged(String id, int back) => WorkoutSessionRecord(
        uuid: id,
        name: 'Logged',
        status: WorkoutStatus.completed,
        startedAtUtc: at(back).toUtc(),
        completedAtUtc: at(back).add(const Duration(hours: 1)).toUtc(),
        originalOffsetMinutes: 0,
        revision: 1,
      );
      final sessions = [logged('a', 45), logged('b', 20), logged('c', 3)];
      final outside = [
        OutsideWorkout(
          id: 'o',
          kind: OutsideWorkoutKind.running,
          start: at(9).toUtc(),
          end: at(9).add(const Duration(minutes: 40)).toUtc(),
          source: 'Synthetic app',
        ),
      ];
      final reader = FakeHealthReader()
        ..applyWindows = true
        ..sleep = _nights(-100);
      _heartFrom(reader, -100);
      final overview = _overview(
        _nights(-100),
        reader,
        logged: sessions,
        outside: outside,
      );
      final c = ProviderContainer(
        overrides: [
          fakeHealthOverview(FakeHealthOverviewController(overview)),
          healthReaderProvider.overrideWithValue(reader),
          // The history changed since the overview was read.
          workoutHistoryRepositoryProvider.overrideWithValue(
            _History(const []),
          ),
          healthOwnerIdProvider.overrideWithValue(_owner),
          healthClockProvider.overrideWithValue(() => _now),
        ],
      );
      addTearDown(c.dispose);
      final provider = readinessHistoryProvider(SleepRange.week);
      c.listen(provider, (_, _) {});
      final history = (await c.read(provider.future))!;

      final fromOverview =
          ((overview.readiness as SectionData<ReadinessOverview>).value.result
                  as ReadinessReady)
              .readiness;
      expect(
        fromOverview.parts.map((p) => p.input),
        contains(ReadinessInput.trainingLoad),
      );
      final todayPoint = (history.last.result as ReadinessReady).readiness;
      expect(history.last.day, _day(0));
      expect(todayPoint.value, fromOverview.value);
      expect(todayPoint.loadRatio, fromOverview.loadRatio);
    });

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
