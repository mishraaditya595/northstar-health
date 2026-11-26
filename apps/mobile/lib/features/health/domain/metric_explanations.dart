import 'health_types.dart';
import 'readiness.dart';

/// Every metric the app explains in plain words.
enum MetricKey {
  readiness,
  sleepScore,
  timeAsleep,
  deepSleep,
  lightSleep,
  remSleep,
  awake,
  sleepHeartRate,
  respiratoryRate,
  bloodOxygen,
  wristTemperature,
  restingHeartRate,
  hrv,
  vo2Max,
  walkingHeartRate,
  steps,
  activeCalories,
  weight,
  bodyFat,
  muscleRecovery,
}

/// Plain-language copy for one metric. [summary] is the glossary line.
class MetricExplanation {
  const MetricExplanation({
    required this.title,
    required this.summary,
    required this.what,
    required this.tells,
    required this.inBeyondRep,
  });

  final String title;
  final String summary;
  final String what;
  final String tells;
  final String inBeyondRep;
}

/// Copy for [key]; Apple Health calls light sleep "Core", Health Connect
/// calls it "Light".
MetricExplanation explanationFor(MetricKey key, HealthPlatformKind platform) {
  final copy = _copy[key]!;
  if (key == MetricKey.lightSleep) {
    return MetricExplanation(
      title: platform == HealthPlatformKind.appleHealth
          ? 'Core sleep'
          : 'Light sleep',
      summary: copy.summary,
      what: copy.what,
      tells: copy.tells,
      inBeyondRep: copy.inBeyondRep,
    );
  }
  return copy;
}

/// The user's usual range for a metric. With [dailyAverage] true, [low] and
/// [high] are both the average and there is no [today] marker.
class MetricUsual {
  const MetricUsual({
    required this.low,
    required this.high,
    this.today,
    this.dailyAverage = false,
  });

  final double low;
  final double high;
  final double? today;
  final bool dailyAverage;
}

/// Mean plus or minus one sd of the 30 days before [today]; null with fewer
/// than 14 of them. Today's own value never enters the baseline.
MetricUsual? usualFrom(
  List<DayValue> daily,
  DateTime today, {
  double? todayValue,
}) {
  final base = baselineOf(daily, today, sdFloor: (_) => 0);
  if (base == null) return null;
  return MetricUsual(
    low: base.mean - base.sd,
    high: base.mean + base.sd,
    today: todayValue,
  );
}

/// Mean of the 30 days before [today] for metrics that build up through the
/// day (steps, active calories); null with fewer than 14 days.
MetricUsual? dailyAverageFrom(List<DayValue> daily, DateTime today) {
  final base = baselineOf(daily, today, sdFloor: (_) => 0);
  if (base == null) return null;
  return MetricUsual(low: base.mean, high: base.mean, dailyAverage: true);
}

const _copy = <MetricKey, MetricExplanation>{
  MetricKey.readiness: MetricExplanation(
    title: 'Readiness',
    summary: 'How ready your body is to train today',
    what: 'A 0 to 100 score for today, worked out on your phone from your HRV, resting heart rate, last night\'s sleep and your sleep over the past week.',
    tells: '70 and up is Good: train as planned. 50 to 69 is Fair: train, but watch your effort. Under 50 is Low: consider an easier session. It compares you only with your own last 30 days.',
    inBeyondRep: 'Shown on Today, Health and Train. It never changes your plans. It is guidance, not medical advice.',
  ),
  MetricKey.sleepScore: MetricExplanation(
    title: 'Sleep score',
    summary: 'Our 0 to 100 view of last night',
    what: 'A score for last night from how long you slept, your deep and REM sleep, time awake in bed, how regular your bedtime was and your sleeping heart rate.',
    tells: 'Higher means more restful sleep. One poor night is normal; look at the trend over a week.',
    inBeyondRep: 'Feeds readiness. Without a sleep score, readiness uses your time asleep instead.',
  ),
  MetricKey.timeAsleep: MetricExplanation(
    title: 'Time asleep',
    summary: 'Hours you were actually asleep',
    what:
        'The time you were asleep last night, not counting time awake in bed.',
    tells: 'Most adults need around 7 to 9 hours. Short nights add up and lower readiness over the week.',
    inBeyondRep:
        'Feeds readiness, both last night and your average over the past week.',
  ),
  MetricKey.deepSleep: MetricExplanation(
    title: 'Deep sleep',
    summary: 'Repair and recovery',
    what: 'The slowest, most restful stage of sleep. Your body does much of its physical repair here.',
    tells: 'Most adults spend about 15 to 25% of the night in deep sleep. It tends to drop after late meals, alcohol or a late hard workout.',
    inBeyondRep: 'Part of your sleep score.',
  ),
  MetricKey.lightSleep: MetricExplanation(
    title: 'Core sleep / Light sleep',
    summary: 'Light sleep, most of the night',
    what: 'The lighter stage you spend most of the night in, moving between deep and REM sleep. Apple Health calls it Core sleep and Health Connect calls it Light sleep; they are the same stage.',
    tells: 'Usually about half the night or more. That is normal and useful sleep.',
    inBeyondRep: 'Counts towards time asleep.',
  ),
  MetricKey.remSleep: MetricExplanation(
    title: 'REM sleep',
    summary: 'Dreaming, memory and learning',
    what: 'The stage when most dreaming happens. It helps with memory and learning, and comes in longer stretches towards morning.',
    tells: 'Cutting a night short usually cuts REM sleep the most.',
    inBeyondRep: 'Part of your sleep score.',
  ),
  MetricKey.awake: MetricExplanation(
    title: 'Awake',
    summary: 'Short wake-ups in the night',
    what: 'Time awake after you first fell asleep.',
    tells:
        'A few short wake-ups are normal and you usually won\'t remember them.',
    inBeyondRep: 'Lowers your sleep score when there is a lot of it.',
  ),
  MetricKey.sleepHeartRate: MetricExplanation(
    title: 'Sleeping heart rate',
    summary: 'Your average heart rate while asleep',
    what: 'Your average heart rate during last night\'s sleep.',
    tells: 'It is usually lower than your daytime resting heart rate. A higher than usual night can follow alcohol, a late meal, illness or hard training.',
    inBeyondRep: 'Part of your sleep score.',
  ),
  MetricKey.respiratoryRate: MetricExplanation(
    title: 'Respiratory rate',
    summary: 'Breaths per minute while asleep',
    what: 'How many breaths you take per minute while asleep.',
    tells: 'It stays steady from night to night for most people, so a change from your usual is what matters.',
    inBeyondRep: 'Shown on Sleep details only.',
  ),
  MetricKey.bloodOxygen: MetricExplanation(
    title: 'Blood oxygen',
    summary: 'Oxygen in your blood',
    what: 'The share of oxygen your blood is carrying, measured by your watch.',
    tells: 'Readings are usually in the mid to high 90s. Watch readings can be off if the fit is loose. This is not a medical measurement.',
    inBeyondRep: 'Shown on Sleep details only.',
  ),
  MetricKey.wristTemperature: MetricExplanation(
    title: 'Wrist temperature',
    summary: 'Change in skin temperature while asleep',
    what: 'How your wrist temperature during sleep differs from your usual.',
    tells: 'Small changes are normal. Changes can follow illness, alcohol, a warm room or your cycle.',
    inBeyondRep: 'Shown on Sleep details only.',
  ),
  MetricKey.restingHeartRate: MetricExplanation(
    title: 'Resting heart rate',
    summary: 'Beats a minute at full rest',
    what: 'How many times your heart beats in a minute when you\'re fully at rest. Your watch measures it while you\'re still or asleep.',
    tells: 'Lower than your usual often means you\'re well recovered. Five or more beats above your usual can come from poor sleep, stress, alcohol, illness or a hard training block.',
    inBeyondRep: 'One of the inputs to readiness, compared only with your own last 30 days.',
  ),
  MetricKey.hrv: MetricExplanation(
    title: 'Heart rate variability (HRV)',
    summary: 'Small changes in time between heartbeats',
    what: 'The tiny differences in time from one heartbeat to the next. Apple and Android measure it in different ways, so the numbers can\'t be compared between phones or with other people.',
    tells: 'Higher than your usual generally means you\'re rested; lower can mean stress, poor sleep, illness or hard training. Only your own trend matters.',
    inBeyondRep: 'The biggest input to readiness, compared only with your own last 30 days.',
  ),
  MetricKey.vo2Max: MetricExplanation(
    title: 'VO₂ max',
    summary: 'Your aerobic fitness',
    what: 'An estimate of how much oxygen your body can use during hard exercise, made by your watch from walks and runs.',
    tells: 'Higher means fitter. It changes slowly over weeks, so look at the trend.',
    inBeyondRep: 'Shown on Heart details. Not part of readiness.',
  ),
  MetricKey.walkingHeartRate: MetricExplanation(
    title: 'Walking heart rate',
    summary: 'Average heart rate while walking',
    what: 'Your average heart rate during everyday walking.',
    tells: 'Going down over weeks often means your fitness is improving.',
    inBeyondRep: 'Shown on Heart details only.',
  ),
  MetricKey.steps: MetricExplanation(
    title: 'Steps',
    summary: 'Steps taken today',
    what: 'Steps counted by your phone or watch today.',
    tells: 'Steps add up over the day, so the morning number is always low. Your daily average is a better guide than any one day.',
    inBeyondRep: 'Shown on Today and Activity. Not part of readiness.',
  ),
  MetricKey.activeCalories: MetricExplanation(
    title: 'Active calories',
    summary: 'Energy burned by moving',
    what: 'Energy you burned by moving and exercising today, on top of what your body uses at rest.',
    tells: 'Like steps, it adds up through the day. Watch estimates can be off, so compare with your own average.',
    inBeyondRep: 'Shown on Activity. Not part of readiness.',
  ),
  MetricKey.weight: MetricExplanation(
    title: 'Weight',
    summary: 'Your latest weigh-in',
    what: 'Your most recent weight from a scale or entered by hand.',
    tells: 'Day-to-day changes of a kilo or so are mostly water. Look at the trend over weeks.',
    inBeyondRep: 'Shown on Body. Not part of readiness.',
  ),
  MetricKey.bodyFat: MetricExplanation(
    title: 'Body fat',
    summary: 'Share of your weight that is fat',
    what: 'Your most recent body fat percentage from a smart scale or other device.',
    tells: 'Home scales vary a lot between readings; the trend over weeks is more useful than one number.',
    inBeyondRep: 'Shown on Body. Not part of readiness.',
  ),
  MetricKey.muscleRecovery: MetricExplanation(
    title: 'Muscle recovery',
    summary: 'Which muscles are still recovering',
    what: 'How recently each muscle group was worked, from the sets you logged in BeyondRep. Small muscles recover in about 48 hours and larger ones in about 72.',
    tells: 'Shaded muscles are still recovering. Training them hard again soon is fine now and then, but recovered muscles are the better fit today.',
    inBeyondRep: 'Used for the "Better fit today" suggestion on Train. Uses only your logged workouts.',
  ),
};
