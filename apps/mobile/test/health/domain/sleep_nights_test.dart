import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:beyondrep/features/health/domain/sleep_nights.dart';
import 'package:flutter_test/flutter_test.dart';

SleepSegment seg(
  DateTime from,
  DateTime to,
  SleepStage stage, {
  String source = 'watch',
  String? sourceKey,
}) => (
  from: from,
  to: to,
  stage: stage,
  source: source,
  sourceKey: sourceKey ?? source,
);

/// 23:30 -> 06:30 (Nov 23 -> Nov 24): 2h light, 1h30 deep, 1h30 rem, 2h light.
List<SleepSegment> stagedNight({String source = 'watch', String? sourceKey}) =>
    [
      seg(
        DateTime(2026, 11, 23, 23, 30),
        DateTime(2026, 11, 24, 1, 30),
        SleepStage.light,
        source: source,
        sourceKey: sourceKey,
      ),
      seg(
        DateTime(2026, 11, 24, 1, 30),
        DateTime(2026, 11, 24, 3),
        SleepStage.deep,
        source: source,
        sourceKey: sourceKey,
      ),
      seg(
        DateTime(2026, 11, 24, 3),
        DateTime(2026, 11, 24, 4, 30),
        SleepStage.rem,
        source: source,
        sourceKey: sourceKey,
      ),
      seg(
        DateTime(2026, 11, 24, 4, 30),
        DateTime(2026, 11, 24, 6, 30),
        SleepStage.light,
        source: source,
        sourceKey: sourceKey,
      ),
    ];

({DateTime from, DateTime to}) _seg(DateTime from, DateTime to) =>
    (from: from, to: to);

void main() {
  test('main sleep across midnight is one night dated the morning', () {
    final nights = buildNights(stagedNight());
    expect(nights, hasLength(1));
    final n = nights.single;
    expect(n.date, DateTime(2026, 11, 24));
    expect(n.start, DateTime(2026, 11, 23, 23, 30));
    expect(n.end, DateTime(2026, 11, 24, 6, 30));
    expect(n.span, const Duration(hours: 7));
    expect(n.asleep, const Duration(hours: 7));
    expect(n.light, const Duration(hours: 4));
    expect(n.deep, const Duration(hours: 1, minutes: 30));
    expect(n.rem, const Duration(hours: 1, minutes: 30));
    expect(n.awake, Duration.zero);
    expect(n.inBed, isNull);
    expect(n.hasStages, isTrue);
    expect(n.source, 'watch');
    expect(n.segments, hasLength(4));
  });

  test('nap on the same date as a main sleep loses to the main sleep', () {
    final nap = seg(
      DateTime(2026, 11, 24, 14),
      DateTime(2026, 11, 24, 14, 40),
      SleepStage.asleepUnspecified,
    );
    final nights = buildNights([...stagedNight(), nap]);
    expect(nights, hasLength(1));
    final n = nights.single;
    expect(n.date, DateTime(2026, 11, 24));
    expect(n.asleep, const Duration(hours: 7));
    expect(n.end, DateTime(2026, 11, 24, 6, 30));
    expect(n.segments, isNot(contains(nap)));
  });

  test('nap the day after does not displace the next main sleep', () {
    // Nap on Nov 25 at 14:00 and the following night ends Nov 26 06:30.
    final nights = buildNights([
      ...stagedNight(),
      seg(
        DateTime(2026, 11, 25, 14),
        DateTime(2026, 11, 25, 14, 40),
        SleepStage.asleepUnspecified,
      ),
      seg(
        DateTime(2026, 11, 25, 23),
        DateTime(2026, 11, 26, 6, 30),
        SleepStage.asleepUnspecified,
      ),
    ]);
    expect(nights.map((n) => n.date), [
      DateTime(2026, 11, 24),
      DateTime(2026, 11, 25),
      DateTime(2026, 11, 26),
    ]);
    // A nap-only day shows the nap (documented rule).
    expect(nights[1].asleep, const Duration(minutes: 40));
    // The night ending Nov 26 contains no nap.
    expect(nights[2].start, DateTime(2026, 11, 25, 23));
    expect(nights[2].asleep, const Duration(hours: 7, minutes: 30));
  });

  test('a lone nap with no main sleep that day shows the nap', () {
    final nights = buildNights([
      seg(
        DateTime(2026, 11, 24, 14),
        DateTime(2026, 11, 24, 14, 40),
        SleepStage.light,
      ),
    ]);
    expect(nights.single.date, DateTime(2026, 11, 24));
    expect(nights.single.asleep, const Duration(minutes: 40));
  });

  test('session ending before 03:00 on its start date is not a candidate', () {
    final nights = buildNights([
      seg(
        DateTime(2026, 11, 24, 0, 30),
        DateTime(2026, 11, 24, 2, 30),
        SleepStage.light,
      ),
    ]);
    expect(nights, isEmpty);
  });

  test('two sources same night: most deep+rem+light wins, one source only', () {
    // Ring: 00:30 -> 06:30 with stages (6h) overlapping the watch (7h).
    final ring = [
      seg(
        DateTime(2026, 11, 24, 0, 30),
        DateTime(2026, 11, 24, 3),
        SleepStage.light,
        source: 'ring',
      ),
      seg(
        DateTime(2026, 11, 24, 3),
        DateTime(2026, 11, 24, 4),
        SleepStage.deep,
        source: 'ring',
      ),
      seg(
        DateTime(2026, 11, 24, 4),
        DateTime(2026, 11, 24, 6, 30),
        SleepStage.rem,
        source: 'ring',
      ),
    ];
    final nights = buildNights([...ring, ...stagedNight()]);
    final n = nights.single;
    expect(n.source, 'watch');
    expect(n.segments.every((s) => s.source == 'watch'), isTrue);
    expect(n.deep, const Duration(hours: 1, minutes: 30));
    expect(n.rem, const Duration(hours: 1, minutes: 30));
    expect(n.light, const Duration(hours: 4));
    expect(n.asleep, const Duration(hours: 7));
  });

  test('sources sharing a display name are still one source per night', () {
    // Two wearables both shown as "Health Connect": the ring has less staged
    // sleep, so the watch's night is kept whole and nothing is merged.
    final ring = [
      seg(
        DateTime(2026, 11, 24, 0, 30),
        DateTime(2026, 11, 24, 3),
        SleepStage.light,
        source: 'Health Connect',
        sourceKey: 'com.example.ring',
      ),
      seg(
        DateTime(2026, 11, 24, 3),
        DateTime(2026, 11, 24, 4),
        SleepStage.deep,
        source: 'Health Connect',
        sourceKey: 'com.example.ring',
      ),
    ];
    final watch = stagedNight(
      source: 'Health Connect',
      sourceKey: 'com.example.watch',
    );
    final n = buildNights([...ring, ...watch]).single;
    expect(n.segments.every((s) => s.sourceKey == 'com.example.watch'), true);
    expect(n.deep, const Duration(hours: 1, minutes: 30));
    expect(n.light, const Duration(hours: 4));
    expect(n.asleep, const Duration(hours: 7));
    expect(n.source, 'Health Connect');
  });

  test('ties between sources sharing a name break on the source key', () {
    final a = stagedNight(source: 'Same', sourceKey: 'b-key');
    final b = stagedNight(source: 'Same', sourceKey: 'a-key');
    final n = buildNights([...a, ...b]).single;
    expect(n.segments.every((s) => s.sourceKey == 'a-key'), true);
    expect(n.asleep, const Duration(hours: 7));
  });

  test('source tie breaks by most asleep, then by name ascending', () {
    final a = stagedNight(source: 'b-source');
    final b = stagedNight(source: 'a-source');
    expect(buildNights([...a, ...b]).single.source, 'a-source');

    // Equal staged minutes; 'z' has an extra unspecified hour -> more asleep.
    final z = [
      ...stagedNight(source: 'z'),
      seg(
        DateTime(2026, 11, 24, 6, 30),
        DateTime(2026, 11, 24, 7, 30),
        SleepStage.asleepUnspecified,
        source: 'z',
      ),
    ];
    expect(buildNights([...b, ...z]).single.source, 'z');
  });

  test('asleepUnspecified only has no stages but asleep is set', () {
    final n = buildNights([
      seg(
        DateTime(2026, 11, 23, 23),
        DateTime(2026, 11, 24, 6),
        SleepStage.asleepUnspecified,
        source: 'phone',
      ),
    ]).single;
    expect(n.hasStages, isFalse);
    expect(n.asleep, const Duration(hours: 7));
    expect(n.light, Duration.zero);
  });

  test('a gap of 75 min splits sessions', () {
    final nights = buildNights([
      seg(
        DateTime(2026, 11, 23, 21),
        DateTime(2026, 11, 23, 22),
        SleepStage.light,
      ),
      seg(
        DateTime(2026, 11, 23, 23, 15),
        DateTime(2026, 11, 24, 6),
        SleepStage.light,
      ),
    ]);
    // 21:00-22:00 ends after 03:00, so it is its own candidate for Nov 23.
    expect(nights, hasLength(2));
    expect(nights.first.date, DateTime(2026, 11, 23));
    expect(nights.first.asleep, const Duration(hours: 1));
    final n = nights.last;
    expect(n.date, DateTime(2026, 11, 24));
    expect(n.start, DateTime(2026, 11, 23, 23, 15));
    expect(n.asleep, const Duration(hours: 6, minutes: 45));
  });

  test('a gap of exactly 60 min keeps one session', () {
    final n = buildNights([
      seg(
        DateTime(2026, 11, 23, 22),
        DateTime(2026, 11, 23, 23),
        SleepStage.light,
      ),
      seg(
        DateTime(2026, 11, 24, 0),
        DateTime(2026, 11, 24, 6),
        SleepStage.light,
      ),
    ]).single;
    expect(n.start, DateTime(2026, 11, 23, 22));
    expect(n.asleep, const Duration(hours: 7));
    expect(n.span, const Duration(hours: 8));
  });

  test('awake segments count in awake, not asleep; inBed is reported', () {
    final n = buildNights([
      ...stagedNight(),
      seg(
        DateTime(2026, 11, 24, 2),
        DateTime(2026, 11, 24, 2, 20),
        SleepStage.awake,
      ),
      seg(
        DateTime(2026, 11, 24, 6, 30),
        DateTime(2026, 11, 24, 7),
        SleepStage.awake,
      ),
      seg(
        DateTime(2026, 11, 23, 23),
        DateTime(2026, 11, 24, 7),
        SleepStage.inBed,
      ),
      // Far from the session: not attached.
      seg(
        DateTime(2026, 11, 24, 12),
        DateTime(2026, 11, 24, 12, 10),
        SleepStage.awake,
      ),
    ]).single;
    expect(n.asleep, const Duration(hours: 7));
    expect(n.awake, const Duration(minutes: 50));
    expect(n.inBed, const Duration(hours: 8));
    expect(n.segments, hasLength(7));
  });

  test('overlapping segments of a stage count once', () {
    final n = buildNights([
      seg(
        DateTime(2026, 11, 23, 23),
        DateTime(2026, 11, 24, 4),
        SleepStage.asleepUnspecified,
      ),
      seg(
        DateTime(2026, 11, 24, 2),
        DateTime(2026, 11, 24, 6),
        SleepStage.light,
      ),
    ]).single;
    expect(n.asleep, const Duration(hours: 7));
    expect(n.light, const Duration(hours: 4));
  });

  test('DST fall-back night: asleep equals real elapsed minutes', () {
    // 2026-10-25 is the EU fall-back date (01:00 UTC); UTC instants keep the
    // arithmetic independent of the machine's zone.
    final n = buildNights([
      seg(
        DateTime.utc(2026, 10, 24, 22, 30),
        DateTime.utc(2026, 10, 25, 5, 30),
        SleepStage.asleepUnspecified,
      ),
    ]).single;
    expect(n.asleep, const Duration(hours: 7));
    final localEnd = DateTime.utc(2026, 10, 25, 5, 30).toLocal();
    expect(n.date, DateTime(localEnd.year, localEnd.month, localEnd.day));
  });

  test('nights are ascending by date', () {
    final later = [
      for (final s in stagedNight())
        seg(
          s.from.add(const Duration(days: 2)),
          s.to.add(const Duration(days: 2)),
          s.stage,
        ),
    ];
    final nights = buildNights([...later, ...stagedNight()]);
    expect(nights.map((n) => n.date), [
      DateTime(2026, 11, 24),
      DateTime(2026, 11, 26),
    ]);
  });

  test('empty input yields no nights', () {
    expect(buildNights(const []), isEmpty);
  });

  group('mergedSleepMinutes', () {
    test('merges overlapping segments into one span', () {
      final minutes = mergedSleepMinutes([
        _seg(DateTime.utc(2026, 11, 23, 23), DateTime.utc(2026, 11, 24, 3)),
        _seg(DateTime.utc(2026, 11, 24, 2), DateTime.utc(2026, 11, 24, 6, 30)),
      ]);
      expect(minutes, 450);
    });

    test('counts identical duplicate segments once', () {
      final a = _seg(
        DateTime.utc(2026, 11, 23, 23),
        DateTime.utc(2026, 11, 24, 3),
      );
      expect(mergedSleepMinutes([a, a]), 240);
    });

    test('empty input is zero', () {
      expect(mergedSleepMinutes(const []), 0);
    });

    test('sums separate segments and merges adjacent ones', () {
      final minutes = mergedSleepMinutes([
        _seg(DateTime.utc(2026, 11, 24, 4), DateTime.utc(2026, 11, 24, 5)),
        _seg(DateTime.utc(2026, 11, 24, 1), DateTime.utc(2026, 11, 24, 2)),
        _seg(DateTime.utc(2026, 11, 24, 2), DateTime.utc(2026, 11, 24, 3)),
      ]);
      expect(minutes, 180);
    });

    test(
      'segment crossing midnight on a DST-change date uses real elapsed time',
      () {
        // 2026-03-29 is the EU spring-forward date; UTC instants keep the
        // arithmetic independent of the test machine's zone.
        final minutes = mergedSleepMinutes([
          _seg(
            DateTime.utc(2026, 3, 28, 22, 30),
            DateTime.utc(2026, 3, 29, 5, 15),
          ),
        ]);
        expect(minutes, 405);
      },
    );
  });
  group('sessionsWithoutStagesAsSleep', () {
    final bed = DateTime(2026, 11, 23, 23);
    final wake = DateTime(2026, 11, 24, 7);

    test('in-bed only builds no night on its own (iOS stays as before)', () {
      expect(buildNights([seg(bed, wake, SleepStage.inBed)]), isEmpty);
    });

    test('a session with no asleep stage from its source becomes sleep', () {
      final nights = buildNights(
        sessionsWithoutStagesAsSleep([
          seg(bed, wake, SleepStage.inBed, sourceKey: 'app'),
        ]),
      );
      expect(nights, hasLength(1));
      final n = nights.single;
      expect(n.date, DateTime(2026, 11, 24));
      expect(n.asleep, const Duration(hours: 8));
      expect(n.hasStages, isFalse);
      expect(n.inBed, isNull);
      expect(n.start, bed);
      expect(n.end, wake);
    });

    test('a session with stages from the same source stays in bed', () {
      final session = seg(
        DateTime(2026, 11, 23, 23),
        DateTime(2026, 11, 24, 7),
        SleepStage.inBed,
      );
      final out = sessionsWithoutStagesAsSleep([...stagedNight(), session]);
      expect(out.last, session);
      final n = buildNights(out).single;
      expect(n.asleep, const Duration(hours: 7));
      expect(n.inBed, const Duration(hours: 8));
    });

    test('a session with only awake stages is not turned into sleep', () {
      final session = seg(bed, wake, SleepStage.inBed, sourceKey: 'app');
      final out = sessionsWithoutStagesAsSleep([
        seg(
          DateTime(2026, 11, 24, 2),
          DateTime(2026, 11, 24, 3),
          SleepStage.awake,
          sourceKey: 'app',
        ),
        session,
      ]);
      expect(out.last, session);
      expect(buildNights(out), isEmpty);
    });

    test('stages from another source do not count', () {
      final out = sessionsWithoutStagesAsSleep([
        ...stagedNight(sourceKey: 'ring'),
        seg(bed, wake, SleepStage.inBed, sourceKey: 'app'),
      ]);
      expect(out.last.stage, SleepStage.asleepUnspecified);
      expect(out.last.sourceKey, 'app');
    });
  });
}
