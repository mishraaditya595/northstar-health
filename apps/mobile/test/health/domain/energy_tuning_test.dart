import 'package:beyondrep/features/health/domain/energy_day.dart';
import 'package:beyondrep/features/health/domain/energy_tuning.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/health/domain/sleep_nights.dart';
import 'package:beyondrep/features/health/domain/training_load.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 27, 12);

WorkoutSessionRecord session(
  String id,
  DateTime start, {
  List<({String ex, int? reps, int? grams, int? secs, double? rpe})> sets =
      const [],
  WorkoutStatus status = WorkoutStatus.completed,
  int minutes = 60,
  List<(String, String?, String)> exercises = const [],
  WorkoutSetKind kind = WorkoutSetKind.working,
  WorkoutSetStatus setStatus = WorkoutSetStatus.completed,
}) => WorkoutSessionRecord(
  uuid: id,
  name: id,
  status: status,
  startedAtUtc: start.toUtc(),
  originalOffsetMinutes: 0,
  revision: 1,
  completedAtUtc: start.add(Duration(minutes: minutes)).toUtc(),
  exercises: [
    for (final e in exercises)
      WorkoutExerciseRecord(
        uuid: e.$1,
        sessionUuid: id,
        nameSnapshot: e.$3,
        position: 0,
        definitionUuid: e.$2,
      ),
  ],
  sets: [
    for (var i = 0; i < sets.length; i++)
      WorkoutSetRecord(
        uuid: '$id-$i',
        exerciseUuid: sets[i].ex,
        position: i,
        kind: kind,
        status: setStatus,
        reps: sets[i].reps,
        durationSeconds: sets[i].secs,
        loadGrams: sets[i].grams,
        rpe: sets[i].rpe,
      ),
  ],
);

List<WorkoutSessionRecord> at(List<(int, int)> times, {int each = 1}) => [
  for (final (i, t) in times.indexed)
    for (var k = 0; k < each; k++)
      session('s$i-$k', DateTime(2026, 10, 1 + i, t.$1, t.$2)),
];

/// Same exercise `bench` (definition `def-bench`) in a session with `n` sets.
WorkoutSessionRecord bench(
  String id,
  DateTime start, {
  int kg = 100,
  int reps = 5,
  int n = 3,
  double? rpe,
  int? secs,
}) => session(
  id,
  start,
  exercises: [('$id-e', 'def-bench', 'Bench')],
  sets: [
    for (var i = 0; i < n; i++)
      (
        ex: '$id-e',
        reps: secs == null ? reps : null,
        grams: secs == null ? kg * 1000 : null,
        secs: secs,
        rpe: rpe,
      ),
  ],
);

void main() {
  group('usualTrainingHours', () {
    test('8 sessions at 22:10 and 22:40 give 21, 22 and 23', () {
      final s = [
        for (var i = 0; i < 4; i++)
          session('a$i', DateTime(2026, 10, 1 + i, 22, 10)),
        for (var i = 0; i < 4; i++)
          session('b$i', DateTime(2026, 10, 10 + i, 22, 40)),
      ];
      expect(usualTrainingHours(s), {21, 22, 23});
    });

    test('7 sessions give no usual hour', () {
      final s = [
        for (var i = 0; i < 7; i++)
          session('a$i', DateTime(2026, 10, 1 + i, 22)),
      ];
      expect(usualTrainingHours(s), isEmpty);
    });

    test('20 sessions spread one per hour fail the share rule', () {
      final s = [
        for (var i = 0; i < 20; i++)
          session('a$i', DateTime(2026, 10, 1 + i, i)),
      ];
      expect(usualTrainingHours(s), isEmpty);
    });

    test('hours wrap around midnight', () {
      final s = [
        for (var i = 0; i < 4; i++)
          session('a$i', DateTime(2026, 10, 1 + i, 23, 30)),
        for (var i = 0; i < 4; i++)
          session('b$i', DateTime(2026, 10, 10 + i, 0, 15)),
      ];
      expect(usualTrainingHours(s), containsAll([23, 0]));
    });
  });

  group('sessionPerformance', () {
    final earlier = [
      bench('e1', DateTime(2026, 11, 1, 10), kg: 90),
      bench('e2', DateTime(2026, 11, 3, 10), kg: 90),
    ];

    test('volume against the norm of earlier sessions', () {
      final s = bench('now', DateTime(2026, 11, 10, 10));
      expect(sessionPerformance(s, earlier), closeTo(1500 / 1350, 1e-9));
    });

    test('bodyweight reps and timed seconds are used', () {
      final bw = [
        for (final (i, id) in ['e1', 'e2'].indexed)
          session(
            id,
            DateTime(2026, 11, 1 + i),
            exercises: [('$id-e', null, 'Push-up')],
            sets: [(ex: '$id-e', reps: 10, grams: null, secs: null, rpe: null)],
          ),
      ];
      final s = session(
        'now',
        DateTime(2026, 11, 10),
        exercises: [('n-e', null, 'push-UP')],
        sets: [(ex: 'n-e', reps: 15, grams: null, secs: null, rpe: null)],
      );
      expect(sessionPerformance(s, bw), closeTo(1.5, 1e-9));
      final timed = [
        for (final (i, id) in ['t1', 't2'].indexed)
          bench(id, DateTime(2026, 11, 1 + i), secs: 30),
      ];
      expect(
        sessionPerformance(
          bench('t3', DateTime(2026, 11, 10), secs: 45),
          timed,
        ),
        closeTo(1.5, 1e-9),
      );
    });

    test('warm-up and skipped sets are ignored', () {
      final s = bench('now', DateTime(2026, 11, 10), n: 0);
      expect(sessionPerformance(s, earlier), isNull);
      final warm = session(
        'w',
        DateTime(2026, 11, 10),
        exercises: [('w-e', 'def-bench', 'Bench')],
        sets: [(ex: 'w-e', reps: 5, grams: 100000, secs: null, rpe: null)],
        kind: WorkoutSetKind.warmup,
      );
      expect(sessionPerformance(warm, earlier), isNull);
      final skipped = session(
        'k',
        DateTime(2026, 11, 10),
        exercises: [('k-e', 'def-bench', 'Bench')],
        sets: [(ex: 'k-e', reps: 5, grams: 100000, secs: null, rpe: null)],
        setStatus: WorkoutSetStatus.skipped,
      );
      expect(sessionPerformance(skipped, earlier), isNull);
    });

    test('one earlier session is no norm', () {
      final s = bench('now', DateTime(2026, 11, 10));
      expect(sessionPerformance(s, [earlier.first]), isNull);
    });

    test('RPE above the norm lowers the ratio', () {
      final withRpe = [
        bench('e1', DateTime(2026, 11, 1), kg: 90, rpe: 8),
        bench('e2', DateTime(2026, 11, 3), kg: 90, rpe: 8),
      ];
      final s = bench('now', DateTime(2026, 11, 10), rpe: 9);
      expect(sessionPerformance(s, withRpe), closeTo(1500 / 1350 * 0.95, 1e-9));
    });

    test('a load norm is never compared with a bodyweight session', () {
      final bw = session(
        'bw',
        DateTime(2026, 11, 10),
        exercises: [('bw-e', 'def-bench', 'Bench')],
        sets: [(ex: 'bw-e', reps: 10, grams: null, secs: null, rpe: null)],
      );
      expect(sessionPerformance(bw, earlier), isNull);
    });

    test('a session ratio is clamped to 0.5 to 2.0', () {
      final huge = bench('now', DateTime(2026, 11, 10), kg: 400);
      expect(sessionPerformance(huge, earlier), energySessionRatioMax);
      final tiny = bench('now2', DateTime(2026, 11, 10), kg: 10);
      expect(sessionPerformance(tiny, earlier), energySessionRatioMin);
    });

    test('zero-volume norms are skipped, never NaN', () {
      final zero = [
        bench('e1', DateTime(2026, 11, 1), reps: 0),
        bench('e2', DateTime(2026, 11, 3), reps: 0),
      ];
      expect(
        sessionPerformance(bench('now', DateTime(2026, 11, 10)), zero),
        isNull,
      );
    });
  });

  group('drainMultiplierOf', () {
    List<({double energy, double ratio})> pairs(
      double lowRatio,
      double highRatio, {
      int n = 10,
      double spread = 40,
    }) => [
      for (var i = 0; i < n; i++)
        (
          energy: 40 + spread * i / (n - 1),
          ratio: i < n ~/ 2 ? lowRatio : highRatio,
        ),
    ];

    test('not calibrated or too few pairs or small spread give 1.0', () {
      expect(drainMultiplierOf(pairs(0.85, 1), calibrated: false), 1.0);
      expect(drainMultiplierOf(pairs(0.85, 1, n: 9), calibrated: true), 1.0);
      expect(
        drainMultiplierOf(pairs(0.85, 1, spread: 8), calibrated: true),
        1.0,
      );
    });

    test('worse lower half clamps to 1.4, better to 0.6, equal-ish to 1.0', () {
      expect(drainMultiplierOf(pairs(0.85, 1), calibrated: true), 1.4);
      expect(drainMultiplierOf(pairs(1, 1), calibrated: true), 0.6);
      expect(
        drainMultiplierOf(pairs(0.95, 1), calibrated: true),
        closeTo(1.0, 1e-9),
      );
    });
  });

  group('energyTuningOf', () {
    final wake = DateTime(2026, 10, 20, 7);
    final nights = [
      SleepNight(
        date: DateTime(2026, 10, 20),
        start: DateTime(2026, 10, 19, 23),
        end: wake,
        source: 'w',
        segments: const [],
        asleep: const Duration(hours: 8),
        deep: Duration.zero,
        light: Duration.zero,
        rem: Duration.zero,
        awake: Duration.zero,
        inBed: null,
      ),
    ];
    ReadinessResult ready(int v) => ReadinessReady(
      Readiness(value: v, band: readinessBandOf(v), parts: const []),
    );

    EnergyTuning run(
      List<WorkoutSessionRecord> sessions, {
      List<LoadSession> load = const [],
      WakingDay? currentDay,
      ReadinessResult Function(DateTime)? onDay,
      List<SleepNight>? n,
    }) => energyTuningOf(
      sessions: sessions,
      load: load,
      nights: n ?? nights,
      readinessOnDay: onDay ?? (_) => ready(80),
      currentDay: currentDay,
      now: _now,
      calibrated: true,
    );

    test('usual hours come from sessions outside the current waking day', () {
      final old = [
        for (var i = 0; i < 8; i++)
          session('a$i', DateTime(2026, 11, 1 + i, 22)),
      ];
      final today = [
        for (var i = 0; i < 8; i++) session('t$i', DateTime(2026, 11, 27, 9)),
      ];
      final t = run(
        [...old, ...today],
        currentDay: (
          day: DateTime(2026, 11, 27),
          wake: DateTime(2026, 11, 27, 7),
        ),
      );
      expect(t.usualHours, {21, 22, 23});
      final u = run(
        today,
        currentDay: (
          day: DateTime(2026, 11, 27),
          wake: DateTime(2026, 11, 27, 7),
        ),
      );
      expect(u.usualHours, isEmpty);
    });

    test('no waking day or a not-ready start gives generic multiplier', () {
      final s = [
        for (var i = 0; i < 12; i++)
          bench('b$i', DateTime(2026, 11, 1 + i, 10)),
      ];
      expect(run(s).drainMultiplier, 1.0);
      expect(
        run(s, onDay: (_) => const ReadinessNotReady()).drainMultiplier,
        1.0,
      );
    });

    test('past energy subtracts an earlier same-day workout', () {
      final start = DateTime(2026, 10, 20, 10);
      final s = bench('b', start);
      double? energy(List<LoadSession> load) => pastEnergyAt(
        session: s,
        load: load,
        nights: nights,
        readinessOnDay: (_) => ready(80),
      );
      expect(energy(const []), 80);
      expect(
        energy([
          (start: DateTime(2026, 10, 20, 8), minutes: 60, intensity: 1.0),
          // Before waking and after the start: not counted.
          (start: DateTime(2026, 10, 20, 5), minutes: 30, intensity: 1.0),
          (start: DateTime(2026, 10, 20, 11), minutes: 60, intensity: 1.0),
        ]),
        closeTo(68, 1e-9),
      );
    });

    test('a session without a waking day has no past energy', () {
      final s = bench('b', DateTime(2026, 10, 25, 10));
      expect(
        pastEnergyAt(
          session: s,
          load: const [],
          nights: nights,
          readinessOnDay: (_) => ready(80),
        ),
        isNull,
      );
    });
  });
}
