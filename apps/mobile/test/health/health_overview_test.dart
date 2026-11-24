import 'dart:async';
import 'dart:io';

import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_connection_repository.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/domain/health_types.dart';
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

SleepSegment _seg(DateTime from, DateTime to, SleepStage stage) =>
    (from: from, to: to, stage: stage, source: 'Synthetic watch');

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
  late DateTime now;

  setUp(() {
    root = Directory.systemTemp.createTempSync('beyondrep-health-overview-');
    store = Store(getObjectBoxModel(), directory: '${root.path}/db');
    repo = ObjectBoxHealthConnectionRepository(store);
    fake = FakeHealthReader();
    now = DateTime(2026, 11, 24, 7, 42);
    repo.connect(_ownerA, DateTime(2026, 11, 1));
  });
  tearDown(() {
    store.close();
    root.deleteSync(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        healthReaderProvider.overrideWithValue(fake),
        healthConnectionRepositoryProvider.overrideWithValue(repo),
        healthOwnerIdProvider.overrideWith((ref) => ref.watch(_ownerProvider)),
        healthClockProvider.overrideWithValue(() => now),
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
      expect(activity.stepsDaily, hasLength(8));
      expect(activity.stepsWeekAverage, 6600);
      expect(activity.activeEnergyToday, isNull);

      final body = (overview.body as SectionData<BodyOverview>).value;
      expect(body.weight!.value, 79);
      expect(body.weightVsMonth!.delta, -1);
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
}
