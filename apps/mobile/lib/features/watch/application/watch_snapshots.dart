import 'dart:convert';

import '../../../core/units/load_units.dart';
import '../../health/application/health_overview.dart';
import '../../health/domain/daily_series.dart';
import '../../health/domain/readiness.dart';
import '../../health/widgets/readiness_card.dart';
import '../../programs/application/program_providers.dart';
import '../../programs/domain/program_status.dart';
import '../../workouts/domain/workout_library_models.dart';
import '../../workouts/domain/workout_models.dart';
import '../domain/watch_message.dart';

/// Pure builders for the `watch_link/v1` messages the phone sends. Ids and
/// clock are passed in; nothing here reads a provider, a store or the platform.

/// WatchConnectivity payload headroom for one application context: the
/// binding, plans and health JSON together.
const watchSnapshotMaxBytes = 60000;

/// Whole milliseconds: Dart prints microseconds when it has them, and the
/// watch's date parser is only sure of three fractional digits.
String _utc(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
  t.millisecondsSinceEpoch,
  isUtc: true,
).toIso8601String();

/// Contract limits count code points, not UTF-16 units.
String _cap(String text, int max) {
  final runes = text.runes;
  return runes.length <= max ? text : String.fromCharCodes(runes.take(max));
}

String _localDate(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

AccountBinding buildAccountBinding({
  required String accountKey,
  required String unit,
  required String messageId,
  required DateTime nowUtc,
}) => AccountBinding(
  messageId: messageId,
  sentAtUtc: _utc(nowUtc),
  accountKey: accountKey,
  unit: unit,
);

AccountCleared buildAccountCleared({
  required String accountKey,
  required bool wipeUnsent,
  required String messageId,
  required DateTime nowUtc,
}) => AccountCleared(
  messageId: messageId,
  sentAtUtc: _utc(nowUtc),
  accountKey: accountKey,
  wipeUnsent: wipeUnsent,
);

/// `kg` or `lb`: the unit of the latest completed set, `kg` without history.
/// There is no separate unit setting; each set keeps the unit it was logged in.
String watchLoadUnit(List<WorkoutSessionRecord> sessions) {
  final newestFirst = [...sessions]
    ..sort((a, b) => _doneAt(b).compareTo(_doneAt(a)));
  for (final s in newestFirst) {
    for (final set in s.sets.reversed) {
      if (set.inputUnit == LoadUnit.lb) return 'lb';
      if (set.inputUnit == LoadUnit.kg) return 'kg';
    }
  }
  return 'kg';
}

DateTime _doneAt(WorkoutSessionRecord s) => s.completedAtUtc ?? s.startedAtUtc;

PlansSnapshot buildPlansSnapshot({
  required String accountKey,
  required WorkoutLibrarySnapshot library,
  required ProgramWeek? week,
  required List<WorkoutSessionRecord> recentSessions,
  required DateTime nowUtc,
  required String messageId,
  int maxBytes = watchSnapshotMaxBytes,
}) {
  final exercises = {for (final e in library.exercises) e.uuid: e};
  final completed = [
    for (final s in recentSessions)
      if (s.status == WorkoutStatus.completed) s,
  ]..sort((a, b) => _doneAt(b).compareTo(_doneAt(a)));

  // Today's program plan, when the program has a workout today.
  WorkoutPlanRecord? todayPlan;
  ProgramWeekRow? todayRow;
  if (week != null) {
    final row = week.todayRow;
    final uuid = row?.day.planUuid;
    if (row != null && row.status == ProgramDayStatus.today && uuid != null) {
      todayPlan =
          week.plans[uuid] ??
          library.plans.where((p) => p.uuid == uuid).firstOrNull;
      if (todayPlan != null && todayPlan.archivedAtMs != null) {
        todayPlan = null;
      }
      if (todayPlan != null) todayRow = row;
    }
  }

  final lastUse = <String, DateTime>{};
  for (final s in completed) {
    final plan = s.planUuid;
    if (plan != null) lastUse.putIfAbsent(plan, () => _doneAt(s));
  }
  final others = [
    for (final p in library.plans)
      if (p.archivedAtMs == null &&
          p.programUuid == null &&
          p.uuid != todayPlan?.uuid)
        p,
  ];
  others.sort((a, b) {
    final x = lastUse[a.uuid];
    final y = lastUse[b.uuid];
    if (x != null && y != null) {
      final byUse = y.compareTo(x);
      if (byUse != 0) return byUse;
    } else if (x != null || y != null) {
      return x != null ? -1 : 1;
    }
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.uuid.compareTo(b.uuid);
  });
  final ordered = [?todayPlan, ...others].take(100);

  final recent = _recentExercises(completed);

  PlansSnapshot message(List<Map<String, Object?>> plans, bool withToday) =>
      PlansSnapshot(
        messageId: messageId,
        sentAtUtc: _utc(nowUtc),
        accountKey: accountKey,
        generatedAtUtc: _utc(nowUtc),
        plans: plans,
        recentExercises: recent,
        today: withToday && todayRow != null
            ? {
                'plan_id': _cap(todayPlan!.uuid, 128),
                'program_id': _cap(week!.program.uuid, 128),
                'local_date': _localDate(week.localToday),
                'label': _cap(todayPlan.name, 120),
              }
            : null,
      );

  int size(PlansSnapshot m) => utf8.encode(jsonEncode(m.toJson())).length;

  // Add plans in order, skipping any that would pass the byte budget so a
  // single huge plan does not hide the smaller ones after it. The order is
  // fixed, so the same library always gives the same snapshot.
  final fitted = <Map<String, Object?>>[];
  for (final plan in ordered) {
    final next = [...fitted, _planJson(plan, exercises)];
    if (size(message(next, true)) > maxBytes) continue;
    fitted.add(next.last);
  }
  final todayFitted =
      todayPlan != null &&
      fitted.isNotEmpty &&
      fitted.first['plan_id'] == _cap(todayPlan.uuid, 128);
  return message(fitted, todayFitted);
}

Map<String, Object?> _planJson(
  WorkoutPlanRecord plan,
  Map<String, ExerciseRecord> exercises,
) {
  final rows = [...plan.exercises]
    ..sort((a, b) => a.position.compareTo(b.position));
  return {
    'plan_id': _cap(plan.uuid, 128),
    'name': _cap(plan.name.isEmpty ? 'Plan' : plan.name, 120),
    'exercises': [
      for (final row in rows.take(40))
        () {
          final definition = exercises[row.exerciseUuid];
          final timed =
              definition?.inputMode == 'duration' ||
              row.targetDurationSeconds != null;
          final muscle = definition?.muscleGroup ?? '';
          return <String, Object?>{
            'exercise_id': _cap(row.exerciseUuid, 128),
            'name': _cap(
              (definition?.name ?? '').isEmpty ? 'Exercise' : definition!.name,
              120,
            ),
            'kind': timed ? 'duration' : 'reps',
            if (muscle.isNotEmpty) 'muscle': _cap(muscle, 60),
            'sets': [
              for (var i = 0; i < row.targetSets.clamp(0, 30); i++)
                <String, Object?>{
                  'position': i,
                  'kind': 'working',
                  if (!timed && row.targetRepsMin != null)
                    'target_reps': row.targetRepsMin,
                  if (row.targetDurationSeconds != null)
                    'target_seconds': row.targetDurationSeconds,
                  if (row.restSeconds != null) 'rest_seconds': row.restSeconds,
                },
            ],
          };
        }(),
    ],
  };
}

/// The last 30 distinct exercises of [newestFirst] completed sessions.
List<Map<String, Object?>> _recentExercises(
  List<WorkoutSessionRecord> newestFirst,
) {
  final seen = <String>{};
  final out = <Map<String, Object?>>[];
  for (final session in newestFirst) {
    final rows = [...session.exercises]
      ..sort((a, b) => a.position.compareTo(b.position));
    for (final e in rows) {
      final id = e.definitionUuid ?? e.uuid;
      if (e.nameSnapshot.isEmpty || !seen.add(id)) continue;
      final timed = session.sets.any(
        (s) => s.exerciseUuid == e.uuid && s.durationSeconds != null,
      );
      out.add({
        'exercise_id': _cap(id, 128),
        'name': _cap(e.nameSnapshot, 120),
        'kind': timed ? 'duration' : 'reps',
      });
      if (out.length == 30) return out;
    }
  }
  return out;
}

/// Today's numbers for the watch, or null without an overview read on
/// [localNow]'s date. A value is sent only when the phone has it for today:
/// a missing one is left out, never sent as 0.
HealthSnapshot? buildHealthSnapshot({
  required String accountKey,
  required HealthOverview? overview,
  required DateTime localNow,
  required String messageId,
}) {
  if (overview == null) return null;
  final today = dayOf(localNow);
  if (dayOf(overview.readAt) != today) return null;

  Map<String, Object?>? readiness;
  final scored = todaysReadiness(overview, localNow);
  if (scored != null && scored.result is ReadinessReady) {
    final r = (scored.result as ReadinessReady).readiness;
    final headline = readinessBandWords(r.band);
    final reason = readinessReasons(overview, scored, r);
    readiness = {
      'score': r.value.clamp(0, 100),
      'band': switch (r.band) {
        ReadinessBand.good => 'good',
        ReadinessBand.fair => 'fair',
        ReadinessBand.low => 'low',
      },
      'headline': _cap(headline, 60),
      'reason': _cap(reason.isEmpty ? headline : reason, 140),
    };
  }

  Map<String, Object?>? sleep;
  if (overview.sleep case SectionData(:final value)
      when dayOf(value.lastNight.date) == today) {
    final night = value.lastNight;
    sleep = {
      'score': ?value.score?.value,
      'asleep_minutes': night.asleep.inMinutes,
      if (night.hasStages) 'deep_minutes': night.deep.inMinutes,
      if (night.hasStages) 'rem_minutes': night.rem.inMinutes,
    };
  }

  int? restingHr;
  int? hrv;
  bool? sdnn;
  if (overview.heart case SectionData(:final value)) {
    final rhr = value.restingHr;
    if (rhr != null && dayOf(rhr.day) == today) restingHr = rhr.value.round();
    final h = value.hrv;
    if (h != null && dayOf(h.day) == today) {
      hrv = h.value.round();
      sdnn = value.hrvIsSdnn;
    }
  }

  int? steps;
  int? energy;
  if (overview.activity case SectionData(:final value)) {
    steps = value.stepsToday?.round();
    energy = value.activeEnergyToday?.round();
  }

  return HealthSnapshot(
    messageId: messageId,
    sentAtUtc: _utc(localNow),
    accountKey: accountKey,
    localDate: _localDate(today),
    asOfUtc: _utc(overview.readAt),
    readiness: readiness,
    sleep: sleep,
    restingHrBpm: restingHr,
    hrvMs: hrv,
    hrvKind: sdnn == null ? null : (sdnn ? 'sdnn' : 'rmssd'),
    steps: steps,
    activeEnergyKcal: energy,
  );
}
