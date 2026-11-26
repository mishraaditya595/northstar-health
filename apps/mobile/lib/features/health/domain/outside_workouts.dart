import '../../workouts/domain/workout_models.dart';

enum OutsideWorkoutKind {
  strength,
  running,
  walking,
  cycling,
  swimming,
  hiit,
  yoga,
  pilates,
  rowing,
  elliptical,
  hiking,
  dance,
  other,
}

String outsideWorkoutName(OutsideWorkoutKind kind) => switch (kind) {
  OutsideWorkoutKind.strength => 'Strength training',
  OutsideWorkoutKind.running => 'Running',
  OutsideWorkoutKind.walking => 'Walking',
  OutsideWorkoutKind.cycling => 'Cycling',
  OutsideWorkoutKind.swimming => 'Swimming',
  OutsideWorkoutKind.hiit => 'HIIT',
  OutsideWorkoutKind.yoga => 'Yoga',
  OutsideWorkoutKind.pilates => 'Pilates',
  OutsideWorkoutKind.rowing => 'Rowing',
  OutsideWorkoutKind.elliptical => 'Elliptical',
  OutsideWorkoutKind.hiking => 'Hiking',
  OutsideWorkoutKind.dance => 'Dance',
  OutsideWorkoutKind.other => 'Workout',
};

/// A workout another app saved to HealthKit / Health Connect. Read fresh,
/// held in memory only, never stored.
class OutsideWorkout {
  const OutsideWorkout({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
    required this.source,
    this.activeKcal,
    this.distanceMeters,
  });

  final String id;
  final OutsideWorkoutKind kind;

  /// UTC.
  final DateTime start;
  final DateTime end;
  final double? activeKcal;
  final double? distanceMeters;
  final String source;

  int get minutes => end.difference(start).inMinutes;
}

class WorkoutMerge {
  const WorkoutMerge({
    this.mergedIntoSession = const {},
    this.standalone = const [],
  });

  /// Keyed by `WorkoutSessionRecord.uuid`, largest overlap first.
  final Map<String, List<OutsideWorkout>> mergedIntoSession;

  /// Newest first.
  final List<OutsideWorkout> standalone;
}

int _overlapMs(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
  final start = aStart.isAfter(bStart) ? aStart : bStart;
  final end = aEnd.isBefore(bEnd) ? aEnd : bEnd;
  final ms = end.difference(start).inMilliseconds;
  return ms > 0 ? ms : 0;
}

/// Merges each outside workout into the completed session it overlaps most,
/// when the overlap is at least half of the shorter of the two.
WorkoutMerge mergeWorkouts(
  List<WorkoutSessionRecord> sessions,
  List<OutsideWorkout> outside,
) {
  final done = [
    for (final s in sessions)
      if (s.status == WorkoutStatus.completed && s.completedAtUtc != null) s,
  ]..sort((a, b) => a.startedAtUtc.compareTo(b.startedAtUtc));
  final merged = <String, List<({OutsideWorkout w, int overlap})>>{};
  final standalone = <OutsideWorkout>[];
  for (final w in outside) {
    WorkoutSessionRecord? best;
    var bestOverlap = 0;
    for (final s in done) {
      final end = s.completedAtUtc!;
      final overlap = _overlapMs(w.start, w.end, s.startedAtUtc, end);
      final shorter = [
        w.end.difference(w.start).inMilliseconds,
        end.difference(s.startedAtUtc).inMilliseconds,
      ].reduce((a, b) => a < b ? a : b);
      if (overlap <= 0 || shorter <= 0 || overlap * 2 < shorter) continue;
      if (overlap > bestOverlap) {
        best = s;
        bestOverlap = overlap;
      }
    }
    if (best == null) {
      standalone.add(w);
    } else {
      merged.putIfAbsent(best.uuid, () => []).add((w: w, overlap: bestOverlap));
    }
  }
  standalone.sort((a, b) => b.start.compareTo(a.start));
  return WorkoutMerge(
    mergedIntoSession: {
      for (final e in merged.entries)
        e.key: [for (final x in _byOverlap(e.value)) x.w],
    },
    standalone: standalone,
  );
}

List<({OutsideWorkout w, int overlap})> _byOverlap(
  List<({OutsideWorkout w, int overlap})> items,
) {
  final indexed = items.indexed.toList()
    ..sort((a, b) {
      final c = b.$2.overlap.compareTo(a.$2.overlap);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final i in indexed) i.$2];
}

({String source, double? kcal})? mergedSummary(List<OutsideWorkout> merged) {
  if (merged.isEmpty) return null;
  double? kcal;
  for (final w in merged) {
    final k = w.activeKcal;
    if (k != null) kcal = (kcal ?? 0) + k;
  }
  return (source: merged.first.source, kcal: kcal);
}
