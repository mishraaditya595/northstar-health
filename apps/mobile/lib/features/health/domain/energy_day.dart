import 'daily_series.dart';
import 'health_types.dart';
import 'sleep_nights.dart';
import 'training_load.dart';

/// Longest time after waking that still counts as the same waking day.
const energyMaxWakingDay = Duration(hours: 20);

/// Asleep segments starting sooner than this after waking are not naps (a
/// second source often logs sleep a few minutes past the wake time).
const energyNapAfterWake = Duration(minutes: 60);

/// Asleep stretches this close together join into one nap.
const energyNapJoinGap = Duration(minutes: 30);
const energyNapMinMinutes = 10;
const energyNapMaxMinutes = 180;

/// Usual days needed before active energy is compared with the usual.
const energyUsualMinDays = 7;

/// Awake time that costs nothing, then points lost per extra hour, capped.
const energyAwakeDipStart = Duration(hours: 8);
const energyAwakeDipPerHour = 0.5;
const energyAwakeDipMax = 5.0;

/// `day` is local midnight of the night's date; `wake` is the night's end.
typedef WakingDay = ({DateTime day, DateTime wake});

typedef Nap = ({DateTime start, DateTime end, int minutes});

const _asleepStages = {
  SleepStage.light,
  SleepStage.deep,
  SleepStage.rem,
  SleepStage.asleepUnspecified,
};

/// The latest night (of [nights], ascending) that ended no later than [now]
/// and at most [energyMaxWakingDay] before it; null when there is none.
WakingDay? wakingDayOf(List<SleepNight> nights, DateTime now) {
  for (final n in nights.reversed) {
    if (n.end.isAfter(now)) continue;
    if (now.difference(n.end) > energyMaxWakingDay) return null;
    return (day: dayOf(n.date), wake: n.end);
  }
  return null;
}

/// Daytime naps since [wake], oldest first. Asleep segments of any source
/// that start at least [energyNapAfterWake] after waking and end by [now]
/// are joined when closer than [energyNapJoinGap]; a nap's minutes are its
/// merged asleep minutes, kept from [energyNapMinMinutes] to
/// [energyNapMaxMinutes]. A stretch that chains (gaps up to
/// [energyNapJoinGap]) from asleep time starting before that is the night
/// running on, as another source logs it, and is no nap.
List<Nap> napsIn(
  List<SleepSegment> segments, {
  required DateTime wake,
  required DateTime now,
}) {
  final earliest = wake.add(energyNapAfterWake);
  final asleep = [
    for (final s in segments)
      if (_asleepStages.contains(s.stage) &&
          !s.to.isAfter(now) &&
          s.to.isAfter(s.from))
        s,
  ]..sort((a, b) => a.from.compareTo(b.from));

  final groups = <List<SleepSegment>>[];
  DateTime? groupEnd;
  for (final s in asleep) {
    if (groupEnd != null && s.from.difference(groupEnd) <= energyNapJoinGap) {
      groups.last.add(s);
      if (s.to.isAfter(groupEnd)) groupEnd = s.to;
    } else {
      groups.add([s]);
      groupEnd = s.to;
    }
  }

  return [
    for (final g in groups)
      if (_nap(g) case final nap?
          when !g.first.from.isBefore(earliest) &&
              nap.minutes >= energyNapMinMinutes &&
              nap.minutes <= energyNapMaxMinutes)
        nap,
  ];
}

Nap? _nap(List<SleepSegment> group) {
  var end = group.first.to;
  for (final s in group) {
    if (s.to.isAfter(end)) end = s.to;
  }
  return (
    start: group.first.from,
    end: end,
    minutes: mergedSleepMinutes([
      for (final s in group) (from: s.from, to: s.to),
    ]),
  );
}

/// When [s] ended: its start plus its minutes.
DateTime loadSessionEnd(LoadSession s) =>
    s.start.add(Duration(seconds: (s.minutes * 60).round()));

/// Active energy burned since waking above what this clock hour usually
/// holds, in kcal. Hours a counted workout overlaps are skipped (the workout
/// is its own item). Null with fewer than [energyUsualMinDays] usual days:
/// local dates before the waking day with any active energy in [hourly].
double? activeExcessKcal(
  List<HealthSample> hourly, {
  required WakingDay day,
  required DateTime now,
  List<LoadSession> workouts = const [],
}) {
  final usualDays = <DateTime>{};
  final sumByHour = List<double>.filled(24, 0);
  for (final s in hourly) {
    final date = dayOf(s.from);
    if (!date.isBefore(day.day) || s.value <= 0) continue;
    usualDays.add(date);
    sumByHour[s.from.toLocal().hour] += s.value;
  }
  if (usualDays.length < energyUsualMinDays) return null;

  final ranges = [
    for (final w in workouts) (start: w.start, end: loadSessionEnd(w)),
  ];
  var excess = 0.0;
  for (final s in hourly) {
    if (!s.to.isAfter(day.wake) || !s.from.isBefore(now)) continue;
    if (ranges.any((r) => s.from.isBefore(r.end) && s.to.isAfter(r.start))) {
      continue;
    }
    final usual = sumByHour[s.from.toLocal().hour] / usualDays.length;
    if (s.value > usual) excess += s.value - usual;
  }
  return excess;
}

/// Points lost to being awake long: none up to [energyAwakeDipStart], then
/// [energyAwakeDipPerHour] per hour, at most [energyAwakeDipMax].
double awakeDipPoints(Duration awake) {
  final hours = (awake - energyAwakeDipStart).inMicroseconds / 3600000000;
  if (hours <= 0) return 0;
  final points = hours * energyAwakeDipPerHour;
  return points > energyAwakeDipMax ? energyAwakeDipMax : points;
}
