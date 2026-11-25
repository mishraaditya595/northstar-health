import 'dart:async';

import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/application/training_insights.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:beyondrep/features/health/domain/sleep_nights.dart';
import 'package:beyondrep/features/progress/data/objectbox_workout_history_repository.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/progress/workout_history_state.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_overview.dart';
import '../support/health_overview_fixtures.dart';

const _owner = 'owner-a';
final _readAt = DateTime(2026, 3, 31, 9);

DateTime _d(int day, [int month = 3]) => DateTime(2026, month, day);

SleepNight _night(DateTime date, int minutes) => SleepNight(
  date: date,
  start: date.subtract(const Duration(hours: 8)),
  end: date,
  source: 'test',
  segments: const [],
  asleep: Duration(minutes: minutes),
  deep: Duration.zero,
  light: Duration(minutes: minutes),
  rem: Duration.zero,
  awake: Duration.zero,
  inBed: null,
);

WorkoutSessionRecord _session(
  String id,
  DateTime localDay, {
  WorkoutStatus status = WorkoutStatus.completed,
  int working = 10,
  int warmups = 0,
  int skipped = 0,
}) {
  var n = 0;
  WorkoutSetRecord set(WorkoutSetKind k, WorkoutSetStatus s) =>
      WorkoutSetRecord(
        uuid: '$id-${n++}',
        exerciseUuid: 'e',
        position: n,
        kind: k,
        status: s,
      );
  final at = DateTime(localDay.year, localDay.month, localDay.day, 12);
  return WorkoutSessionRecord(
    uuid: id,
    name: 'w',
    status: status,
    startedAtUtc: at.toUtc(),
    originalOffsetMinutes: 0,
    revision: 1,
    completedAtUtc: at.toUtc(),
    sets: [
      for (var i = 0; i < working; i++)
        set(WorkoutSetKind.working, WorkoutSetStatus.completed),
      for (var i = 0; i < warmups; i++)
        set(WorkoutSetKind.warmup, WorkoutSetStatus.completed),
      for (var i = 0; i < skipped; i++)
        set(WorkoutSetKind.working, WorkoutSetStatus.skipped),
    ],
  );
}

class _FakeHistory implements WorkoutHistoryRepository {
  _FakeHistory(this.sessions, {this.fail = false, this.gate});
  final List<WorkoutSessionRecord> sessions;
  final bool fail;
  final Completer<void>? gate;
  int reads = 0;

  @override
  WorkoutHistorySnapshot readCompleted() {
    reads++;
    return WorkoutHistorySnapshot(sessions: sessions);
  }

  @override
  Future<WorkoutHistorySnapshot> readCompletedAsync() async {
    reads++;
    await gate?.future;
    if (fail) throw StateError('boom');
    return WorkoutHistorySnapshot(sessions: sessions);
  }
}

// Training on March 1, 3, 5, 7; nights after are 40 min longer.
final _training = [
  for (final x in [1, 3, 5, 7]) _session('s$x', _d(x)),
];

HealthOverview _overview({
  String owner = _owner,
  bool sleepGap = false,
  bool heartGap = false,
  List<DayValue>? rhr,
}) {
  final nights = [
    for (final x in [2, 4, 6, 8]) _night(_d(x), 460),
    for (final x in [10, 11, 12, 13, 14]) _night(_d(x), 420),
  ];
  return HealthOverview(
    ownerId: owner,
    readAt: _readAt,
    platform: HealthPlatformKind.healthConnect,
    readableFrom: null,
    needsMoreAccess: false,
    sleep: sleepGap
        ? const SectionGap(MetricGap.noData)
        : SectionData(sleepOverview(nights.last).withNights(nights)),
    heart: heartGap
        ? const SectionGap(MetricGap.noData)
        : SectionData(
            _heart(
              rhr ??
                  [
                    for (final x in [2, 4, 6, 8]) (day: _d(x), value: 58.0),
                    for (final x in [10, 11, 12, 13]) (day: _d(x), value: 55.0),
                  ],
            ),
          ),
    activity: const SectionGap(MetricGap.noData),
    body: const SectionGap(MetricGap.noData),
    readiness: const SectionGap(MetricGap.noData),
  );
}

HeartOverview _heart(List<DayValue> daily) => HeartOverview(
  restingHr: null,
  restingHrDaily: daily,
  hrv: null,
  hrvDaily: const [],
  vo2Max: null,
  vo2MaxDaily: const [],
  restingHrVsMonth: null,
  hrvVsNormal: null,
  hrvIsSdnn: false,
);

extension on SleepOverview {
  SleepOverview withNights(List<SleepNight> nights) => SleepOverview(
    lastNight: lastNight,
    score: score,
    sleepAvgHr: sleepAvgHr,
    nights: nights,
    vsWeek: vsWeek,
  );
}

ProviderContainer _container(
  HealthOverview? overview,
  _FakeHistory history, {
  String? owner = _owner,
}) {
  final c = ProviderContainer(
    overrides: [
      fakeHealthOverview(FakeHealthOverviewController(overview)),
      healthOwnerIdProvider.overrideWithValue(owner),
      workoutHistoryRepositoryProvider.overrideWithValue(history),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<TrainingInsights?> _read(ProviderContainer c) async {
  final sub = c.listen(trainingInsightsProvider, (_, _) {});
  await c.read(healthOverviewProvider.future);
  try {
    await c.read(completedWorkoutHistoryProvider.future);
  } catch (_) {}
  final v = sub.read();
  sub.close();
  return v;
}

void main() {
  test('both insights computed from overview and history', () async {
    final h = _FakeHistory(_training);
    final r = (await _read(_container(_overview(), h)))!;
    expect(r.sleep!.difference, const Duration(minutes: 40));
    expect(r.sleep!.trainingNights, 4);
    expect(r.restingHr, isNotNull);
    expect(r.restingHr!.difference, closeTo(3, 1e-9));
    expect(h.reads, 1);
  });

  test('overview for another owner is null', () async {
    final c = _container(_overview(owner: 'owner-b'), _FakeHistory(_training));
    expect(await _read(c), isNull);
  });

  test('no current owner is null', () async {
    final c = _container(_overview(), _FakeHistory(_training), owner: null);
    expect(await _read(c), isNull);
  });

  test('null overview is null', () async {
    expect(await _read(_container(null, _FakeHistory(_training))), isNull);
  });

  test('history loading is null', () async {
    final gate = Completer<void>();
    final c = _container(_overview(), _FakeHistory(_training, gate: gate));
    final sub = c.listen(trainingInsightsProvider, (_, _) {});
    await c.read(healthOverviewProvider.future);
    expect(sub.read(), isNull);
    gate.complete();
    await c.read(completedWorkoutHistoryProvider.future);
    expect(sub.read(), isNotNull);
    sub.close();
  });

  test('history error is null', () async {
    final c = _container(_overview(), _FakeHistory(_training, fail: true));
    expect(await _read(c), isNull);
  });

  test('sleep gap leaves only the resting heart rate insight', () async {
    final r = (await _read(
      _container(_overview(sleepGap: true), _FakeHistory(_training)),
    ))!;
    expect(r.sleep, isNull);
    expect(r.restingHr, isNotNull);
  });

  test('heart gap leaves only the sleep insight', () async {
    final r = (await _read(
      _container(_overview(heartGap: true), _FakeHistory(_training)),
    ))!;
    expect(r.restingHr, isNull);
    expect(r.sleep, isNotNull);
  });

  test('sessions outside the 30 day window are ignored', () async {
    // March 31 minus 30 is March 1: Feb 28 is out, March 1 is in.
    final h = _FakeHistory([
      _session('old', _d(28, 2)),
      _session('edge', _d(1)),
      _session('future', DateTime(2026, 4, 1)),
    ]);
    final r = (await _read(_container(_overview(), h)))!;
    expect(r.sleep, isNull); // one training day only
    final inWindow = _FakeHistory([
      for (final x in [2, 4, 6]) _session('s$x', _d(x)),
      _session('old', _d(28, 2)),
    ]);
    final n = [
      for (final x in [3, 5, 7]) _night(_d(x), 480),
      for (final x in [10, 11, 12]) _night(_d(x), 400),
    ];
    final o = HealthOverview(
      ownerId: _owner,
      readAt: _readAt,
      platform: HealthPlatformKind.healthConnect,
      readableFrom: null,
      needsMoreAccess: false,
      sleep: SectionData(sleepOverview(n.last).withNights(n)),
      heart: const SectionGap(MetricGap.noData),
      activity: const SectionGap(MetricGap.noData),
      body: const SectionGap(MetricGap.noData),
      readiness: const SectionGap(MetricGap.noData),
    );
    final r2 = (await _read(_container(o, inWindow)))!;
    expect(r2.sleep!.trainingNights, 3);
  });

  test('unfinished and discarded sessions are ignored', () async {
    final h = _FakeHistory([
      _session('a', _d(1), status: WorkoutStatus.inProgress),
      _session('b', _d(3), status: WorkoutStatus.discarded),
      _session('c', _d(5), status: WorkoutStatus.paused),
      _session('d', _d(7)),
    ]);
    final r = (await _read(_container(_overview(), h)))!;
    expect(r.sleep, isNull);
    expect(r.restingHr, isNull);
  });

  test('warm-up and skipped sets do not make a training day', () async {
    final h = _FakeHistory([
      for (final x in [1, 3, 5, 7])
        _session('s$x', _d(x), working: 0, warmups: 3, skipped: 2),
    ]);
    final r = (await _read(_container(_overview(), h)))!;
    expect(r.sleep, isNull);
  });

  test('sets from sessions on the same day are summed', () async {
    // Two 3-set sessions on day 1 are hard (6) against 5-set days.
    final h = _FakeHistory([
      _session('a', _d(1), working: 3),
      _session('b', _d(1), working: 3),
      for (final x in [2, 3, 4, 5, 6]) _session('s$x', _d(x), working: 5),
    ]);
    final o = _overview(
      rhr: [
        (day: _d(2), value: 70.0),
        (day: _d(3), value: 70.0),
        (day: _d(4), value: 70.0),
        for (final x in [10, 11, 12]) (day: _d(x), value: 60.0),
      ],
    );
    final r = (await _read(_container(o, h)))!;
    // 6 days, k=2, threshold 5 -> day 1 (6) and ties at 5: all days hard.
    expect(r.restingHr, isNotNull);
  });
}
