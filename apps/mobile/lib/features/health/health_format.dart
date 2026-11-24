import '../../core/design/charts/trend_label.dart';
import '../../core/design/stats.dart';
import 'data/health_reader.dart';
import 'domain/trend.dart';

const _dash = '—';
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

String healthMetricLabel(HealthMetric metric, {bool compact = false}) =>
    switch (metric) {
      HealthMetric.sleep => 'Sleep',
      HealthMetric.steps => 'Steps',
      HealthMetric.restingHeartRate =>
        compact ? 'Resting HR' : 'Resting heart rate',
      HealthMetric.weight => 'Weight',
    };

String healthPlatformName(HealthPlatformKind platform) => switch (platform) {
  HealthPlatformKind.appleHealth => 'Apple Health',
  HealthPlatformKind.healthConnect => 'Health Connect',
};

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
String formatTrend(TrendMetric metric, TrendResult trend) {
  final d = trend.delta.abs();
  if (trend.direction == TrendDirection.flat) {
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
String formatTrendSpoken(TrendMetric metric, TrendResult trend) {
  final word = switch (trend.direction) {
    TrendDirection.up => 'up',
    TrendDirection.down => 'down',
    TrendDirection.flat => 'no change,',
  };
  return '$word ${formatTrend(metric, trend)}';
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
NsTrendLabel healthTrendLabel(TrendMetric metric, TrendResult trend) {
  final t = nsTrendOf(trend);
  return NsTrendLabel(
    direction: t.direction,
    tone: t.tone,
    text: formatTrend(metric, trend),
  );
}

String _grouped(int n) => n.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

/// Value text for a card. Anything that is not a measurement shows a dash,
/// never `0`.
String formatHealthValue(HealthMetric metric, HealthReading reading) {
  if (reading is! HealthMeasured) return _dash;
  final v = reading.value;
  return switch (metric) {
    HealthMetric.sleep => () {
      final minutes = v.round();
      final h = minutes ~/ 60;
      final m = minutes % 60;
      return h == 0 ? '${m}m' : '${h}h ${m}m';
    }(),
    HealthMetric.steps => _grouped(v.round()),
    HealthMetric.restingHeartRate => '${v.round()} bpm',
    HealthMetric.weight => '${v.toStringAsFixed(1)} kg',
  };
}

/// Caption under the value: source and time, or the reason it is empty.
String formatHealthCaption(
  HealthMetric metric,
  HealthReading reading,
  HealthPlatformKind platform,
  DateTime now,
) {
  switch (reading) {
    case HealthMeasured():
      final at = reading.measuredAt;
      return switch (metric) {
        HealthMetric.sleep => '${reading.source} · ended ${_time(at)}',
        HealthMetric.steps =>
          '${healthPlatformName(platform)} · as of ${_time(now)}',
        HealthMetric.restingHeartRate =>
          at.year == now.year && at.month == now.month && at.day == now.day
              ? '${reading.source} · today ${_time(at)}'
              : '${reading.source} · ${_date(at)}',
        HealthMetric.weight => '${reading.source} · ${_date(at)}',
      };
    case HealthNoData():
      return switch (metric) {
        HealthMetric.sleep => 'No sleep recorded last night',
        HealthMetric.steps => 'No steps yet today',
        HealthMetric.restingHeartRate => 'None in the last 7 days',
        HealthMetric.weight => 'None in the last 30 days',
      };
    case HealthNotAllowed():
      return 'Not allowed · Manage';
    case HealthReadFailed():
      return "Couldn't read · Try again";
    case HealthUnsupported():
      return 'Not available on this device';
  }
}

/// True when the card shows "no data": a no-data reading, or iOS steps of 0
/// (iOS cannot tell a denied read from nothing, so 0 steps is no data).
bool isHealthNoData(
  HealthMetric metric,
  HealthReading reading,
  HealthPlatformKind platform,
) =>
    reading is HealthNoData ||
    (platform == HealthPlatformKind.appleHealth &&
        metric == HealthMetric.steps &&
        reading is HealthMeasured &&
        reading.value == 0);
