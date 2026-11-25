import '../../core/design/charts/trend_label.dart';
import '../../core/design/stats.dart';
import 'data/health_reader.dart';
import 'domain/trend.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String healthPlatformName(HealthPlatformKind platform) => switch (platform) {
  HealthPlatformKind.appleHealth => 'Apple Health',
  HealthPlatformKind.healthConnect => 'Health Connect',
};

/// Apple Health calls light sleep "Core"; Health Connect calls it "Light".
String lightStageName(HealthPlatformKind p) =>
    p == HealthPlatformKind.appleHealth ? 'Core' : 'Light';

String _time(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
}

String _date(DateTime t) => '${t.day} ${_months[t.month - 1]}';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// `24 Nov`.
String formatHealthDate(DateTime t) => _date(t);

/// `3:10 AM`.
String formatClockTime(DateTime t) => _time(t);

/// `11:48 PM – 6:31 AM`.
String formatTimeRange(DateTime from, DateTime to) =>
    '${_time(from)} – ${_time(to)}';

/// `Tue 24 Nov · Apple Health · updated 7:42 AM`.
String formatOverviewDateLine(DateTime readAt, HealthPlatformKind platform) =>
    '${_weekdays[readAt.weekday - 1]} ${_date(readAt)} · '
    '${healthPlatformName(platform)} · updated ${_time(readAt)}';

/// `6h 12m`, `1h 03m`, `45m`.
String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return h == 0 ? '${m}m' : '${h}h ${m.toString().padLeft(2, '0')}m';
}

/// `8,214`.
String formatCount(double v) => _grouped(v.round());

/// Size of the change plus what it is compared with, without the arrow
/// ([NsTrendLabel] adds it): `36m vs 7-day avg`, `3 bpm this month · better`.
/// [since] replaces a weight's "in 30 days" with the compared reading's date.
String formatTrend(TrendMetric metric, TrendResult trend, {DateTime? since}) {
  final d = trend.delta.abs();
  if (trend.direction == TrendDirection.flat) {
    if (since != null) return 'steady since ${_date(since)}';
    return switch (metric) {
      TrendMetric.sleepDuration => 'same as 7-day avg',
      TrendMetric.restingHr => 'steady this month',
      TrendMetric.hrv => 'at your normal',
      TrendMetric.weight => 'steady over 30 days',
      _ => 'about the same',
    };
  }
  final amount = switch (metric) {
    TrendMetric.sleepDuration ||
    TrendMetric.deep ||
    TrendMetric.rem => formatDuration(Duration(minutes: d.round())),
    TrendMetric.restingHr || TrendMetric.sleepHr => '${d.round()} bpm',
    TrendMetric.hrv => '${d.round()} ms',
    TrendMetric.vo2Max => d.toStringAsFixed(1),
    TrendMetric.steps => _grouped(d.round()),
    TrendMetric.activeEnergy => '${d.round()} kcal',
    TrendMetric.weight => '${d.toStringAsFixed(1)} kg',
    TrendMetric.bodyFat => '${d.toStringAsFixed(1)}%',
    TrendMetric.sleepScore => '${d.round()}',
  };
  final context = switch (metric) {
    _ when since != null => 'since ${_date(since)}',
    TrendMetric.sleepDuration => 'vs 7-day avg',
    TrendMetric.restingHr => 'this month',
    TrendMetric.hrv => 'vs normal',
    TrendMetric.weight => 'in 30 days',
    _ => 'vs avg',
  };
  // Lower is better for heart rates, so the arrow alone could mislead.
  final word = switch (metric) {
    TrendMetric.restingHr || TrendMetric.sleepHr =>
      trend.tone == TrendTone.better ? ' · better' : ' · worse',
    _ => '',
  };
  return '$amount $context$word';
}

/// [formatTrend] for screen readers: `down 36m vs 7-day avg`.
String formatTrendSpoken(
  TrendMetric metric,
  TrendResult trend, {
  DateTime? since,
}) {
  final word = switch (trend.direction) {
    TrendDirection.up => 'up',
    TrendDirection.down => 'down',
    TrendDirection.flat => 'no change,',
  };
  return '$word ${formatTrend(metric, trend, since: since)}';
}

/// The kit's arrow and colour for a domain trend.
({NsTrend direction, NsTrendTone tone}) nsTrendOf(TrendResult trend) => (
  direction: switch (trend.direction) {
    TrendDirection.up => NsTrend.up,
    TrendDirection.down => NsTrend.down,
    TrendDirection.flat => NsTrend.flat,
  },
  tone: switch (trend.tone) {
    TrendTone.better => NsTrendTone.better,
    TrendTone.worse => NsTrendTone.worse,
    TrendTone.neutral => NsTrendTone.neutral,
    TrendTone.same => NsTrendTone.same,
  },
);

/// Arrow + words + colour for [trend].
NsTrendLabel healthTrendLabel(
  TrendMetric metric,
  TrendResult trend, {
  DateTime? since,
}) {
  final t = nsTrendOf(trend);
  return NsTrendLabel(
    direction: t.direction,
    tone: t.tone,
    text: formatTrend(metric, trend, since: since),
  );
}

String _grouped(int n) => n.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);
