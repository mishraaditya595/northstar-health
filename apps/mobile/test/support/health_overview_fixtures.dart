import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:beyondrep/features/health/domain/sleep_nights.dart';
import 'package:beyondrep/features/health/domain/sleep_score.dart';
import 'package:beyondrep/features/health/domain/trend.dart';

/// Synthetic overviews for widget tests; read at 24 Nov 2026, 7:42 AM.
final overviewReadAt = DateTime(2026, 11, 24, 7, 42);

List<DayValue> daily(int days, double Function(int i) value) => [
  for (var i = 0; i < days; i++)
    (day: DateTime(2026, 11, 24 - days + 1 + i), value: value(i)),
];

SleepNight night({
  DateTime? date,
  int asleep = 372,
  int deep = 63,
  int light = 216,
  int rem = 93,
  int awake = 22,
}) {
  final d = date ?? DateTime(2026, 11, 24);
  return SleepNight(
    date: d,
    start: DateTime(d.year, d.month, d.day - 1, 23, 48),
    end: DateTime(d.year, d.month, d.day, 6, 31),
    source: 'Apple Watch',
    segments: const [],
    asleep: Duration(minutes: asleep),
    deep: Duration(minutes: deep),
    light: Duration(minutes: light),
    rem: Duration(minutes: rem),
    awake: Duration(minutes: awake),
    inBed: null,
  );
}

SleepOverview sleepOverview(SleepNight lastNight, {bool staged = true}) =>
    SleepOverview(
      lastNight: lastNight,
      score: staged ? const SleepScore(value: 74, contributors: {}) : null,
      sleepAvgHr: staged ? 51 : null,
      nights: [lastNight],
      vsWeek: const TrendResult(
        direction: TrendDirection.down,
        tone: TrendTone.worse,
        delta: -36,
      ),
    );

final fullHeart = HeartOverview(
  restingHr: (day: DateTime(2026, 11, 24), value: 54),
  restingHrDaily: daily(30, (i) => 57 - i / 10),
  hrv: (day: DateTime(2026, 11, 24), value: 52),
  hrvDaily: daily(30, (i) => 46 + i / 5),
  vo2Max: (day: DateTime(2026, 11, 20), value: 44.1),
  vo2MaxDaily: [(day: DateTime(2026, 11, 20), value: 44.1)],
  restingHrVsMonth: const TrendResult(
    direction: TrendDirection.down,
    tone: TrendTone.better,
    delta: -3,
  ),
  hrvVsNormal: const TrendResult(
    direction: TrendDirection.up,
    tone: TrendTone.better,
    delta: 6,
  ),
  hrvIsSdnn: true,
);

final fullActivity = ActivityOverview(
  stepsToday: 8214,
  stepsDaily: daily(30, (i) => 9000 + (i % 5) * 300),
  activeEnergyToday: 412,
  activeEnergyDaily: daily(30, (i) => 400),
  stepsWeekAverage: 9480,
);

final fullBody = BodyOverview(
  weight: (day: DateTime(2026, 11, 24), value: 78.4),
  weightDaily: daily(30, (i) => 79.3 - i * 0.03),
  bodyFat: (day: DateTime(2026, 11, 22), value: 17.2),
  weightVsMonth: const TrendResult(
    direction: TrendDirection.down,
    tone: TrendTone.neutral,
    delta: -0.9,
  ),
);

HealthOverview overview({
  String ownerId = 'synthetic-owner',
  HealthPlatformKind platform = HealthPlatformKind.appleHealth,
  bool needsMoreAccess = false,
  Section<SleepOverview>? sleep,
  Section<HeartOverview>? heart,
  Section<ActivityOverview>? activity,
  Section<BodyOverview>? body,
}) => HealthOverview(
  ownerId: ownerId,
  readAt: overviewReadAt,
  platform: platform,
  readableFrom: null,
  needsMoreAccess: needsMoreAccess,
  sleep: sleep ?? SectionData(sleepOverview(night())),
  heart: heart ?? SectionData(fullHeart),
  activity: activity ?? SectionData(fullActivity),
  body: body ?? SectionData(fullBody),
);

/// iPhone without a wearable: no sleep or heart data, steps and a manual
/// weight only.
HealthOverview phoneOnly({
  HealthPlatformKind platform = HealthPlatformKind.appleHealth,
}) => overview(
  platform: platform,
  sleep: const SectionGap(MetricGap.noData),
  heart: const SectionGap(MetricGap.noData),
  activity: SectionData(
    ActivityOverview(
      stepsToday: 6930,
      stepsDaily: daily(7, (i) => 7000 + i * 100),
      activeEnergyToday: null,
      activeEnergyDaily: const [],
      stepsWeekAverage: 8050,
    ),
  ),
  body: SectionData(
    BodyOverview(
      weight: (day: DateTime(2026, 11, 20), value: 81.0),
      weightDaily: [(day: DateTime(2026, 11, 20), value: 81.0)],
      bodyFat: null,
      weightVsMonth: null,
    ),
  ),
);
