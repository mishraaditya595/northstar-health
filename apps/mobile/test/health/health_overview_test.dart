import 'dart:async';
import 'dart:io';

import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_connection_repository.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:beyondrep/features/health/domain/outside_workouts.dart';
import 'package:beyondrep/features/progress/data/objectbox_workout_history_repository.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/progress/workout_history_state.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_reader.dart';

const _ownerA = 'owner-a';
const _ownerB = 'owner-b';

class _Owner extends Notifier<String?> {
  @override
  String? build() => _ownerA;

  void set(String? owner) => state = owner;
}

final _ownerProvider = NotifierProvider<_Owner, String?>(_Owner.new);

class _OwnIds extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void set(Set<String> ids) => state = ids;
}

final _ownIdsProvider = NotifierProvider<_OwnIds, Set<String>>(_OwnIds.new);

class _FakeHistory implements WorkoutHistoryRepository {
  _FakeHistory(this.sessions, {this.fail = false});
  final List<WorkoutSessionRecord> sessions;
  final bool fail;

  @override
  WorkoutHistorySnapshot readCompleted() =>
      WorkoutHistorySnapshot(sessions: sessions);

  @override
  Future<WorkoutHistorySnapshot> readCompletedAsync() async =>
      fail ? throw StateError('synthetic history bug') : readCompleted();
}

/// A completed 60 minute BeyondRep session [daysBack] days before the
/// test's clock, at 09:00 local.
WorkoutSessionRecord _logged(String id, int daysBack) {
  final start = DateTime(2026, 11, 24 - daysBack, 9);
  return WorkoutSessionRecord(
    uuid: id,
    name: 'Logged',
    status: WorkoutStatus.completed,
    startedAtUtc: start.toUtc(),
    completedAtUtc: start.add(const Duration(hours: 1)).toUtc(),
    originalOffsetMinutes: 0,
    revision: 1,
  );
}

OutsideWorkout _outside(String id, int daysBack, {int hour = 18}) {
  final start = DateTime(2026, 11, 24 - daysBack, hour);
  return OutsideWorkout(
    id: id,
    kind: OutsideWorkoutKind.running,
    start: start.toUtc(),
    end: start.add(const Duration(minutes: 30)).toUtc(),
    source: 'Synthetic app',
  );
}

/// Delegates to [inner]; [connectedAt] throws while [fail] is set.
class _FlakyRepo implements HealthConnectionRepository {
  _FlakyRepo(this.inner);
  final HealthConnectionRepository inner;
  bool fail = false;

  @override
  bool isConnected(String owner) => inner.isConnected(owner);
  @override
  DateTime? connectedAt(String owner) =>
      fail ? throw StateError('synthetic store bug') : inner.connectedAt(owner);
  @override
  void connect(String owner, DateTime at) => inner.connect(owner, at);
  @override
  int accessScope(String owner) => inner.accessScope(owner);
  @override
  void recordAccessScope(String owner, int scope) =>
      inner.recordAccessScope(owner, scope);
  @override
  void disconnect(String owner) => inner.disconnect(owner);
}

SleepSegment _seg(DateTime from, DateTime to, SleepStage stage) => (
  from: from,
  to: to,
  stage: stage,
  source: 'Synthetic watch',
  sourceKey: 'watch',
);

/// Staged night ending on [date] at 06:30; 23:00 -> 06:30 = 450 min asleep,
/// minus [shortBy] minutes cut from the start.
List<SleepSegment> _night(DateTime date, {int shortBy = 0}) {
  DateTime at(int h, [int m = 0]) =>
      DateTime(date.year, date.month, date.day, h, m);
  return [
    _seg(at(-1).add(Duration(minutes: shortBy)), at(0, 30), SleepStage.light),
    _seg(at(0, 30), at(1, 30), SleepStage.deep),
    _seg(at(1, 30), at(3), SleepStage.light),
    _seg(at(3), at(4), SleepStage.rem),
    _seg(at(4), at(6), SleepStage.light),
    _seg(at(6), at(6, 30), SleepStage.rem),
  ];
}

HealthSample _sample(DateTime at, double value) =>
    (from: at, to: at, value: value, source: 'Synthetic source');

DateTime _day(int offset) => DateTime(2026, 11, 24 + offset);

void main() {
  late Directory root;
  late Store store;
  late HealthConnectionRepository repo;
  late FakeHealthReader fake;
  Set<String> ownWorkoutIds = const {};
  late DateTime now;

  setUp(() {
    root = Directory.systemTemp.createTempSync('beyondrep-health-overview-');
    store = Store(getObjectBoxModel(), directory: '${root.path}/db');
    repo = ObjectBoxHealthConnectionRepository(store);
    fake = FakeHealthReader();
    ownWorkoutIds = const {};
    now = DateTime(2026, 11, 24, 7, 42);
    repo.connect(_ownerA, DateTime(2026, 11, 1));
  });
  tearDown(() {
    store.close();
    root.deleteSync(recursive: true);
  });

  WorkoutHistoryRepository? history;

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        if (history != null)
          workoutHistoryRepositoryProvider.overrideWithValue(history!),
        healthReaderProvider.overrideWithValue(fake),
        healthConnectionRepositoryProvider.overrideWithValue(repo),
        healthOwnerIdProvider.overrideWith((ref) => ref.watch(_ownerProvider)),
        healthClockProvider.overrideWithValue(() => now),
        ownPlatformWorkoutIdsProvider.overrideWith((ref) {
          final live = ref.watch(_ownIdsProvider);
          return {...ownWorkoutIds, ...live};
        }),
      ],
    );
    addTearDown(c.dispose);
    c.listen(healthOverviewProvider, (_, _) {});
    return c;
  }

  void syntheticWeek() {
    fake.sleep = [
      for (var i = -7; i < 0; i++) ..._night(_day(i)),
      ..._night(_day(0), shortBy: 60),
    ];
    fake.series[HealthSeriesType.heartRate] = [
      _sample(DateTime(2026, 11, 24, 2), 50),
      _sample(DateTime(2026, 11, 24, 3), 52),
    ];
    fake.series[HealthSeriesType.restingHeartRate] = [
      for (var i = -9; i < 0; i++) _sample(_day(i).add(Duration(hours: 8)), 58),
      _sample(DateTime(2026, 11, 24, 7), 54),
    ];
    fake.series[HealthSeriesType.hrv] = [
      _sample(DateTime(2026, 11, 24, 2), 60),
      _sample(DateTime(2026, 11, 24, 7, 30), 30),
      _sample(DateTime(2026, 11, 23, 14), 40),
    ];
    fake.totals[HealthTotalType.steps] = [
      for (var i = -7; i < 0; i++)
        (
          from: _day(i).add(Duration(hours: 10)),
          to: _day(i).add(Duration(hours: 11)),
          value: 7000.0 + 100 * i,
          source: 'Synthetic phone',
        ),
      (
        from: DateTime(2026, 11, 24, 7),
        to: DateTime(2026, 11, 24, 7, 42),
        value: 900,
        source: 'Synthetic phone',
      ),
    ];
    fake.series[HealthSeriesType.weight] = [
      _sample(DateTime(2026, 11, 2, 7), 80),
      _sample(DateTime(2026, 11, 23, 7), 79),
    ];
  }

  test(
    'builds sleep, heart, activity and body from synthetic series',
    () async {
      syntheticWeek();
      final c = container();
      final overview = (await c.read(healthOverviewProvider.future))!;

      expect(overview.readAt, now);
      expect(overview.platform, HealthPlatformKind.appleHealth);
      expect(overview.readableFrom, isNull);
      expect(overview.needsMoreAccess, false);

      final sleep = (overview.sleep as SectionData<SleepOverview>).value;
      expect(sleep.lastNight.date, _day(0));
      expect(sleep.lastNight.asleep, const Duration(minutes: 390));
      expect(sleep.score, isNotNull);
      expect(sleep.sleepAvgHr, 51);
      expect(sleep.nights, hasLength(8));
      expect(sleep.vsWeek!.delta, -60);

      final heart = (overview.heart as SectionData<HeartOverview>).value;
      expect(heart.restingHr!.value, 54);
      expect(heart.restingHrDaily, hasLength(10));
      expect(heart.restingHrVsMonth!.delta, -4);
      expect(heart.hrv!.value, 60, reason: 'overnight samples win');
      expect(heart.hrvDaily.map((d) => d.value), [40, 60]);
      expect(heart.hrvVsNormal, isNull, reason: 'fewer than 7 prior days');
      expect(heart.hrvIsSdnn, true);

      final activity =
          (overview.activity as SectionData<ActivityOverview>).value;
      expect(activity.stepsToday, 900);
      expect(activity.stepsSource, 'Synthetic phone');
      expect(activity.stepsDaily, hasLength(8));
      expect(activity.stepsWeekAverage, 6600);
      expect(activity.activeEnergyToday, isNull);

      final body = (overview.body as SectionData<BodyOverview>).value;
      expect(body.weight!.value, 79);
      expect(body.weightVsMonth!.delta, -1);
      expect(body.weightSince, isNull, reason: '2 Nov is 21 days earlier');
      expect(body.bodyFat, isNull);

      expect(fake.sleepCalls.single, (DateTime(2026, 10, 24, 18), now));
      expect(fake.totalsCalls.map((c) => (c.$1, c.$2)), {
        (HealthTotalType.steps, DateTime(2026, 10, 26)),
        (HealthTotalType.activeEnergy, DateTime(2026, 10, 26)),
      });
      final vo2 = fake.seriesCalls.where(
        (c) => c.$1 == HealthSeriesType.vo2Max,
      );
      expect(vo2.single.$2, DateTime(2026, 8, 27));
    },
  );

  test('a weight change over a few days names its start date', () async {
    fake.series[HealthSeriesType.weight] = [
      _sample(DateTime(2026, 11, 22, 7), 80),
      _sample(DateTime(2026, 11, 24, 7), 79.5),
    ];
    final c = container();
    final overview = (await c.read(healthOverviewProvider.future))!;
    final body = (overview.body as SectionData<BodyOverview>).value;
    expect(body.weightVsMonth!.delta, -0.5);
    expect(body.weightSince, DateTime(2026, 11, 22));
  });

  test('vsWeek needs at least 3 prior nights', () async {
    fake.sleep = [..._night(_day(-2)), ..._night(_day(-1)), ..._night(_day(0))];
    final c = container();
    final overview = (await c.read(healthOverviewProvider.future))!;
    final sleep = (overview.sleep as SectionData<SleepOverview>).value;
    expect(sleep.vsWeek, isNull);
  });

  test('phone-only person', () async {
    fake.totals[HealthTotalType.steps] = [
      (
        from: DateTime(2026, 11, 24, 7),
        to: DateTime(2026, 11, 24, 7, 42),
        value: 500,
        source: 'Synthetic phone',
      ),
    ];
    fake.series[HealthSeriesType.weight] = [
      _sample(DateTime(2026, 11, 20, 7), 70),
    ];
    final c = container();
    final overview = (await c.read(healthOverviewProvider.future))!;

    expect((overview.sleep as SectionGap).gap, MetricGap.noData);
    expect((overview.heart as SectionGap).gap, MetricGap.noData);
    expect(overview.activity, isA<SectionData<ActivityOverview>>());
    expect(overview.body, isA<SectionData<BodyOverview>>());
    expect(
      fake.seriesCalls.where((c) => c.$1 == HealthSeriesType.heartRate),
      isEmpty,
    );
  });

  test('steps from two sources today have no single source', () async {
    fake.totals[HealthTotalType.steps] = [
      (
        from: DateTime(2026, 11, 24, 6),
        to: DateTime(2026, 11, 24, 7),
        value: 500,
        source: 'Synthetic phone',
      ),
      (
        from: DateTime(2026, 11, 24, 7),
        to: DateTime(2026, 11, 24, 7, 30),
        value: 400,
        source: 'Synthetic watch',
      ),
    ];
    final c = container();
    final overview = (await c.read(healthOverviewProvider.future))!;
    final activity = (overview.activity as SectionData<ActivityOverview>).value;
    expect(activity.stepsSource, isNull);
  });

  group('steps today of 0', () {
    void zeroToday() {
      fake.totals[HealthTotalType.steps] = [
        (
          from: _day(-1).add(const Duration(hours: 10)),
          to: _day(-1).add(const Duration(hours: 11)),
          value: 6400,
          source: 'Synthetic phone',
        ),
        (
          from: DateTime(2026, 11, 24, 6),
          to: DateTime(2026, 11, 24, 7),
          value: 0,
          source: 'Synthetic phone',
        ),
      ];
    }

    test('is no data on iOS', () async {
      zeroToday();
      final c = container();
      final overview = (await c.read(healthOverviewProvider.future))!;
      final activity =
          (overview.activity as SectionData<ActivityOverview>).value;
      expect(activity.stepsToday, isNull);
      expect(activity.stepsDaily, isNotEmpty);
    });

    test('stays 0 on Health Connect', () async {
      fake = FakeHealthReader(platform: HealthPlatformKind.healthConnect);
      zeroToday();
      final c = container();
      final overview = (await c.read(healthOverviewProvider.future))!;
      final activity =
          (overview.activity as SectionData<ActivityOverview>).value;
      expect(activity.stepsToday, 0);
    });
  });

  test('Phase 3 account', () async {
    fake
      ..needsMore = true
      ..seriesResults[HealthSeriesType.hrv] = const SeriesNeedsAccess()
      ..series[HealthSeriesType.restingHeartRate] = [
        _sample(DateTime(2026, 11, 24, 7), 54),
      ];
    final c = container();
    final overview = (await c.read(healthOverviewProvider.future))!;

    expect(overview.needsMoreAccess, true);
    final heart = (overview.heart as SectionData<HeartOverview>).value;
    expect(heart.restingHr!.value, 54);
    expect(heart.hrv, isNull);
  });

  group('Android "Allow more data" follows the requested scope', () {
    setUp(() {
      fake = FakeHealthReader(platform: HealthPlatformKind.healthConnect)
        // Health Connect still reports some types declined.
        ..needsMore = true;
    });

    test('a Phase 3 account (scope 0) is asked', () async {
      repo.recordAccessScope(_ownerA, 0);
      final c = container();
      final overview = (await c.read(healthOverviewProvider.future))!;
      expect(overview.needsMoreAccess, true);
    });

    test('one request hides it even when types stay declined', () async {
      repo.recordAccessScope(_ownerA, 0);
      final c = container();
      await c.read(healthOverviewProvider.future);
      await c.read(healthOverviewProvider.notifier).requestMoreAccess();
      expect(fake.requestMoreAccessCalls, 1);
      expect(repo.accessScope(_ownerA), currentHealthAccessScope);
      final overview = (await c.read(healthOverviewProvider.future))!;
      expect(overview.needsMoreAccess, false);
    });

    test('a fresh connect is not asked again', () async {
      final c = container();
      final overview = (await c.read(healthOverviewProvider.future))!;
      expect(overview.needsMoreAccess, false);
    });

    test('nothing declined is not asked even at scope 0', () async {
      repo.recordAccessScope(_ownerA, 0);
      fake.needsMore = false;
      final c = container();
      final overview = (await c.read(healthOverviewProvider.future))!;
      expect(overview.needsMoreAccess, false);
    });
  });

  test('a section with no data maps the read result to its gap', () async {
    fake
      ..seriesResults[HealthSeriesType.weight] = const SeriesNotAllowed()
      ..seriesResults[HealthSeriesType.restingHeartRate] = const SeriesFailed()
      ..throwOnSeries = {HealthSeriesType.hrv};
    final c = container();
    final overview = (await c.read(healthOverviewProvider.future))!;

    expect((overview.body as SectionGap).gap, MetricGap.notAllowed);
    expect((overview.heart as SectionGap).gap, MetricGap.failed);
    expect((overview.activity as SectionGap).gap, MetricGap.noData);
  });

  test('a metric gap is kept when its section has other data', () async {
    fake = FakeHealthReader(platform: HealthPlatformKind.healthConnect);
    syntheticWeek();
    fake
      ..totalsResults[HealthTotalType.steps] = const SeriesNotAllowed()
      ..totals[HealthTotalType.activeEnergy] = [
        (
          from: DateTime(2026, 11, 24, 7),
          to: DateTime(2026, 11, 24, 7, 42),
          value: 120,
          source: 'Synthetic watch',
        ),
      ]
      ..seriesResults[HealthSeriesType.restingHeartRate] =
          const SeriesNotAllowed()
      ..seriesResults[HealthSeriesType.vo2Max] = const SeriesFailed()
      ..seriesResults[HealthSeriesType.bodyFat] = const SeriesNotAllowed()
      ..seriesResults[HealthSeriesType.heartRate] = const SeriesNotAllowed();
    final c = container();
    final overview = (await c.read(healthOverviewProvider.future))!;

    final sleep = (overview.sleep as SectionData<SleepOverview>).value;
    expect(sleep.sleepHrGap, MetricGap.notAllowed);
    expect(sleep.sleepAvgHr, isNull);

    final activity = (overview.activity as SectionData<ActivityOverview>).value;
    expect(activity.stepsGap, MetricGap.notAllowed);
    expect(activity.energyGap, isNull);
    final heart = (overview.heart as SectionData<HeartOverview>).value;
    expect(heart.restingHrGap, MetricGap.notAllowed);
    expect(heart.hrvGap, isNull);
    expect(heart.vo2Gap, MetricGap.failed);
    final body = (overview.body as SectionData<BodyOverview>).value;
    expect(body.bodyFatGap, MetricGap.notAllowed);
    expect(body.weightGap, isNull);
  });

  test('a heart section with only VO2 max still shows', () async {
    fake.series[HealthSeriesType.vo2Max] = [
      _sample(DateTime(2026, 11, 20, 9), 44.5),
    ];
    final c = container();
    final overview = (await c.read(healthOverviewProvider.future))!;

    final heart = (overview.heart as SectionData<HeartOverview>).value;
    expect(heart.vo2Max!.value, 44.5);
    expect(heart.restingHr, isNull);
    expect(heart.hrv, isNull);
  });

  test('a VO2 max gap ranks in an empty heart section', () async {
    fake.seriesResults[HealthSeriesType.vo2Max] = const SeriesNotAllowed();
    final c = container();
    final overview = (await c.read(healthOverviewProvider.future))!;

    expect((overview.heart as SectionGap).gap, MetricGap.notAllowed);
  });

  test('needsAccess outranks failed when a section has no data', () async {
    fake
      ..seriesResults[HealthSeriesType.restingHeartRate] = const SeriesFailed()
      ..seriesResults[HealthSeriesType.hrv] = const SeriesNeedsAccess();
    final c = container();
    final overview = (await c.read(healthOverviewProvider.future))!;

    expect((overview.heart as SectionGap).gap, MetricGap.needsAccess);
  });

  test('overnight HRV does not feed the previous day mean', () async {
    fake
      ..sleep = _night(_day(0))
      ..series[HealthSeriesType.hrv] = [
        _sample(DateTime(2026, 11, 23, 14), 40),
        _sample(DateTime(2026, 11, 23, 23, 30), 90),
      ];
    final c = container();
    final overview = (await c.read(healthOverviewProvider.future))!;
    final heart = (overview.heart as SectionData<HeartOverview>).value;

    expect(heart.hrvDaily, [
      (day: _day(-1), value: 40.0),
      (day: _day(0), value: 90.0),
    ]);
  });

  test('Android without history, connected 10 days ago', () async {
    fake = FakeHealthReader(platform: HealthPlatformKind.healthConnect)
      ..history = false;
    final connectedAt = DateTime(2026, 11, 14, 9);
    repo.connect(_ownerA, connectedAt);
    final c = container();
    final overview = (await c.read(healthOverviewProvider.future))!;

    expect(overview.readableFrom, connectedAt.subtract(Duration(days: 30)));
  });

  test("heart rate is read only inside last night's window", () async {
    syntheticWeek();
    final c = container();
    final overview = (await c.read(healthOverviewProvider.future))!;
    final night =
        (overview.sleep as SectionData<SleepOverview>).value.lastNight;

    final hr = fake.seriesCalls.where(
      (c) => c.$1 == HealthSeriesType.heartRate,
    );
    expect(hr.single, (HealthSeriesType.heartRate, night.start, night.end));
    expect(night.start, DateTime(2026, 11, 24));
    expect(night.end, DateTime(2026, 11, 24, 6, 30));
  });

  test('account switch mid-read discards the result', () async {
    syntheticWeek();
    fake.sleepGate = Completer<void>();
    final c = container();
    final pending = c.read(healthOverviewProvider.future);
    while (fake.sleepCalls.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }

    c.read(_ownerProvider.notifier).set(_ownerB);
    fake.sleepGate!.complete();
    await pending.catchError((_) => null);

    expect(await c.read(healthOverviewProvider.future), isNull);
    expect(c.read(healthOverviewProvider).value, isNull);
  });

  test("switching to a connected account never exposes A's overview", () async {
    syntheticWeek();
    repo.connect(_ownerB, DateTime(2026, 11, 1));
    final c = container();
    final a = (await c.read(healthOverviewProvider.future))!;
    expect(a.ownerId, _ownerA);

    fake.sleepGate = Completer<void>();
    c.read(_ownerProvider.notifier).set(_ownerB);
    while (fake.sleepCalls.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    final mid = c.read(healthOverviewProvider);
    expect(mid.isLoading, true);
    expect(mid.value, isNull);

    fake.sleepGate!.complete();
    final b = (await c.read(healthOverviewProvider.future))!;
    expect(b.ownerId, _ownerB);
  });

  /// 20 prior days of HRV and resting HR plus today's values, on top of
  /// [syntheticWeek]'s nights.
  void readinessWeek() {
    syntheticWeek();
    fake.series[HealthSeriesType.restingHeartRate] = [
      for (var i = -20; i < 0; i++)
        _sample(
          _day(i).add(const Duration(hours: 8)),
          58 + (i.isEven ? 1 : -1),
        ),
      _sample(DateTime(2026, 11, 24, 7), 54),
    ];
    fake.series[HealthSeriesType.hrv] = [
      for (var i = -20; i < 0; i++)
        _sample(
          _day(i).add(const Duration(hours: 14)),
          40 + (i.isEven ? 2 : -2),
        ),
      _sample(DateTime(2026, 11, 24, 2), 50),
    ];
  }

  group('readiness', () {
    test('scores from the overview inputs like the domain does', () async {
      readinessWeek();
      final c = container();
      final o = (await c.read(healthOverviewProvider.future))!;
      final sleep = (o.sleep as SectionData<SleepOverview>).value;
      final heart = (o.heart as SectionData<HeartOverview>).value;
      final r = (o.readiness as SectionData<ReadinessOverview>).value;

      final expected = scoreReadiness(
        today: _day(0),
        lastNight: sleep.lastNight,
        sleepScore: sleep.score,
        priorNights: sleep.nights.sublist(0, sleep.nights.length - 1),
        hrvDaily: heart.hrvDaily,
        restingHrDaily: heart.restingHrDaily,
      );
      expect(expected, isA<ReadinessReady>());
      expect(
        (r.result as ReadinessReady).readiness.value,
        (expected as ReadinessReady).readiness.value,
      );
      expect(r.hasHrv && r.hasRestingHr && r.hasSleep, true);
      expect(r.hrvIsSdnn, true);
      expect(r.hrvBaseline!.days, 20);
      expect(r.restingHrBaseline!.mean, closeTo(58, 0.01));
      expect(r.hrvVsNormal!.delta, closeTo(10, 0.01));
      expect(r.restingHrVsNormal!.delta, closeTo(-4, 0.01));
    });

    test('a phone-only person gets NotReady with nothing present', () async {
      fake.totals[HealthTotalType.steps] = [
        (
          from: DateTime(2026, 11, 24, 7),
          to: DateTime(2026, 11, 24, 7, 42),
          value: 900,
          source: 'Synthetic phone',
        ),
      ];
      final c = container();
      final o = (await c.read(healthOverviewProvider.future))!;
      // Both sections gap for the same reason: readiness is that gap.
      expect((o.readiness as SectionGap).gap, MetricGap.noData);
    });

    test('a heart gap still yields NotReady naming what is missing', () async {
      syntheticWeek();
      fake.seriesResults[HealthSeriesType.restingHeartRate] =
          const SeriesNotAllowed();
      fake.seriesResults[HealthSeriesType.hrv] = const SeriesNotAllowed();
      fake.seriesResults[HealthSeriesType.vo2Max] = const SeriesNotAllowed();
      final c = container();
      final o = (await c.read(healthOverviewProvider.future))!;
      expect((o.heart as SectionGap).gap, MetricGap.notAllowed);
      final r = (o.readiness as SectionData<ReadinessOverview>).value;
      final result = r.result as ReadinessNotReady;
      expect(result.noHrvOrRhrToday, true);
      expect(result.noSleep, false);
      expect(r.hasHrv || r.hasRestingHr, false);
      expect(r.hasSleep, true);
      expect(r.hrvVsNormal, isNull);
      expect(r.restingHrVsNormal, isNull);
    });

    test('a sleep gap with heart data is NotReady with noSleep', () async {
      readinessWeek();
      fake.sleep = [];
      final c = container();
      final o = (await c.read(healthOverviewProvider.future))!;
      expect(o.sleep, isA<SectionGap<SleepOverview>>());
      final r = (o.readiness as SectionData<ReadinessOverview>).value;
      expect((r.result as ReadinessNotReady).noSleep, true);
      expect(r.hasSleep, false);
      expect(r.hasHrv && r.hasRestingHr, true);
    });

    test('denied sleep with heart data makes readiness Not allowed', () async {
      readinessWeek();
      fake.sleepResult = const SeriesNotAllowed();
      final c = container();
      final o = (await c.read(healthOverviewProvider.future))!;
      expect((o.sleep as SectionGap).gap, MetricGap.notAllowed);
      expect((o.readiness as SectionGap).gap, MetricGap.notAllowed);
    });

    test('a failed sleep read makes readiness a failed gap', () async {
      readinessWeek();
      fake.throwOnSleep = true;
      final c = container();
      final o = (await c.read(healthOverviewProvider.future))!;
      expect((o.readiness as SectionGap).gap, MetricGap.failed);
    });

    test(
      'failed resting HR and HRV reads make readiness a failed gap',
      () async {
        readinessWeek();
        fake.throwOnSeries = {
          HealthSeriesType.restingHeartRate,
          HealthSeriesType.hrv,
        };
        final c = container();
        final o = (await c.read(healthOverviewProvider.future))!;
        expect((o.readiness as SectionGap).gap, MetricGap.failed);
      },
    );

    test('one failed heart input still scores from the other', () async {
      readinessWeek();
      fake.throwOnSeries = {HealthSeriesType.hrv};
      final c = container();
      final o = (await c.read(healthOverviewProvider.future))!;
      expect(o.readiness, isA<SectionData<ReadinessOverview>>());
    });

    test('two gaps with different reasons stay NotReady data', () async {
      fake.seriesResults[HealthSeriesType.restingHeartRate] =
          const SeriesNotAllowed();
      fake.seriesResults[HealthSeriesType.hrv] = const SeriesNotAllowed();
      fake.seriesResults[HealthSeriesType.vo2Max] = const SeriesNotAllowed();
      final c = container();
      final o = (await c.read(healthOverviewProvider.future))!;
      expect((o.sleep as SectionGap).gap, MetricGap.noData);
      expect((o.heart as SectionGap).gap, MetricGap.notAllowed);
      expect(o.readiness, isA<SectionData<ReadinessOverview>>());
    });

    test('adds no reader calls', () async {
      readinessWeek();
      final c = container();
      await c.read(healthOverviewProvider.future);

      expect(fake.sleepCalls, [(DateTime(2026, 10, 24, 18), now)]);
      expect(fake.seriesCalls, hasLength(6));
      expect(fake.seriesCalls.map((c) => c.$1).toSet(), {
        HealthSeriesType.restingHeartRate,
        HealthSeriesType.hrv,
        HealthSeriesType.weight,
        HealthSeriesType.bodyFat,
        HealthSeriesType.vo2Max,
        HealthSeriesType.heartRate,
      });
      expect(fake.totalsCalls, hasLength(2));
    });

    test("account B never sees A's readiness", () async {
      readinessWeek();
      repo.connect(_ownerB, DateTime(2026, 11, 1));
      final c = container();
      final a = (await c.read(healthOverviewProvider.future))!;
      final aReady =
          (a.readiness as SectionData<ReadinessOverview>).value.result;
      expect(aReady, isA<ReadinessReady>());

      // B's device has sleep but no HRV or resting HR.
      fake.series.remove(HealthSeriesType.hrv);
      fake.series.remove(HealthSeriesType.restingHeartRate);
      fake.sleepGate = Completer<void>();
      c.read(_ownerProvider.notifier).set(_ownerB);
      while (fake.sleepCalls.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      final mid = c.read(healthOverviewProvider);
      expect(mid.isLoading, true);
      expect(mid.value, isNull);

      fake.sleepGate!.complete();
      final b = (await c.read(healthOverviewProvider.future))!;
      expect(b.ownerId, _ownerB);
      final r = (b.readiness as SectionData<ReadinessOverview>).value;
      expect(r.result, isA<ReadinessNotReady>());
      expect(identical(r.result, aReady), false);
      expect(r.hasHrv || r.hasRestingHr, false);
      expect(r.hasSleep, true);
    });

    test('HRV today without resting HR today', () async {
      readinessWeek();
      fake.series[HealthSeriesType.restingHeartRate] = [
        for (var i = -20; i < 0; i++)
          _sample(_day(i).add(const Duration(hours: 8)), 58),
      ];
      final c = container();
      final o = (await c.read(healthOverviewProvider.future))!;
      final r = (o.readiness as SectionData<ReadinessOverview>).value;
      expect(r.hasHrv, true);
      expect(r.hasRestingHr, false);
      expect(r.hrvVsNormal, isNotNull);
      expect(r.restingHrVsNormal, isNull);
    });

    test('fewer than 14 baseline days has no baseline', () async {
      syntheticWeek();
      fake.series[HealthSeriesType.hrv] = [
        for (var i = -5; i < 0; i++)
          _sample(_day(i).add(const Duration(hours: 14)), 40),
        _sample(DateTime(2026, 11, 24, 2), 50),
      ];
      final c = container();
      final o = (await c.read(healthOverviewProvider.future))!;
      final r = (o.readiness as SectionData<ReadinessOverview>).value;
      expect(r.hrvBaseline, isNull);
      expect(r.hrvVsNormal, isNull);
      expect(
        (r.result as ReadinessNotReady).daysUntilBaseline,
        5,
        reason: 'the longer history (9 resting HR days) counts',
      );
    });

    test('Android reports RMSSD, not SDNN', () async {
      fake = FakeHealthReader(platform: HealthPlatformKind.healthConnect);
      readinessWeek();
      final c = container();
      final o = (await c.read(healthOverviewProvider.future))!;
      final r = (o.readiness as SectionData<ReadinessOverview>).value;
      expect(r.hrvIsSdnn, false);
    });
  });

  test('refreshIfStale re-reads after an error', () async {
    final flaky = _FlakyRepo(repo)..fail = true;
    final c = ProviderContainer(
      overrides: [
        healthReaderProvider.overrideWithValue(fake),
        healthConnectionRepositoryProvider.overrideWithValue(flaky),
        healthOwnerIdProvider.overrideWith((ref) => ref.watch(_ownerProvider)),
        healthClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    c.listen(healthOverviewProvider, (_, _) {});
    await expectLater(c.read(healthOverviewProvider.future), throwsStateError);
    expect(c.read(healthOverviewProvider).hasError, true);

    flaky.fail = false;
    await c.read(healthOverviewProvider.notifier).refreshIfStale();

    expect((await c.read(healthOverviewProvider.future))!.ownerId, _ownerA);
  });

  test('refreshIfStale does not re-read within 5 minutes', () async {
    final c = container();
    await c.read(healthOverviewProvider.future);
    final notifier = c.read(healthOverviewProvider.notifier);
    expect(fake.sleepCalls, hasLength(1));

    now = now.add(const Duration(minutes: 4));
    await notifier.refreshIfStale();
    expect(fake.sleepCalls, hasLength(1));
    expect(fake.totalsCalls, hasLength(2));

    now = now.add(const Duration(minutes: 2));
    await notifier.refreshIfStale();
    expect(fake.sleepCalls, hasLength(2));
    expect(fake.totalsCalls, hasLength(4));
    expect((await c.read(healthOverviewProvider.future))!.readAt, now);
  });

  test('refreshIfStale re-reads on a new local day within 5 minutes', () async {
    now = DateTime(2026, 11, 24, 23, 58);
    final c = container();
    await c.read(healthOverviewProvider.future);
    final notifier = c.read(healthOverviewProvider.notifier);
    now = DateTime(2026, 11, 25, 0, 1);
    await notifier.refreshIfStale();
    expect(fake.sleepCalls, hasLength(2));
  });

  test(
    'todaysReadiness is absent for an overview read on another day',
    () async {
      readinessWeek();
      final c = container();
      final o = (await c.read(healthOverviewProvider.future))!;
      expect(todaysReadiness(o, DateTime(2026, 11, 24, 23, 59)), isNotNull);
      expect(todaysReadiness(o, DateTime(2026, 11, 25, 0, 1)), isNull);
    },
  );

  test('the resume after Manage re-reads even within 5 minutes', () async {
    final c = container();
    await c.read(healthOverviewProvider.future);
    final notifier = c.read(healthOverviewProvider.notifier);
    expect(fake.sleepCalls, hasLength(1));

    // Not allowed · Manage: the user may revoke access in the settings.
    await c.read(healthSummaryProvider.notifier).manage();
    now = now.add(const Duration(minutes: 1));
    await notifier.refreshIfStale();
    expect(fake.sleepCalls, hasLength(2));
    expect((await c.read(healthOverviewProvider.future))!.readAt, now);

    // Only the one resume is forced.
    now = now.add(const Duration(minutes: 1));
    await notifier.refreshIfStale();
    expect(fake.sleepCalls, hasLength(2));
  });

  test('disconnect clears the overview', () async {
    final c = container();
    expect(await c.read(healthOverviewProvider.future), isNotNull);

    await c.read(healthSummaryProvider.notifier).disconnect();

    expect(await c.read(healthOverviewProvider.future), isNull);
  });

  test('requestMoreAccess asks the reader and re-reads', () async {
    final c = container();
    await c.read(healthOverviewProvider.future);

    await c.read(healthOverviewProvider.notifier).requestMoreAccess();

    expect(fake.requestMoreAccessCalls, 1);
    expect(fake.sleepCalls, hasLength(2));
  });

  group('workouts from other apps', () {
    test('reads outside workouts for the last 90 days', () async {
      syntheticWeek();
      fake.workouts = SeriesData([_outside('o1', 2)]);
      final c = container();
      final o = (await c.read(healthOverviewProvider.future))!;
      expect(fake.workoutCalls.single, (DateTime(2026, 11, 24 - 89), now));
      final w = (o.workouts as SectionData<WorkoutsOverview>).value;
      expect(w.outside.single.id, 'o1');
    });

    test('not allowed maps to MetricGap.notAllowed', () async {
      syntheticWeek();
      fake.workouts = const SeriesNotAllowed();
      final o = (await container().read(healthOverviewProvider.future))!;
      expect((o.workouts as SectionGap).gap, MetricGap.notAllowed);
    });

    test('needs access and failures map like the other sections', () async {
      syntheticWeek();
      fake.workouts = const SeriesNeedsAccess();
      var o = (await container().read(healthOverviewProvider.future))!;
      expect((o.workouts as SectionGap).gap, MetricGap.needsAccess);
      fake.workouts = const SeriesFailed();
      o = (await container().read(healthOverviewProvider.future))!;
      expect((o.workouts as SectionGap).gap, MetricGap.failed);
    });

    ReadinessReady ready(HealthOverview o) =>
        ((o.readiness as SectionData<ReadinessOverview>).value.result)
            as ReadinessReady;

    bool hasLoad(HealthOverview o) =>
        ready(o).readiness.parts
            .any((p) => p.input == ReadinessInput.trainingLoad);

    test('readiness includes a training load part when 14+ days of sessions '
        'exist', () async {
      readinessWeek();
      history = _FakeHistory([_logged('a', 20), _logged('b', 3)]);
      final o = (await container().read(healthOverviewProvider.future))!;
      expect(hasLoad(o), isTrue);
      expect(ready(o).readiness.loadRatio, isNotNull);
    });

    test('outside workouts alone can supply the load history', () async {
      readinessWeek();
      history = _FakeHistory(const []);
      fake.workouts = SeriesData([_outside('a', 20), _outside('b', 3)]);
      final o = (await container().read(healthOverviewProvider.future))!;
      expect(hasLoad(o), isTrue);
    });

    test('readiness has no training load part when workouts are not allowed '
        'and BeyondRep history is short', () async {
      readinessWeek();
      history = _FakeHistory([_logged('b', 3)]);
      fake.workouts = const SeriesNotAllowed();
      final o = (await container().read(healthOverviewProvider.future))!;
      expect(hasLoad(o), isFalse);
      expect(ready(o).readiness.loadRatio, isNull);
    });

    test('a workout whose uuid is a stored receipt is not an outside workout '
        'and adds no load', () async {
      readinessWeek();
      history = _FakeHistory(const []);
      fake.workouts = SeriesData([_outside('a', 20), _outside('B-UPPER', 3)]);
      final withLoad = (await container().read(healthOverviewProvider.future))!;
      ownWorkoutIds = {'b-upper'};
      final o = (await container().read(healthOverviewProvider.future))!;
      final outside =
          (o.workouts as SectionData<WorkoutsOverview>).value.outside;
      expect(outside.map((w) => w.id), ['a']);
      // The hidden workout no longer counts toward training load.
      expect(
        ready(o).readiness.loadRatio,
        isNot(ready(withLoad).readiness.loadRatio),
      );
    });

    test('a receipt stored after the read hides the workout without a '
        'refresh', () async {
      readinessWeek();
      history = _FakeHistory(const []);
      fake.workouts = SeriesData([_outside('a', 20), _outside('B-UPPER', 3)]);
      final c = container();
      final before = (await c.read(healthOverviewProvider.future))!;
      expect(
        (before.workouts as SectionData<WorkoutsOverview>).value.outside,
        hasLength(2),
      );
      c.read(_ownIdsProvider.notifier).set({'b-upper'});
      final after = (await c.read(healthOverviewProvider.future))!;
      expect(
        (after.workouts as SectionData<WorkoutsOverview>).value.outside.map(
          (w) => w.id,
        ),
        ['a'],
      );
    });

    test(
      'without a receipt the same workouts are outside and add load',
      () async {
        readinessWeek();
        history = _FakeHistory(const []);
        fake.workouts = SeriesData([_outside('a', 20), _outside('B-UPPER', 3)]);
        final o = (await container().read(healthOverviewProvider.future))!;
        expect(
          (o.workouts as SectionData<WorkoutsOverview>).value.outside,
          hasLength(2),
        );
        expect(hasLoad(o), isTrue);
      },
    );

    test('a history read failure leaves readiness without load but still '
        'scored', () async {
      readinessWeek();
      history = _FakeHistory(const [], fail: true);
      fake.workouts = SeriesData([_outside('a', 20), _outside('b', 3)]);
      final o = (await container().read(healthOverviewProvider.future))!;
      expect(hasLoad(o), isFalse);
      expect(ready(o).readiness.value, inInclusiveRange(0, 100));
    });

    test('an account switch during the read never exposes the other '
        "owner's workouts", () async {
      syntheticWeek();
      repo.connect(_ownerB, DateTime(2026, 11, 1));
      fake.workouts = SeriesData([_outside('of-a', 2)]);
      fake.workoutsGate = Completer<void>();
      final c = container();
      final pending = c.read(healthOverviewProvider.future);
      while (fake.workoutCalls.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      fake.workouts = const SeriesData([]);
      c.read(_ownerProvider.notifier).set(_ownerB);
      fake.workoutsGate!.complete();
      await pending.catchError((_) => null);

      final b = (await c.read(healthOverviewProvider.future))!;
      expect(b.ownerId, _ownerB);
      expect(
        (b.workouts as SectionData<WorkoutsOverview>).value.outside,
        isEmpty,
      );
    });

    test('workoutMergeProvider merges using overview outside workouts and '
        'completed history', () async {
      syntheticWeek();
      history = _FakeHistory([_logged('s', 2)]);
      // 09:10-09:40 sits inside the 09:00-10:00 session two days ago.
      fake.workouts = SeriesData([
        OutsideWorkout(
          id: 'merged',
          kind: OutsideWorkoutKind.strength,
          start: DateTime(2026, 11, 22, 9, 10).toUtc(),
          end: DateTime(2026, 11, 22, 9, 40).toUtc(),
          source: 'Synthetic app',
        ),
        _outside('alone', 5),
      ]);
      final c = container();
      c.listen(completedWorkoutHistoryProvider, (_, _) {});
      await c.read(healthOverviewProvider.future);
      await c.read(completedWorkoutHistoryProvider.future);
      c.listen(workoutMergeProvider, (_, _) {});
      final merge = c.read(workoutMergeProvider)!;
      expect(merge.mergedIntoSession['s']!.single.id, 'merged');
      expect(merge.standalone.single.id, 'alone');
    });
  });
}
