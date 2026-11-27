import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/domain/daily_series.dart';
import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:beyondrep/features/health/domain/sleep_nights.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs the language-neutral cases in `contracts/watch_link/v1/cases/health`
/// through the phone's day rules. The watch's Swift port
/// (`WatchHealthDerivation`) runs the same files, so both produce the same
/// numbers. Picks today's values the way `buildHealthSnapshot` does.

const _dir = '../../contracts/watch_link/v1/cases/health';

const _stages = {
  'light': SleepStage.light,
  'deep': SleepStage.deep,
  'rem': SleepStage.rem,
  'asleep_unspecified': SleepStage.asleepUnspecified,
  'awake': SleepStage.awake,
  'in_bed': SleepStage.inBed,
};

List<File> _files() =>
    Directory(_dir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

HealthSample _sample(Map<String, Object?> j) => (
  from: DateTime.parse(j['from']! as String),
  to: DateTime.parse(j['to']! as String),
  value: (j['value']! as num).toDouble(),
  source: 'synthetic',
);

Map<String, int> _derive(Map<String, Object?> c) {
  final today = dayOf(DateTime.parse(c['now']! as String).toLocal());
  final segments = <SleepSegment>[
    for (final s in (c['sleep']! as List).cast<Map<String, Object?>>())
      (
        from: DateTime.parse(s['from']! as String),
        to: DateTime.parse(s['to']! as String),
        stage: _stages[s['stage']]!,
        source: 'synthetic',
        sourceKey: s['source_key']! as String,
      ),
  ];
  final hrv = [
    for (final s in (c['hrv']! as List).cast<Map<String, Object?>>())
      _sample(s),
  ];
  final rhr = [
    for (final s in (c['resting_hr']! as List).cast<Map<String, Object?>>())
      _sample(s),
  ];

  final nights = buildNights(segments);
  final out = <String, int>{};
  final night = nights.where((n) => dayOf(n.date) == today).lastOrNull;
  if (night != null) out['asleep_minutes'] = night.asleep.inMinutes;
  for (final d in hrvDailyOf(hrv, nights)) {
    if (dayOf(d.day) == today) out['hrv_ms'] = d.value.round();
  }
  for (final d in reduceDaily(rhr, DailyReduction.latest)) {
    if (dayOf(d.day) == today) out['resting_hr_bpm'] = d.value.round();
  }
  return out;
}

void main() {
  final files = _files();

  test('there are at least 8 health cases', () {
    expect(files.length, greaterThanOrEqualTo(8));
  });

  for (final f in files) {
    final name = f.uri.pathSegments.last;
    final c = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    final offset = c['utc_offset_minutes']! as int;
    final sameZone = DateTime.now().timeZoneOffset.inMinutes == offset;
    test(
      name,
      () {
        expect(
          _derive(c),
          equals(c['expected']),
          reason: c['description']! as String,
        );
      },
      skip: sameZone
          ? null
          : 'buildNights uses the device zone; this case needs UTC offset '
                '$offset min',
    );
  }
}
