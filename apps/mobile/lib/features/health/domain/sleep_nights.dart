import 'health_types.dart';

/// Total minutes covered by [segments], counting overlapping or duplicate
/// segments (several sources, or stage plus total records) only once.
int mergedSleepMinutes(List<({DateTime from, DateTime to})> segments) {
  final sorted = [...segments]..sort((a, b) => a.from.compareTo(b.from));
  var total = Duration.zero;
  DateTime? start;
  DateTime? end;
  for (final s in sorted) {
    if (!s.to.isAfter(s.from)) continue;
    if (end == null || s.from.isAfter(end)) {
      if (start != null) total += end!.difference(start);
      start = s.from;
      end = s.to;
    } else if (s.to.isAfter(end)) {
      end = s.to;
    }
  }
  if (start != null) total += end!.difference(start);
  return total.inMinutes;
}

/// One source's main sleep for a local date (the date it ended on).
class SleepNight {
  const SleepNight({
    required this.date,
    required this.start,
    required this.end,
    required this.source,
    required this.segments,
    required this.asleep,
    required this.deep,
    required this.light,
    required this.rem,
    required this.awake,
    required this.inBed,
  });

  /// Local date the main sleep ended on.
  final DateTime date;

  /// First and last asleep segment.
  final DateTime start, end;
  final String source;

  /// This source, this session, all stages including awake and inBed.
  final List<SleepSegment> segments;
  final Duration asleep, deep, light, rem, awake;

  /// From inBed segments of this source, else null.
  final Duration? inBed;

  bool get hasStages => deep + rem > Duration.zero;
  Duration get span => end.difference(start);
}

const _sessionGap = Duration(minutes: 60);
const _asleepStages = {
  SleepStage.light,
  SleepStage.deep,
  SleepStage.rem,
  SleepStage.asleepUnspecified,
};

DateTime _localDate(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

Duration _merged(Iterable<SleepSegment> segments) => Duration(
  minutes: mergedSleepMinutes([
    for (final s in segments) (from: s.from, to: s.to),
  ]),
);

class _Session {
  _Session(SleepSegment first) : start = first.from, end = first.to {
    asleep.add(first);
  }

  final DateTime start;
  DateTime end;
  final List<SleepSegment> asleep = [];
  final List<SleepSegment> other = [];
}

SleepNight _night(_Session s) {
  final all = [...s.asleep, ...s.other]
    ..sort((a, b) => a.from.compareTo(b.from));
  Duration stage(SleepStage st) => _merged(all.where((x) => x.stage == st));
  final inBed = all.where((x) => x.stage == SleepStage.inBed);
  return SleepNight(
    date: _localDate(s.end),
    start: s.start,
    end: s.end,
    source: s.asleep.first.source,
    segments: List.unmodifiable(all),
    asleep: _merged(s.asleep),
    deep: stage(SleepStage.deep),
    light: stage(SleepStage.light),
    rem: stage(SleepStage.rem),
    awake: stage(SleepStage.awake),
    inBed: inBed.isEmpty ? null : _merged(inBed),
  );
}

List<_Session> _sessions(List<SleepSegment> source) {
  final sorted = [...source]..sort((a, b) => a.from.compareTo(b.from));
  final sessions = <_Session>[];
  for (final s in sorted.where((s) => _asleepStages.contains(s.stage))) {
    final current = sessions.isEmpty ? null : sessions.last;
    if (current == null || s.from.difference(current.end) > _sessionGap) {
      sessions.add(_Session(s));
    } else {
      current.asleep.add(s);
      if (s.to.isAfter(current.end)) current.end = s.to;
    }
  }
  // awake/inBed attach to the first session whose padded window they overlap.
  for (final s in sorted.where((s) => !_asleepStages.contains(s.stage))) {
    for (final session in sessions) {
      if (s.from.isBefore(session.end.add(_sessionGap)) &&
          s.to.isAfter(session.start.subtract(_sessionGap))) {
        session.other.add(s);
        break;
      }
    }
  }
  return sessions;
}

bool _isMainSleepCandidate(_Session s) {
  final end = s.end.toLocal();
  return end.hour >= 3 || _localDate(s.end).isAfter(_localDate(s.start));
}

/// Health Connect sources may write a sleep session without stages, which
/// reads as an in-bed segment only. Each in-bed segment that overlaps no
/// asleep stage from the same [SleepSegment.sourceKey] becomes unspecified
/// sleep over the session (no stages, so no score). Other segments pass
/// through unchanged.
List<SleepSegment> sessionsWithoutStagesAsSleep(List<SleepSegment> segments) {
  bool hasStages(SleepSegment session) => segments.any(
    (s) =>
        s.sourceKey == session.sourceKey &&
        _asleepStages.contains(s.stage) &&
        s.from.isBefore(session.to) &&
        s.to.isAfter(session.from),
  );
  return [
    for (final s in segments)
      if (s.stage == SleepStage.inBed && !hasStages(s))
        (
          from: s.from,
          to: s.to,
          stage: SleepStage.asleepUnspecified,
          source: s.source,
          sourceKey: s.sourceKey,
        )
      else
        s,
  ];
}

/// Turns raw sleep segments into at most one [SleepNight] per local date,
/// ascending. Per source and date the longest main-sleep candidate wins (so
/// a nap never beats the main sleep, but a nap-only day shows the nap); per
/// date the source with most deep+rem+light, then most asleep, then source
/// key. Sources are told apart by [SleepSegment.sourceKey], not the shown
/// name.
List<SleepNight> buildNights(List<SleepSegment> segments) {
  final bySource = <String, List<SleepSegment>>{};
  for (final s in segments) {
    bySource.putIfAbsent(s.sourceKey, () => []).add(s);
  }
  final byDate = <DateTime, (String, SleepNight)>{};
  for (final MapEntry(key: key, value: list) in bySource.entries) {
    final perDate = <DateTime, SleepNight>{};
    for (final session in _sessions(list).where(_isMainSleepCandidate)) {
      final night = _night(session);
      final kept = perDate[night.date];
      if (kept == null || night.asleep > kept.asleep) {
        perDate[night.date] = night;
      }
    }
    for (final night in perDate.values) {
      final kept = byDate[night.date];
      if (kept == null || _beats(night, key, kept.$2, kept.$1)) {
        byDate[night.date] = (key, night);
      }
    }
  }
  return [for (final d in byDate.keys.toList()..sort()) byDate[d]!.$2];
}

bool _beats(SleepNight a, String aKey, SleepNight b, String bKey) {
  final staged = (a.deep + a.rem + a.light).compareTo(b.deep + b.rem + b.light);
  if (staged != 0) return staged > 0;
  final asleep = a.asleep.compareTo(b.asleep);
  if (asleep != 0) return asleep > 0;
  return aKey.compareTo(bKey) < 0;
}
