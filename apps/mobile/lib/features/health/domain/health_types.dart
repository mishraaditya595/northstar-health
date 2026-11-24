/// A per-day value; `day` is a local date at 00:00.
typedef DayValue = ({DateTime day, double value});

typedef HealthSample = ({
  DateTime from,
  DateTime to,
  double value,
  String source,
});

enum SleepStage { awake, light, deep, rem, asleepUnspecified, inBed }

typedef SleepSegment = ({
  DateTime from,
  DateTime to,
  SleepStage stage,
  String source,
});
