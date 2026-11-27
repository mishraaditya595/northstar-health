import 'dart:convert';

import 'package:beyondrep/core/units/load_units.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/domain/energy.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/health/domain/sleep_nights.dart';
import 'package:beyondrep/features/health/domain/sleep_score.dart';
import 'package:beyondrep/features/health/widgets/readiness_card.dart';
import 'package:beyondrep/features/programs/application/program_providers.dart';
import 'package:beyondrep/features/programs/domain/program_models.dart';
import 'package:beyondrep/features/programs/domain/program_status.dart';
import 'package:beyondrep/features/watch/application/watch_snapshots.dart';
import 'package:beyondrep/features/watch/domain/watch_account_key.dart';
import 'package:beyondrep/features/watch/domain/watch_message.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/health_overview_fixtures.dart';

final _key = watchAccountKey('synthetic-user');
final _now = DateTime.utc(2026, 11, 24, 2, 30);
const _id = '77777777-3333-4333-8333-000000000099';

WatchMessage _roundTrip(WatchMessage m) => WatchMessage.fromJson(
  jsonDecode(jsonEncode(m.toJson())) as Map<String, Object?>,
);

Section<ReadinessOverview> _ready(int value) => SectionData(
  ReadinessOverview(
    result: ReadinessReady(
      Readiness(
        value: value,
        band: readinessBandOf(value),
        parts: const [
          ReadinessPart(input: ReadinessInput.hrv, score: 70, weight: 0.4),
          ReadinessPart(input: ReadinessInput.sleep, score: 70, weight: 0.6),
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
    hrvIsSdnn: true,
  ),
);

ExerciseRecord _exercise(int i, {String mode = 'reps'}) => ExerciseRecord(
  uuid: 'ex-$i',
  name: 'Synthetic move $i',
  muscleGroup: 'chest',
  equipment: 'barbell',
  movementCategory: 'push',
  inputMode: mode,
  isBuiltIn: false,
  updatedAtMs: 0,
);

WorkoutPlanRecord _plan(
  String uuid,
  String name, {
  int exercises = 2,
  int sets = 3,
}) => WorkoutPlanRecord(
  uuid: uuid,
  name: name,
  description: '',
  updatedAtMs: 0,
  exercises: [
    for (var i = 0; i < exercises; i++)
      PlanExerciseRecord(
        uuid: '$uuid-pe-$i',
        exerciseUuid: 'ex-${i % 40}',
        position: i,
        targetSets: sets,
        targetRepsMin: 8,
        targetRepsMax: 12,
        restSeconds: 90,
      ),
  ],
);

WorkoutLibrarySnapshot _library(List<WorkoutPlanRecord> plans) =>
    WorkoutLibrarySnapshot(
      exercises: [for (var i = 0; i < 40; i++) _exercise(i)],
      plans: plans,
    );

ProgramWeek _week(WorkoutPlanRecord todayPlan) {
  final day = ProgramDayRecord(
    uuid: 'day-1',
    dayIndex: 0,
    planUuid: todayPlan.uuid,
  );
  return ProgramWeek(
    program: TrainingProgramRecord(
      uuid: 'program-1',
      name: 'Synthetic program',
      description: '',
      sourceId: 'src',
      sourceRelease: 1,
      firstDayWeekday: 1,
      isActive: true,
      updatedAtMs: 0,
      days: [day],
    ),
    localToday: DateTime(2026, 11, 24, 8),
    rows: [
      (
        date: DateTime(2026, 11, 24),
        dayIndex: 0,
        day: day,
        status: ProgramDayStatus.today,
      ),
    ],
    plans: {todayPlan.uuid: todayPlan},
    latestMissed: null,
    nextTraining: null,
  );
}

WorkoutSessionRecord _session(
  String uuid, {
  required String? planUuid,
  required DateTime completedAt,
  List<String> exerciseUuids = const ['ex-1'],
}) => WorkoutSessionRecord(
  uuid: uuid,
  name: 'Session $uuid',
  status: WorkoutStatus.completed,
  startedAtUtc: completedAt.subtract(const Duration(hours: 1)),
  originalOffsetMinutes: 0,
  revision: 1,
  planUuid: planUuid,
  completedAtUtc: completedAt,
  exercises: [
    for (final (i, e) in exerciseUuids.indexed)
      WorkoutExerciseRecord(
        uuid: '$uuid-we-$i',
        sessionUuid: uuid,
        definitionUuid: e,
        nameSnapshot: 'Synthetic move ${e.substring(3)}',
        position: i,
      ),
  ],
  sets: [
    for (var i = 0; i < exerciseUuids.length; i++)
      WorkoutSetRecord(
        uuid: '$uuid-s-$i',
        exerciseUuid: '$uuid-we-$i',
        position: 0,
        kind: WorkoutSetKind.working,
        status: WorkoutSetStatus.completed,
        reps: 8,
        loadGrams: 50000,
        completedAtUtc: completedAt,
      ),
  ],
);

void main() {
  group('account messages', () {
    test('send times are cut to milliseconds', () {
      final micros = DateTime.utc(2026, 11, 24, 2, 30, 1, 123, 456);
      final binding = buildAccountBinding(
        accountKey: _key,
        unit: 'kg',
        messageId: _id,
        nowUtc: micros,
      );
      expect(binding.sentAtUtc, '2026-11-24T02:30:01.123Z');
      final cleared = buildAccountCleared(
        accountKey: _key,
        wipeUnsent: false,
        messageId: _id,
        nowUtc: micros,
      );
      expect(cleared.sentAtUtc, '2026-11-24T02:30:01.123Z');
      final plans = buildPlansSnapshot(
        accountKey: _key,
        library: _library([_plan('p', 'P')]),
        week: null,
        recentSessions: const [],
        nowUtc: micros,
        messageId: _id,
      );
      expect(plans.sentAtUtc, '2026-11-24T02:30:01.123Z');
      expect(plans.generatedAtUtc, '2026-11-24T02:30:01.123Z');
    });

    test('binding round-trips through the codec', () {
      final m = buildAccountBinding(
        accountKey: _key,
        unit: 'lb',
        messageId: _id,
        nowUtc: _now,
      );
      final back = _roundTrip(m) as AccountBinding;
      expect(back.unit, 'lb');
      expect(back.accountKey, _key);
      expect(back.messageId, _id);
    });

    test('cleared round-trips with its wipe flag', () {
      final m = buildAccountCleared(
        accountKey: _key,
        wipeUnsent: true,
        messageId: _id,
        nowUtc: _now,
      );
      expect((_roundTrip(m) as AccountCleared).wipeUnsent, isTrue);
    });
  });

  group('health snapshot', () {
    test('omits missing values instead of zero', () {
      final o = overview(
        sleep: const SectionGap(MetricGap.noData),
        heart: const SectionGap(MetricGap.noData),
        activity: SectionData(
          ActivityOverview(
            stepsToday: null,
            stepsDaily: const [],
            activeEnergyToday: null,
            activeEnergyDaily: const [],
            stepsWeekAverage: null,
          ),
        ),
      );
      final m = buildHealthSnapshot(
        accountKey: _key,
        overview: o,
        localNow: DateTime(2026, 11, 24, 8),
        messageId: _id,
      )!;
      final body = m.bodyJson;
      expect(body.containsKey('steps'), isFalse);
      expect(body.containsKey('sleep'), isFalse);
      expect(body.containsKey('resting_hr_bpm'), isFalse);
      expect(body.containsKey('hrv_ms'), isFalse);
      expect(body.containsKey('readiness'), isFalse);
      expect(body['local_date'], '2026-11-24');
      _roundTrip(m);
    });

    test('carries today values with their units rounded to whole numbers', () {
      final m = buildHealthSnapshot(
        accountKey: _key,
        overview: overview(readiness: _ready(77)),
        localNow: DateTime(2026, 11, 24, 8),
        messageId: _id,
      )!;
      expect(m.steps, 8214);
      expect(m.restingHrBpm, 54);
      expect(m.hrvMs, 52);
      expect(m.hrvKind, 'sdnn');
      expect(m.sleep, {
        'score': 74,
        'asleep_minutes': 372,
        'deep_minutes': 63,
        'rem_minutes': 93,
        'core_minutes': 216,
        'awake_minutes': 22,
      });
      expect(m.activeEnergyKcal, 412);
      expect(m.asOfUtc, overviewReadAt.toUtc().toIso8601String());
      _roundTrip(m);
    });

    test('no health snapshot when readAt is yesterday', () {
      final m = buildHealthSnapshot(
        accountKey: _key,
        overview: overview(),
        localNow: DateTime(2026, 11, 25, 0, 5),
        messageId: _id,
      );
      expect(m, isNull);
    });

    test('no health snapshot without an overview', () {
      expect(
        buildHealthSnapshot(
          accountKey: _key,
          overview: null,
          localNow: DateTime(2026, 11, 24, 8),
          messageId: _id,
        ),
        isNull,
      );
    });

    test('readiness carries energy now with the start factors', () {
      final start = _ready(78);
      final startValue = (start as SectionData<ReadinessOverview>).value;
      final readiness = (startValue.result as ReadinessReady).readiness;
      final energy = Energy(
        value: 62,
        band: readinessBandOf(62),
        start: 78,
        items: const [],
      );
      final o = overview(
        readiness: start,
        energy: energySection(
          start,
          energy: energy,
          learning: const EnergyLearning(workoutsNeeded: 3),
          wake: DateTime(2026, 11, 24, 6, 31),
        ),
      );
      final m = buildHealthSnapshot(
        accountKey: _key,
        overview: o,
        localNow: DateTime(2026, 11, 24, 8),
        messageId: _id,
      )!;
      expect(m.readiness, {
        'score': 62,
        'band': 'fair',
        'headline': 'Train as planned, watch effort',
        'reason': 'Started at 78 · down 16 since morning · still learning',
        'factors': [
          for (final f in readinessFactors(o, startValue, readiness))
            {'input': f.input, 'status': f.status, 'tone': f.tone},
        ],
      });
      _roundTrip(m);
    });

    test('a ready start without a waking day sends no readiness', () {
      final start = _ready(78);
      final o = overview(
        readiness: start,
        energy: SectionData(
          EnergyOverview(
            day: DateTime(2026, 11, 24),
            wake: null,
            start: (start as SectionData<ReadinessOverview>).value,
            energy: null,
            learning: const EnergyLearning(),
          ),
        ),
      );
      final m = buildHealthSnapshot(
        accountKey: _key,
        overview: o,
        localNow: DateTime(2026, 11, 24, 8),
        messageId: _id,
      )!;
      expect(m.readiness, isNull);
    });

    test('after local midnight the previous waking day sends no readiness', () {
      final start = _ready(78);
      final o = overview(
        readiness: start,
        readAt: DateTime(2026, 11, 25, 0, 28),
        energy: energySection(
          start,
          wake: DateTime(2026, 11, 24, 7),
          day: DateTime(2026, 11, 24),
        ),
      );
      final m = buildHealthSnapshot(
        accountKey: _key,
        overview: o,
        localNow: DateTime(2026, 11, 25, 0, 30),
        messageId: _id,
      )!;
      expect(m.readiness, isNull);
    });

    test('the reason stays within 140 characters', () {
      final start = _ready(100);
      final o = overview(
        readiness: start,
        energy: energySection(
          start,
          energy: Energy(
            value: 0,
            band: readinessBandOf(0),
            start: 100,
            items: const [],
          ),
          learning: const EnergyLearning(workoutsNeeded: 12, daysNeeded: 9),
          wake: DateTime(2026, 11, 24, 6, 31),
        ),
      );
      final m = buildHealthSnapshot(
        accountKey: _key,
        overview: o,
        localNow: DateTime(2026, 11, 24, 8),
        messageId: _id,
      )!;
      expect(
        (m.readiness!['reason']! as String).length,
        lessThanOrEqualTo(140),
      );
    });

    test('not-ready readiness is omitted', () {
      final o = overview(
        readiness: const SectionData(
          ReadinessOverview(
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
        ),
      );
      final m = buildHealthSnapshot(
        accountKey: _key,
        overview: o,
        localNow: DateTime(2026, 11, 24, 8),
        messageId: _id,
      )!;
      expect(m.readiness, isNull);
    });

    test('a night that ended on an earlier day is not sent as sleep', () {
      final o = overview(
        sleep: SectionData(sleepOverview(night(date: DateTime(2026, 11, 23)))),
      );
      final m = buildHealthSnapshot(
        accountKey: _key,
        overview: o,
        localNow: DateTime(2026, 11, 24, 8),
        messageId: _id,
      )!;
      expect(m.sleep, isNull);
    });
  });

  group('health snapshot extras', () {
    final localNow = DateTime(2026, 11, 24, 8);

    HealthSnapshot build(HealthOverview o) => buildHealthSnapshot(
      accountKey: _key,
      overview: o,
      localNow: localNow,
      messageId: _id,
    )!;

    SleepOverview nightsOf(List<SleepNight> nights, {bool staged = true}) =>
        SleepOverview(
          lastNight: nights.last,
          score: staged ? const SleepScore(value: 74, contributors: {}) : null,
          sleepAvgHr: null,
          nights: nights,
          vsWeek: null,
        );

    test('week holds the 7 days ending today, oldest first', () {
      final m = build(overview(readiness: _ready(77)));
      final week = m.week!;
      expect(
        [for (final d in week) d['local_date']],
        [
          '2026-11-18',
          '2026-11-19',
          '2026-11-20',
          '2026-11-21',
          '2026-11-22',
          '2026-11-23',
          '2026-11-24',
        ],
      );
      // Resting HR and HRV come from the daily series, rounded.
      expect(week.last['resting_hr_bpm'], 54);
      expect(week.last['hrv_ms'], 52);
      expect(week.first['resting_hr_bpm'], 55);
      _roundTrip(m);
    });

    test(
      'a day with no values is left out and a missing metric key is absent',
      () {
        final o = overview(
          sleep: SectionData(
            nightsOf([
              night(date: DateTime(2026, 11, 22), asleep: 400),
              night(),
            ]),
          ),
          heart: SectionData(
            HeartOverview(
              restingHr: null,
              restingHrDaily: [(day: DateTime(2026, 11, 20), value: 58.4)],
              hrv: null,
              hrvDaily: const [],
              vo2Max: null,
              vo2MaxDaily: const [],
              restingHrVsMonth: null,
              hrvVsNormal: null,
              hrvIsSdnn: true,
            ),
          ),
          activity: SectionData(
            ActivityOverview(
              stepsToday: null,
              stepsDaily: const [],
              activeEnergyToday: null,
              activeEnergyDaily: const [],
              stepsWeekAverage: null,
            ),
          ),
        );
        final week = build(o).week!;
        expect(
          [for (final d in week) d['local_date']],
          ['2026-11-20', '2026-11-22', '2026-11-24'],
        );
        expect(week[0], {'local_date': '2026-11-20', 'resting_hr_bpm': 58});
        expect(week[1], {'local_date': '2026-11-22', 'asleep_minutes': 400});
        expect(week[2].containsKey('steps'), isFalse);
        expect(week[2].containsKey('hrv_ms'), isFalse);
        expect(week[2]['asleep_minutes'], 372);
        expect(week[2]['sleep_score'], 74);
      },
    );

    test('no week at all when no day has a value', () {
      final o = overview(
        sleep: const SectionGap(MetricGap.noData),
        heart: const SectionGap(MetricGap.noData),
        activity: const SectionGap(MetricGap.noData),
      );
      expect(build(o).week, isNull);
      expect(build(o).bodyJson.containsKey('week'), isFalse);
    });

    test("today's steps in week come from stepsToday", () {
      final week = build(overview()).week!;
      // The daily series holds 10200 for today; the live count wins.
      expect(week.last['steps'], 8214);
      expect(week[5]['steps'], isNot(8214));
    });

    test('core and awake minutes only when the night has stages', () {
      final staged = build(overview()).sleep!;
      expect(staged['core_minutes'], 216);
      expect(staged['awake_minutes'], 22);
      final plain = build(
        overview(
          sleep: SectionData(
            sleepOverview(night(deep: 0, rem: 0), staged: false),
          ),
        ),
      ).sleep!;
      expect(plain.containsKey('core_minutes'), isFalse);
      expect(plain.containsKey('awake_minutes'), isFalse);
      expect(plain.containsKey('deep_minutes'), isFalse);
    });

    test('usual values only when a baseline exists', () {
      final without = build(overview(readiness: _ready(77)));
      expect(without.restingHrUsualBpm, isNull);
      expect(without.hrvUsualMs, isNull);
      expect(without.bodyJson.containsKey('hrv_usual_ms'), isFalse);

      final value = (_ready(77) as SectionData<ReadinessOverview>).value;
      final withBaseline = build(
        overview(
          readiness: SectionData(
            ReadinessOverview(
              result: value.result,
              hasHrv: true,
              hasRestingHr: true,
              hasSleep: true,
              hrvVsNormal: null,
              restingHrVsNormal: null,
              hrvBaseline: const Baseline(mean: 58.6, sd: 4, days: 20),
              restingHrBaseline: const Baseline(mean: 56.4, sd: 1.5, days: 20),
              hrvIsSdnn: true,
            ),
          ),
        ),
      );
      expect(withBaseline.restingHrUsualBpm, 56);
      expect(withBaseline.hrvUsualMs, 59);
      _roundTrip(withBaseline);
    });

    test('factors copied into readiness', () {
      final m = build(overview(readiness: _ready(77)));
      final factors = m.readiness!['factors']! as List;
      expect([for (final f in factors) (f as Map)['input']], ['sleep', 'hrv']);
    });

    test('full week snapshot stays under watchSnapshotMaxBytes', () {
      final m = build(overview(readiness: _ready(77)));
      expect(
        utf8.encode(jsonEncode(m.toJson())).length,
        lessThan(watchSnapshotMaxBytes ~/ 4),
      );
    });

    test('round-trips through WatchMessage.fromJson', () {
      final m = build(overview(readiness: _ready(77)));
      final back = _roundTrip(m) as HealthSnapshot;
      expect(back.week, m.week);
      expect(back.toJson(), m.toJson());
    });
  });

  group('plans snapshot', () {
    test(
      "puts today's program plan first, then most recent use, then name",
      () {
        final a = _plan('plan-a', 'Alpha');
        final b = _plan('plan-b', 'Bravo');
        final c = _plan('plan-c', 'Charlie');
        final today = _plan('plan-today', 'Zulu program day');
        final m = buildPlansSnapshot(
          accountKey: _key,
          library: _library([a, b, c]),
          week: _week(today),
          recentSessions: [
            _session(
              's1',
              planUuid: 'plan-c',
              completedAt: DateTime.utc(2026, 11, 20),
            ),
            _session(
              's2',
              planUuid: 'plan-b',
              completedAt: DateTime.utc(2026, 11, 22),
            ),
          ],
          nowUtc: _now,
          messageId: _id,
        );
        final names = [for (final p in m.plans) (p! as Map)['name']];
        expect(names, ['Zulu program day', 'Bravo', 'Charlie', 'Alpha']);
        expect(m.today, {
          'plan_id': 'plan-today',
          'program_id': 'program-1',
          'local_date': '2026-11-24',
          'label': 'Zulu program day',
        });
        _roundTrip(m);
      },
    );

    test('no today without a program workout today', () {
      final m = buildPlansSnapshot(
        accountKey: _key,
        library: _library([_plan('plan-a', 'Alpha')]),
        week: null,
        recentSessions: const [],
        nowUtc: _now,
        messageId: _id,
      );
      expect(m.today, isNull);
      expect(m.plans, hasLength(1));
    });

    test('maps targets, kind and rest from the plan', () {
      final m = buildPlansSnapshot(
        accountKey: _key,
        library: WorkoutLibrarySnapshot(
          exercises: [
            _exercise(0),
            _exercise(1, mode: 'duration'),
          ],
          plans: [
            WorkoutPlanRecord(
              uuid: 'p',
              name: 'Mixed',
              description: '',
              updatedAtMs: 0,
              exercises: const [
                PlanExerciseRecord(
                  uuid: 'a',
                  exerciseUuid: 'ex-0',
                  position: 0,
                  targetSets: 2,
                  targetRepsMin: 8,
                  targetRepsMax: 12,
                  restSeconds: 60,
                ),
                PlanExerciseRecord(
                  uuid: 'b',
                  exerciseUuid: 'ex-1',
                  position: 1,
                  targetSets: 1,
                  targetDurationSeconds: 45,
                ),
              ],
            ),
          ],
        ),
        week: null,
        recentSessions: const [],
        nowUtc: _now,
        messageId: _id,
      );
      final exercises = ((m.plans.single! as Map)['exercises']! as List);
      final first = exercises[0] as Map;
      final second = exercises[1] as Map;
      expect(first['kind'], 'reps');
      expect((first['sets'] as List), hasLength(2));
      expect((first['sets'] as List).first, {
        'position': 0,
        'kind': 'working',
        'target_reps': 8,
        'rest_seconds': 60,
      });
      expect(second['kind'], 'duration');
      expect((second['sets'] as List).single, {
        'position': 0,
        'kind': 'working',
        'target_seconds': 45,
      });
      _roundTrip(m);
    });

    test('recent exercises are the last 30 distinct, newest first', () {
      final sessions = [
        for (var i = 0; i < 40; i++)
          _session(
            's$i',
            planUuid: null,
            completedAt: DateTime.utc(2026, 10, 1).add(Duration(days: i)),
            exerciseUuids: ['ex-$i'],
          ),
        // A repeat of ex-39 from an older session must not duplicate it.
        _session(
          'old',
          planUuid: null,
          completedAt: DateTime.utc(2026, 9, 1),
          exerciseUuids: ['ex-39'],
        ),
      ];
      final m = buildPlansSnapshot(
        accountKey: _key,
        library: _library(const []),
        week: null,
        recentSessions: sessions,
        nowUtc: _now,
        messageId: _id,
      );
      final ids = [
        for (final e in m.recentExercises) (e! as Map)['exercise_id'],
      ];
      expect(ids, hasLength(30));
      expect(ids.first, 'ex-39');
      expect(ids.toSet(), hasLength(30));
      expect(ids.last, 'ex-10');
      _roundTrip(m);
    });

    test('archived plans are left out', () {
      final archived = WorkoutPlanRecord(
        uuid: 'gone',
        name: 'Gone',
        description: '',
        updatedAtMs: 0,
        archivedAtMs: 1,
        exercises: const [],
      );
      final m = buildPlansSnapshot(
        accountKey: _key,
        library: _library([archived, _plan('plan-a', 'Alpha')]),
        week: null,
        recentSessions: const [],
        nowUtc: _now,
        messageId: _id,
      );
      expect([for (final p in m.plans) (p! as Map)['name']], ['Alpha']);
    });

    test(
      '150 plans x 40 exercises stays under 60000 bytes and within caps',
      () {
        final plans = [
          for (var i = 0; i < 150; i++)
            _plan(
              'plan-$i',
              'Plan ${i.toString().padLeft(3, '0')}',
              exercises: 40,
              sets: 3,
            ),
        ];
        final today = _plan('plan-today', 'Program day', exercises: 40);
        final m = buildPlansSnapshot(
          accountKey: _key,
          library: _library(plans),
          week: _week(today),
          recentSessions: const [],
          nowUtc: _now,
          messageId: _id,
        );
        final bytes = utf8.encode(jsonEncode(m.toJson())).length;
        expect(bytes, lessThanOrEqualTo(60000));
        expect(m.plans.length, lessThanOrEqualTo(100));
        expect(m.plans, isNotEmpty);
        expect((m.plans.first! as Map)['name'], 'Program day');
        _roundTrip(m);
        // Deterministic: the same input gives the same output.
        final again = buildPlansSnapshot(
          accountKey: _key,
          library: _library(plans),
          week: _week(today),
          recentSessions: const [],
          nowUtc: _now,
          messageId: _id,
        );
        expect(jsonEncode(again.toJson()), jsonEncode(m.toJson()));
      },
    );

    test('a plan too large for the limit is skipped and later plans stay', () {
      final m = buildPlansSnapshot(
        accountKey: _key,
        library: _library([
          _plan('plan-big', 'A huge plan', exercises: 40, sets: 30),
          _plan('plan-small', 'B small plan'),
        ]),
        week: null,
        recentSessions: const [],
        nowUtc: _now,
        messageId: _id,
      );
      expect([for (final p in m.plans) (p! as Map)['name']], ['B small plan']);
    });

    test('maxBytes budgets the plans snapshot below the full limit', () {
      final plans = [
        for (var i = 0; i < 20; i++) _plan('plan-$i', 'Plan $i', exercises: 10),
      ];
      final full = buildPlansSnapshot(
        accountKey: _key,
        library: _library(plans),
        week: null,
        recentSessions: const [],
        nowUtc: _now,
        messageId: _id,
      );
      final small = buildPlansSnapshot(
        accountKey: _key,
        library: _library(plans),
        week: null,
        recentSessions: const [],
        nowUtc: _now,
        messageId: _id,
        maxBytes: 6000,
      );
      expect(utf8.encode(jsonEncode(small.toJson())).length, lessThan(6001));
      expect(small.plans, isNotEmpty);
      expect(small.plans.length, lessThan(full.plans.length));
    });

    test('names and ids over the contract length are shortened', () {
      final long = 'n' * 300;
      final m = buildPlansSnapshot(
        accountKey: _key,
        library: _library([_plan('p' * 200, long)]),
        week: null,
        recentSessions: const [],
        nowUtc: _now,
        messageId: _id,
      );
      _roundTrip(m);
    });
  });

  group('load unit', () {
    test('follows the latest completed session and defaults to kg', () {
      expect(watchLoadUnit(const []), 'kg');
      final lb = WorkoutSessionRecord(
        uuid: 'u',
        name: 'n',
        status: WorkoutStatus.completed,
        startedAtUtc: DateTime.utc(2026, 11, 1),
        originalOffsetMinutes: 0,
        revision: 1,
        completedAtUtc: DateTime.utc(2026, 11, 1, 1),
        exercises: const [],
        sets: [
          WorkoutSetRecord(
            uuid: 's',
            exerciseUuid: 'e',
            position: 0,
            kind: WorkoutSetKind.working,
            status: WorkoutSetStatus.completed,
            reps: 5,
            inputUnit: LoadUnit.lb,
            completedAtUtc: DateTime.utc(2026, 11, 1),
          ),
        ],
      );
      expect(watchLoadUnit([lb]), 'lb');
    });
  });
}
