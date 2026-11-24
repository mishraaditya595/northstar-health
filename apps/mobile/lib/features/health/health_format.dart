import 'data/health_reader.dart';

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
