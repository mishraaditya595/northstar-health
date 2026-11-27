import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/health/domain/trend.dart';
import 'package:beyondrep/features/health/widgets/readiness_card.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/health_overview_fixtures.dart';

TrendResult _trend(TrendDirection d) => TrendResult(
  direction: d,
  tone: d == TrendDirection.flat ? TrendTone.same : TrendTone.better,
  delta: 1,
);

ReadinessPart _part(ReadinessInput input) =>
    ReadinessPart(input: input, score: 70, weight: 0.25);

({HealthOverview overview, ReadinessOverview value, Readiness readiness})
_case({
  bool hrv = true,
  bool restingHr = true,
  double? loadRatio,
  TrendDirection hrvTrend = TrendDirection.up,
  TrendDirection rhrTrend = TrendDirection.down,
  int asleepMinutes = 450,
}) {
  final readiness = Readiness(
    value: 77,
    band: ReadinessBand.good,
    parts: [
      if (hrv) _part(ReadinessInput.hrv),
      if (restingHr) _part(ReadinessInput.restingHr),
      _part(ReadinessInput.sleep),
    ],
    loadRatio: loadRatio,
  );
  final value = ReadinessOverview(
    result: ReadinessReady(readiness),
    hasHrv: hrv,
    hasRestingHr: restingHr,
    hasSleep: true,
    hrvVsNormal: hrv ? _trend(hrvTrend) : null,
    restingHrVsNormal: restingHr ? _trend(rhrTrend) : null,
    hrvBaseline: null,
    restingHrBaseline: null,
    hrvIsSdnn: true,
  );
  final o = overview(
    sleep: SectionData(sleepOverview(night(asleep: asleepMinutes))),
    readiness: SectionData(value),
  );
  return (overview: o, value: value, readiness: readiness);
}

void main() {
  test('lists only the inputs the score used, in order', () {
    final c = _case(hrv: false, loadRatio: 1.0);
    final f = readinessFactors(c.overview, c.value, c.readiness);
    expect(
      [for (final x in f) x.input],
      ['sleep', 'resting_hr', 'training_load'],
    );

    final all = _case(loadRatio: 1.0);
    expect(
      [
        for (final x in readinessFactors(
          all.overview,
          all.value,
          all.readiness,
        ))
          x.input,
      ],
      ['sleep', 'hrv', 'resting_hr', 'training_load'],
    );

    final none = _case(hrv: false, restingHr: false);
    expect(
      [
        for (final x in readinessFactors(
          none.overview,
          none.value,
          none.readiness,
        ))
          x.input,
      ],
      ['sleep'],
    );
  });

  test('wording follows the same trend as readinessReasons', () {
    final c = _case(
      hrvTrend: TrendDirection.down,
      rhrTrend: TrendDirection.flat,
      loadRatio: 1.4,
    );
    final f = {
      for (final x in readinessFactors(c.overview, c.value, c.readiness))
        x.input: x,
    };
    final reasons = readinessReasons(c.overview, c.value, c.readiness);
    expect(f['sleep']!.status, 'Slept 7h 30m');
    expect(reasons, contains('slept 7h 30m'));
    expect(f['hrv']!.status, 'Below usual');
    expect(f['hrv']!.tone, 'caution');
    expect(reasons, contains('below your normal'));
    expect(f['resting_hr']!.status, 'About usual');
    expect(f['resting_hr']!.tone, 'neutral');
    expect(f['training_load']!.status, 'Above usual');
    expect(f['training_load']!.tone, 'caution');

    final up = _case(rhrTrend: TrendDirection.up, loadRatio: 1.3);
    final g = {
      for (final x in readinessFactors(up.overview, up.value, up.readiness))
        x.input: x,
    };
    expect(g['hrv']!.status, 'Above usual');
    expect(g['hrv']!.tone, 'good');
    expect(g['resting_hr']!.status, 'Above usual');
    expect(g['resting_hr']!.tone, 'caution');
    expect(g['training_load']!.status, 'Normal');
    expect(g['training_load']!.tone, 'neutral');

    final down = _case(rhrTrend: TrendDirection.down);
    expect(
      readinessFactors(
        down.overview,
        down.value,
        down.readiness,
      ).firstWhere((x) => x.input == 'resting_hr').tone,
      'good',
    );
  });

  test('sleep tone follows 7 h and 6 h', () {
    String tone(int minutes) {
      final c = _case(asleepMinutes: minutes);
      return readinessFactors(
        c.overview,
        c.value,
        c.readiness,
      ).firstWhere((x) => x.input == 'sleep').tone;
    }

    expect(tone(420), 'good');
    expect(tone(419), 'neutral');
    expect(tone(360), 'neutral');
    expect(tone(359), 'caution');
  });

  test('status never exceeds 24 code points', () {
    final c = _case(asleepMinutes: 23 * 60 + 59, loadRatio: 2);
    for (final x in readinessFactors(c.overview, c.value, c.readiness)) {
      expect(x.status.runes.length, inInclusiveRange(1, 24), reason: x.input);
    }
  });
}
