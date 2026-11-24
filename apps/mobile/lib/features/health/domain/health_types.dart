/// A per-day value; `day` is a local date at 00:00.
typedef DayValue = ({DateTime day, double value});

typedef HealthSample = ({
  DateTime from,
  DateTime to,
  double value,
  String source,
});

enum SleepStage { awake, light, deep, rem, asleepUnspecified, inBed }

/// [source] is the name shown to the user; [sourceKey] tells writing apps
/// and devices apart (several can share one shown name) and is never shown.
typedef SleepSegment = ({
  DateTime from,
  DateTime to,
  SleepStage stage,
  String source,
  String sourceKey,
});
