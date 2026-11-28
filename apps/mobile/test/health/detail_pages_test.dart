import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/charts/bar_series.dart';
import 'package:beyondrep/features/health/application/health_details.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/detail/activity_detail_page.dart';
import 'package:beyondrep/features/health/detail/body_detail_page.dart';
import 'package:beyondrep/features/health/detail/heart_detail_page.dart';
import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:beyondrep/features/health/domain/metric_explanations.dart';
import 'package:beyondrep/features/health/domain/outside_workouts.dart';
import 'package:beyondrep/features/progress/data/objectbox_workout_history_repository.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:beyondrep/features/health/domain/trend.dart';
import 'package:flutter/material.dart';
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

class _History implements WorkoutHistoryRepository {
  _History(this.sessions);
  final List<WorkoutSessionRecord> sessions;

  @override
  WorkoutHistorySnapshot readCompleted() =>
      WorkoutHistorySnapshot(sessions: sessions);

  @override
  Future<WorkoutHistorySnapshot> readCompletedAsync() async => readCompleted();
}

WorkoutSessionRecord _logged(
  String id,
  DateTime start,
  int minutes, {
  String name = 'Push day',
}) => WorkoutSessionRecord(
  uuid: id,
  name: name,
  status: WorkoutStatus.completed,
  startedAtUtc: start.toUtc(),
  completedAtUtc: start.add(Duration(minutes: minutes)).toUtc(),
  originalOffsetMinutes: 0,
  revision: 1,
);

OutsideWorkout _outsideWorkout(
  String id,
  DateTime start,
  int minutes, {
  OutsideWorkoutKind kind = OutsideWorkoutKind.running,
  double? kcal,
  String source = 'Synthetic app',
}) => OutsideWorkout(
  id: id,
  kind: kind,
  start: start.toUtc(),
  end: start.add(Duration(minutes: minutes)).toUtc(),
  activeKcal: kcal,
  source: source,
);

HealthSample _sample(DateTime at, double value) =>
    (from: at, to: at, value: value, source: 'Synthetic watch');

/// Resting HR alternating 53/57 (normal 53–57) and HRV alternating 41/50
/// (normal 41–50 ms) over 30 days.
HeartOverview _heart({bool sdnn = true}) => HeartOverview(
  restingHr: (day: DateTime(2026, 11, 24), value: 57),
  restingHrDaily: daily(30, (i) => i.isEven ? 53 : 57),
  hrv: (day: DateTime(2026, 11, 24), value: 50),
  hrvDaily: daily(30, (i) => i.isEven ? 41 : 50),
  vo2Max: (day: DateTime(2026, 11, 19), value: 44.1),
  vo2MaxDaily: [
    (day: DateTime(2026, 10, 12), value: 43.3),
    (day: DateTime(2026, 11, 19), value: 44.1),
  ],
  restingHrVsMonth: const TrendResult(
    direction: TrendDirection.down,
    tone: TrendTone.better,
    delta: -3,
  ),
  hrvVsNormal: null,
  hrvIsSdnn: sdnn,
);

BodyOverview _body(List<DayValue> weights) => BodyOverview(
  weight: weights.last,
  weightDaily: weights,
  bodyFat: (day: DateTime(2026, 11, 22), value: 17.2),
  weightVsMonth: null,
);

Future<void> _pump(
  WidgetTester tester,
  Widget page,
  HealthOverview overview, {
  FakeHealthReader? reader,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  List<WorkoutSessionRecord>? logged,
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fakeHealthOverview(FakeHealthOverviewController(overview)),
        healthReaderProvider.overrideWithValue(reader ?? FakeHealthReader()),
        if (logged != null)
          workoutHistoryRepositoryProvider.overrideWithValue(_History(logged)),
        healthOwnerIdProvider.overrideWithValue(_owner),
        healthClockProvider.overrideWithValue(() => overviewReadAt),
      ],
      child: MaterialApp(
        theme: BeyondRepTheme.build(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls through the whole page in both ranges so lazily built panels are
/// laid out too.
Future<void> _scrollThrough(WidgetTester tester) async {
  final list = find.byType(Scrollable).first;
  for (final range in ['30 days', '7 days']) {
    await tester.ensureVisible(find.text(range));
    await tester.tap(find.text(range));
    await tester.pumpAndSettle();
    for (var i = 0; i < 12; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  }
}

void main() {
  group('Heart', () {
    testWidgets('resting HR shows the normal band and Lower is better', (
      tester,
    ) async {
      await _pump(
        tester,
        const HeartDetailPage(),
        overview(heart: SectionData(_heart())),
      );
      expect(find.text('Resting heart rate'), findsOneWidget);
      expect(find.text('Lower is better'), findsOneWidget);
      expect(find.text('your normal 53–57'), findsOneWidget);
      expect(find.text('Higher is better'), findsOneWidget);
      expect(find.text('your normal 41–50 ms'), findsOneWidget);
      expect(find.text('▼ 3 bpm this month · better'), findsOneWidget);
    });

    testWidgets('VO2 max shows its change since 30+ days earlier', (
      tester,
    ) async {
      await _pump(
        tester,
        const HeartDetailPage(),
        overview(heart: SectionData(_heart())),
      );
      expect(find.text('44.1'), findsOneWidget);
      expect(find.text('▲ 0.8 since 12 Oct'), findsOneWidget);
    });

    testWidgets('HRV note names SDNN on iOS', (tester) async {
      await _pump(
        tester,
        const HeartDetailPage(),
        overview(heart: SectionData(_heart())),
      );
      expect(find.textContaining('reports HRV as SDNN'), findsOneWidget);
      expect(find.textContaining('reports HRV as RMSSD'), findsNothing);
    });

    testWidgets('HRV note names RMSSD on Android, no walking HR tile', (
      tester,
    ) async {
      await _pump(
        tester,
        const HeartDetailPage(),
        overview(
          platform: HealthPlatformKind.healthConnect,
          heart: SectionData(_heart(sdnn: false)),
        ),
      );
      expect(find.textContaining('reports HRV as RMSSD'), findsOneWidget);
      expect(find.textContaining('reports HRV as SDNN'), findsNothing);
      expect(find.text('Walking heart rate'), findsNothing);
    });

    testWidgets('iOS walking HR tile shows the latest day mean', (
      tester,
    ) async {
      final reader = FakeHealthReader()
        ..series[HealthSeriesType.walkingHeartRate] = [
          _sample(DateTime(2026, 11, 24, 7), 94),
          _sample(DateTime(2026, 11, 24, 7, 30), 98),
        ];
      await _pump(
        tester,
        const HeartDetailPage(),
        overview(heart: SectionData(_heart())),
        reader: reader,
      );
      expect(find.text('Walking heart rate'), findsOneWidget);
      expect(find.text('96 bpm'), findsOneWidget);
    });

    testWidgets('a failed VO2 max read offers Try again, not "none"', (
      tester,
    ) async {
      final heart = _heart();
      await _pump(
        tester,
        const HeartDetailPage(),
        overview(
          heart: SectionData(
            HeartOverview(
              restingHr: heart.restingHr,
              restingHrDaily: heart.restingHrDaily,
              hrv: heart.hrv,
              hrvDaily: heart.hrvDaily,
              vo2Max: null,
              vo2MaxDaily: const [],
              restingHrVsMonth: null,
              hrvVsNormal: null,
              hrvIsSdnn: true,
              vo2Gap: MetricGap.failed,
            ),
          ),
        ),
      );
      expect(find.text("Couldn't read · Try again"), findsOneWidget);
      expect(find.text('None in the last 90 days'), findsNothing);
    });

    testWidgets('Android heart not allowed reads Not allowed · Manage', (
      tester,
    ) async {
      await _pump(
        tester,
        const HeartDetailPage(),
        overview(
          platform: HealthPlatformKind.healthConnect,
          heart: const SectionGap(MetricGap.notAllowed),
        ),
      );
      expect(find.text('Not allowed · Manage'), findsOneWidget);
    });

    testWidgets('no overflow at text scale 2.0 in dark mode', (tester) async {
      await _pump(
        tester,
        const HeartDetailPage(),
        overview(heart: SectionData(_heart())),
        textScale: 2,
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      await _scrollThrough(tester);
    });
  });

  group('Activity', () {
    testWidgets('steps bars highlight today only', (tester) async {
      await _pump(tester, const ActivityDetailPage(), overview());
      final chart = tester.widget<NsBarChart>(find.byType(NsBarChart).first);
      expect(chart.bars, hasLength(30));
      expect(chart.bars.last.highlight, isTrue);
      expect(chart.bars.where((b) => b.highlight), hasLength(1));
      await tester.tap(find.text('7 days'));
      await tester.pumpAndSettle();
      final week = tester.widget<NsBarChart>(find.byType(NsBarChart).first);
      expect(week.bars, hasLength(7));
      expect(week.bars.last.highlight, isTrue);
    });

    testWidgets('shows the best day and active calories', (tester) async {
      await _pump(tester, const ActivityDetailPage(), overview());
      expect(find.text('Best day'), findsOneWidget);
      expect(find.text('Active calories'), findsOneWidget);
      expect(find.byType(NsBarChart), findsNWidgets(2));
    });

    testWidgets('Android active calories not allowed reads Not allowed', (
      tester,
    ) async {
      await _pump(
        tester,
        const ActivityDetailPage(),
        overview(
          platform: HealthPlatformKind.healthConnect,
          activity: SectionData(
            ActivityOverview(
              stepsToday: 8214,
              stepsDaily: daily(30, (i) => 9000),
              activeEnergyToday: null,
              activeEnergyDaily: const [],
              stepsWeekAverage: 9000,
              energyGap: MetricGap.notAllowed,
            ),
          ),
        ),
      );
      expect(find.text('Not allowed · Manage'), findsOneWidget);
      expect(find.textContaining('need a watch'), findsNothing);
    });

    // Yesterday's 10:02 session absorbs the 10:00 Apple Watch workout; the
    // 06:00 run today stands alone.
    final yesterday = DateTime(2026, 11, 23, 10, 2);
    final session = _logged('s1', yesterday, 48);
    final merged = _outsideWorkout(
      'o1',
      DateTime(2026, 11, 23, 10),
      30,
      kind: OutsideWorkoutKind.strength,
      kcal: 131,
      source: 'Apple Watch',
    );
    final run = _outsideWorkout('o2', DateTime(2026, 11, 24, 6), 45, kcal: 286);
    HealthOverview withWorkouts() => overview(
      workouts: SectionData(WorkoutsOverview(outside: [merged, run])),
    );

    testWidgets('Workouts panel has bars, a merged BeyondRep row and a '
        'standalone Running row', (tester) async {
      await _pump(
        tester,
        const ActivityDetailPage(),
        withWorkouts(),
        logged: [session],
      );
      expect(find.text('Workouts'), findsOneWidget);
      expect(
        find.bySemanticsLabel('About Workouts from other apps'),
        findsOneWidget,
      );
      expect(find.byType(NsBarChart), findsNWidgets(3));
      expect(find.text('2 workouts · 93 min'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Running'), 300);
      expect(find.text('Running'), findsOneWidget);
      expect(find.textContaining('Today 6:00 AM · 45 min'), findsOneWidget);
      expect(find.textContaining('286 kcal'), findsOneWidget);
      expect(find.text('From Synthetic app'), findsOneWidget);
      expect(find.text('Push day'), findsOneWidget);
      expect(
        find.textContaining('Yesterday 10:02 AM · 48 min'),
        findsOneWidget,
      );
      expect(
        find.textContaining('From Apple Watch · 131 kcal'),
        findsOneWidget,
      );
      // The merged workout is not listed on its own.
      expect(find.text('Strength training'), findsNothing);
    });

    testWidgets('the 30-day chip widens the workouts chart', (tester) async {
      await _pump(
        tester,
        const ActivityDetailPage(),
        withWorkouts(),
        logged: [session],
      );
      expect(
        tester.widget<NsBarChart>(find.byType(NsBarChart).last).bars,
        hasLength(30),
      );
      await tester.tap(find.text('7 days'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NsBarChart>(find.byType(NsBarChart).last).bars,
        hasLength(7),
      );
      await tester.tap(find.text('30 days'));
      await tester.pumpAndSettle();
      final bars = tester.widget<NsBarChart>(find.byType(NsBarChart).last).bars;
      expect(bars, hasLength(30));
      expect(bars.last.total, 45);
      expect(bars[28].total, 48);
    });

    testWidgets('workouts not allowed shows the gap panel and still lists '
        'BeyondRep sessions', (tester) async {
      await _pump(
        tester,
        const ActivityDetailPage(),
        overview(workouts: const SectionGap(MetricGap.notAllowed)),
        logged: [session],
      );
      expect(find.text('Not allowed · Manage'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Push day'), 300);
      expect(find.text('Push day'), findsOneWidget);
      expect(find.byType(NsBarChart), findsNWidgets(2));
    });

    testWidgets('Workouts panel has no overflow at text scale 2.0 in dark '
        'mode', (tester) async {
      await _pump(
        tester,
        const ActivityDetailPage(),
        withWorkouts(),
        logged: [session],
        textScale: 2,
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 8; i++) {
        await tester.drag(list, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('lists at most 10 workouts, then See all in Progress', (
      tester,
    ) async {
      await _pump(
        tester,
        const ActivityDetailPage(),
        overview(workouts: SectionData(const WorkoutsOverview(outside: []))),
        logged: [
          for (var i = 1; i <= 12; i++)
            _logged(
              's$i',
              DateTime(2026, 11, 24, 6).subtract(Duration(days: i)),
              30,
              name: 'Day $i',
            ),
        ],
      );
      await tester.scrollUntilVisible(find.text('See all in Progress'), 400);
      expect(find.text('Day 10'), findsOneWidget);
      expect(find.text('Day 11'), findsNothing);
    });

    testWidgets('no overflow at text scale 2.0 in dark mode', (tester) async {
      await _pump(
        tester,
        const ActivityDetailPage(),
        overview(),
        textScale: 2,
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      await _scrollThrough(tester);
    });
  });

  group('Body', () {
    testWidgets('weekly change with 3 weigh-ins shows no rate', (tester) async {
      await _pump(
        tester,
        const BodyDetailPage(),
        overview(
          body: SectionData(
            _body([
              (day: DateTime(2026, 11, 10), value: 80.0),
              (day: DateTime(2026, 11, 17), value: 79.5),
              (day: DateTime(2026, 11, 24), value: 79.0),
            ]),
          ),
        ),
      );
      expect(find.text('Average weekly change'), findsOneWidget);
      expect(find.textContaining('kg a week'), findsNothing);
      expect(find.textContaining('Needs 4 weigh-ins'), findsOneWidget);
    });

    testWidgets('weekly change with 4 weigh-ins shows the rate', (
      tester,
    ) async {
      await _pump(
        tester,
        const BodyDetailPage(),
        overview(
          body: SectionData(
            _body([
              (day: DateTime(2026, 11, 3), value: 80.0),
              (day: DateTime(2026, 11, 10), value: 79.5),
              (day: DateTime(2026, 11, 17), value: 79.0),
              (day: DateTime(2026, 11, 24), value: 78.5),
            ]),
          ),
        ),
      );
      expect(find.text('−0.5 kg a week'), findsOneWidget);
      expect(find.text('17.2%'), findsOneWidget);
    });

    testWidgets('body fat not allowed reads Not allowed', (tester) async {
      await _pump(
        tester,
        const BodyDetailPage(),
        overview(
          platform: HealthPlatformKind.healthConnect,
          body: SectionData(
            BodyOverview(
              weight: (day: DateTime(2026, 11, 24), value: 78.4),
              weightDaily: [(day: DateTime(2026, 11, 24), value: 78.4)],
              bodyFat: null,
              weightVsMonth: null,
              bodyFatGap: MetricGap.notAllowed,
            ),
          ),
        ),
      );
      expect(find.text('Body fat'), findsOneWidget);
      expect(find.text('Not allowed · Manage'), findsOneWidget);
    });

    testWidgets('no lean mass tile without a reading', (tester) async {
      await _pump(tester, const BodyDetailPage(), overview());
      expect(find.text('Lean mass'), findsNothing);
    });

    testWidgets('lean mass shows when present', (tester) async {
      await _pump(
        tester,
        const BodyDetailPage(),
        overview(),
        reader: FakeHealthReader()
          ..series[HealthSeriesType.leanMass] = [
            _sample(DateTime(2026, 11, 22, 8), 61.3),
          ],
      );
      expect(find.text('Lean mass'), findsOneWidget);
      expect(find.text('61.3 kg'), findsOneWidget);
    });

    testWidgets('no overflow at text scale 2.0 in dark mode', (tester) async {
      await _pump(
        tester,
        const BodyDetailPage(),
        overview(),
        textScale: 2,
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      await _scrollThrough(tester);
    });
  });

  test('walking HR is dropped when the account changes', () async {
    final reader = FakeHealthReader()
      ..series[HealthSeriesType.walkingHeartRate] = [
        _sample(DateTime(2026, 11, 24, 7), 96),
      ];
    final c = ProviderContainer(
      overrides: [
        fakeHealthOverview(FakeHealthOverviewController(overview())),
        healthReaderProvider.overrideWithValue(reader),
        healthOwnerIdProvider.overrideWith((ref) => ref.watch(_ownerProvider)),
        healthClockProvider.overrideWithValue(() => overviewReadAt),
      ],
    );
    addTearDown(c.dispose);
    c.listen(walkingHrProvider, (_, _) {});
    final first = await c.read(walkingHrProvider.future);
    expect((first! as SectionData<DayValue>).value.value, 96);

    c.read(_ownerProvider.notifier).set('other-owner');
    expect(c.read(walkingHrProvider).isLoading, isTrue);
    expect(await c.read(walkingHrProvider.future), isNull);
  });

  test('walking HR is unsupported on Android without a read', () async {
    final reader = FakeHealthReader(platform: HealthPlatformKind.healthConnect);
    final c = ProviderContainer(
      overrides: [
        fakeHealthOverview(
          FakeHealthOverviewController(
            overview(platform: HealthPlatformKind.healthConnect),
          ),
        ),
        healthReaderProvider.overrideWithValue(reader),
        healthOwnerIdProvider.overrideWithValue(_owner),
        healthClockProvider.overrideWithValue(() => overviewReadAt),
      ],
    );
    addTearDown(c.dispose);
    final result = await c.read(walkingHrProvider.future);
    expect((result! as SectionGap<DayValue>).gap, MetricGap.unsupported);
    expect(reader.seriesCalls, isEmpty);
  });

  group('About buttons', () {
    final apple = HealthPlatformKind.appleHealth;

    testWidgets('Heart panels and the walking row have About buttons', (
      tester,
    ) async {
      final reader = FakeHealthReader()
        ..series[HealthSeriesType.walkingHeartRate] = [
          _sample(DateTime(2026, 11, 24, 7), 94),
        ];
      await _pump(
        tester,
        const HeartDetailPage(),
        overview(heart: SectionData(_heart())),
        reader: reader,
      );
      for (final title in [
        'Resting heart rate',
        'Heart rate variability (HRV)',
        'Walking heart rate',
      ]) {
        expect(
          find.bySemanticsLabel('About $title'),
          findsOneWidget,
          reason: title,
        );
      }
      await tester.tap(find.bySemanticsLabel('About Resting heart rate'));
      await tester.pumpAndSettle();
      expect(
        find.text(explanationFor(MetricKey.restingHeartRate, apple).what),
        findsOneWidget,
      );
      expect(find.text('Your usual 53 to 57 bpm'), findsOneWidget);
    });

    testWidgets('stale readings show the usual range but no Today line', (
      tester,
    ) async {
      final stale = DateTime(2026, 11, 22);
      final heart = HeartOverview(
        restingHr: (day: stale, value: 57),
        restingHrDaily: daily(30, (i) => i.isEven ? 53 : 57),
        hrv: (day: stale, value: 50),
        hrvDaily: daily(30, (i) => i.isEven ? 41 : 50),
        vo2Max: null,
        vo2MaxDaily: const [],
        restingHrVsMonth: null,
        hrvVsNormal: null,
        hrvIsSdnn: true,
      );
      await _pump(
        tester,
        const HeartDetailPage(),
        overview(heart: SectionData(heart)),
      );
      for (final title in [
        'Resting heart rate',
        'Heart rate variability (HRV)',
      ]) {
        await tester.tap(find.bySemanticsLabel('About $title'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Your usual'),
          findsOneWidget,
          reason: title,
        );
        expect(find.textContaining('Today '), findsNothing, reason: title);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('a stale weight shows the usual range but no Today line', (
      tester,
    ) async {
      final stale = DateTime(2026, 11, 22);
      final weights = daily(30, (i) => 79.0 - i * 0.03);
      await _pump(
        tester,
        const BodyDetailPage(),
        overview(
          body: SectionData(
            BodyOverview(
              weight: (day: stale, value: 78.4),
              weightDaily: weights,
              bodyFat: null,
              weightVsMonth: null,
            ),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('About Weight'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your usual'), findsOneWidget);
      expect(find.textContaining('Today '), findsNothing);
    });

    testWidgets('Activity panels have About buttons with a daily average', (
      tester,
    ) async {
      await _pump(tester, const ActivityDetailPage(), overview());
      expect(find.bySemanticsLabel('About Steps'), findsOneWidget);
      expect(find.bySemanticsLabel('About Active calories'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('About Steps'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your daily average 9,'), findsOneWidget);
    });

    testWidgets('Log weight shows in the weight panel', (tester) async {
      await _pump(tester, const BodyDetailPage(), overview());
      expect(find.text('Log weight'), findsOneWidget);
    });

    testWidgets('Log weight shows when the whole body section is a gap', (
      tester,
    ) async {
      await _pump(
        tester,
        const BodyDetailPage(),
        overview(body: const SectionGap(MetricGap.noData)),
      );
      expect(find.text('Log weight'), findsOneWidget);
    });

    testWidgets('Log weight shows in the weight gap panel', (tester) async {
      await _pump(
        tester,
        const BodyDetailPage(),
        overview(
          body: SectionData(
            BodyOverview(
              weight: null,
              weightDaily: const [],
              bodyFat: null,
              weightVsMonth: null,
              weightGap: MetricGap.noData,
            ),
          ),
        ),
      );
      expect(find.text('Log weight'), findsOneWidget);
    });

    testWidgets('Body weight panel and body fat tile have About buttons', (
      tester,
    ) async {
      await _pump(tester, const BodyDetailPage(), overview());
      expect(find.bySemanticsLabel('About Weight'), findsOneWidget);
      expect(find.bySemanticsLabel('About Body fat'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('About Body fat'));
      await tester.pumpAndSettle();
      expect(
        find.text(explanationFor(MetricKey.bodyFat, apple).what),
        findsOneWidget,
      );
    });
  });
}
