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
