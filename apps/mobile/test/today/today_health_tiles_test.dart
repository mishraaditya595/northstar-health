import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/domain/metric_explanations.dart';
import 'package:beyondrep/features/health/domain/sleep_nights.dart';
import 'package:beyondrep/features/health/widgets/today_health_tiles.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/health_overview_fixtures.dart';

WorkoutSessionRecord _session(
  String name,
  DateTime started,
  Duration length, {
  WorkoutStatus status = WorkoutStatus.completed,
}) => WorkoutSessionRecord(
  uuid: name,
  name: name,
  status: status,
  startedAtUtc: started.toUtc(),
  originalOffsetMinutes: 0,
  revision: 1,
  completedAtUtc: started.add(length).toUtc(),
);

HeartOverview _heart({required double today, required int days}) =>
    HeartOverview(
      restingHr: (day: DateTime(2026, 11, 24), value: today),
      restingHrDaily: daily(days, (i) => i == days - 1 ? today : 60.0),
      hrv: null,
      hrvDaily: const [],
      vo2Max: null,
      vo2MaxDaily: const [],
      restingHrVsMonth: null,
      hrvVsNormal: null,
      hrvIsSdnn: true,
    );

void main() {
  test('sleepTile caption is Ended 7:59 AM', () {
    final base = night();
    final late = SleepNight(
      date: base.date,
      start: base.start,
      end: DateTime(2026, 11, 24, 7, 59),
      source: base.source,
      segments: base.segments,
      asleep: base.asleep,
      deep: base.deep,
      light: base.light,
      rem: base.rem,
      awake: base.awake,
      inBed: null,
    );
    final tile = sleepTile(overview(sleep: SectionData(sleepOverview(late))));
    expect(tile.label, 'Sleep');
    expect(tile.value, '6h 12m');
    expect(tile.caption, 'Ended 7:59 AM');
    expect(tile.infoKey, MetricKey.timeAsleep);
  });

  test('stepsTile caption is As of the read time and has a daily average', () {
    final tile = stepsTile(overview());
    expect(tile.value, '8,214');
    expect(tile.caption, 'As of 7:42 AM');
    expect(tile.infoKey, MetricKey.steps);
    expect(tile.usual?.dailyAverage, isTrue);
  });

  test('restingHrTile says 2 below usual', () {
    final tile = restingHrTile(
      overview(heart: SectionData(_heart(today: 58, days: 30))),
    );
    expect(tile.value, '58');
    expect(tile.unit, 'bpm');
    expect(tile.caption, 'Today · 2 below usual');
  });

  test('restingHrTile says above and about usual', () {
    expect(
      restingHrTile(overview(heart: SectionData(_heart(today: 63, days: 30))))
          .caption,
      'Today · 3 above usual',
    );
    expect(
      restingHrTile(overview(heart: SectionData(_heart(today: 60.4, days: 30))))
          .caption,
      'Today · about usual',
    );
  });

  test('restingHrTile omits usual under 14 days', () {
    final tile = restingHrTile(
      overview(heart: SectionData(_heart(today: 58, days: 13))),
    );
    expect(tile.caption, 'Today');
    expect(tile.usual, isNull);
  });

  test("workoutsTile counts only today's completed sessions", () {
    final now = DateTime(2026, 11, 24, 18, 20);
    final tile = workoutsTile([
      _session(
        'Pull day',
        DateTime(2026, 11, 23, 18),
        const Duration(hours: 1),
      ),
      _session(
        'Push day',
        DateTime(2026, 11, 24, 7, 30),
        const Duration(minutes: 32, seconds: 20),
      ),
      _session('Legs', DateTime(2026, 11, 24, 12), const Duration(minutes: 45)),
      _session(
        'Unfinished',
        DateTime(2026, 11, 24, 13),
        const Duration(minutes: 5),
        status: WorkoutStatus.inProgress,
      ),
    ], now);
    expect(tile.label, 'Workouts');
    expect(tile.value, '2');
    expect(tile.unit, 'today');
    expect(tile.caption, 'Push day · 32 min');
    expect(tile.route, '/progress');
    expect(tile.infoKey, isNull);
  });

  test('workoutsTile with none is a dash and None yet today', () {
    final tile = workoutsTile(const [], DateTime(2026, 11, 24, 18));
    expect(tile.value, '—');
    expect(tile.caption, 'None yet today');
  });

  test('gap tiles keep Allow more data, Not allowed and Try again', () {
    String caption(MetricGap gap) =>
        stepsTile(overview(activity: SectionGap(gap))).caption;
    expect(caption(MetricGap.needsAccess), 'Allow more data');
    expect(caption(MetricGap.notAllowed), 'Not allowed · Manage');
    expect(caption(MetricGap.failed), "Couldn't read · Try again");
    expect(caption(MetricGap.unsupported), 'Not available on this device');
    expect(caption(MetricGap.noData), 'No steps yet today');
    expect(
      sleepTile(overview(sleep: const SectionGap(MetricGap.noData))).caption,
      'No sleep recorded last night',
    );
    expect(
      restingHrTile(overview(heart: const SectionGap(MetricGap.noData)))
          .caption,
      'None in the last 30 days',
    );
  });

  test('missing steps never shows 0', () {
    final tile = stepsTile(
      overview(
        activity: SectionData(
          ActivityOverview(
            stepsToday: null,
            stepsDaily: const [],
            activeEnergyToday: null,
            activeEnergyDaily: const [],
            stepsWeekAverage: null,
          ),
        ),
      ),
    );
    expect(tile.value, isNull);
    expect(tile.caption, 'No steps yet today');
  });
}
