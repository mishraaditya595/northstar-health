import 'package:flutter/material.dart' hide Baseline;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/design/charts/bar_series.dart';
import '../../../core/design/charts/score_ring.dart';
import '../../../core/design/charts/trend_label.dart';
import '../application/health_details.dart';
import '../application/health_overview.dart';
import '../domain/energy.dart';
import '../domain/metric_explanations.dart';
import '../domain/readiness.dart';
import '../domain/trend.dart';
import '../health_format.dart';
import '../widgets/detail_layout.dart';
import '../widgets/energy_text.dart';
import '../widgets/health_card_frame.dart';
import '../widgets/metric_info_sheet.dart';
import '../widgets/readiness_card.dart';

const _reference = 70;
const _sleepReference = Duration(hours: 7, minutes: 30);
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Today's readiness and its parts, or 7 / 30 days of it; read fresh and
/// held in memory only.
class ReadinessDetailPage extends ConsumerStatefulWidget {
  const ReadinessDetailPage({super.key});

  @override
  ConsumerState<ReadinessDetailPage> createState() =>
      _ReadinessDetailPageState();
}

class _ReadinessDetailPageState extends ConsumerState<ReadinessDetailPage> {
  /// [SleepRange.lastNight] is the Today tab.
  SleepRange _range = SleepRange.lastNight;

  /// Ranges opened on this page; their reads stay alive until it closes, so
  /// switching back does not read again.
  final _opened = <SleepRange>{};

  @override
  Widget build(BuildContext context) {
    for (final range in _opened) {
      ref.listen(readinessHistoryProvider(range), (_, _) {});
    }
    return HealthDetailScaffold(
      title: 'Energy',
      icon: Icons.bolt_outlined,
      chips: DetailRangeChips(
        options: const [
          (SleepRange.lastNight, 'Today'),
          (SleepRange.week, '7 days'),
          (SleepRange.month, '30 days'),
        ],
        selected: _range,
        onSelected: (range) => setState(() {
          _range = range;
          if (range != SleepRange.lastNight) _opened.add(range);
        }),
      ),
      builder: (overview) {
        final now = ref.watch(localNowProvider);
        void retry() => ref.read(healthOverviewProvider.notifier).refresh();
        Widget unavailable(MetricGap gap) => DetailPanel(
          children: [
            DetailUnavailable(
              gap: gap,
              metricName: 'Energy',
              platform: overview.platform,
              onRetry: retry,
            ),
          ],
        );
        final today = currentEnergy(overview, now);
        // An earlier day's energy is never shown as today's: wait for the
        // re-read, or offer to try again.
        if (today == null && hasStaleEnergy(overview, now)) {
          return ref.watch(healthOverviewProvider).isLoading
              ? const DetailLoading()
              : unavailable(MetricGap.failed);
        }
        return switch (overview.energy) {
          SectionGap(gap: MetricGap.noData) => ReadinessCard(
            overview: overview,
            now: now,
          ),
          SectionGap(:final gap) => unavailable(gap),
          SectionData() =>
            _range == SleepRange.lastNight
                ? _Today(overview: overview, energy: today!, now: now)
                : _RangeView(overview: overview, range: _range),
        };
      },
    );
  }
}

class _Today extends StatelessWidget {
  const _Today({
    required this.overview,
    required this.energy,
    required this.now,
  });

  final HealthOverview overview;
  final EnergyOverview energy;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final start = energy.start;
    final hrvName = readinessHrvName(start.hrvIsSdnn);
    final current = energy.energy;
    return DetailPanels(
      children: [
        ...switch ((current, start.result)) {
          (final e?, ReadinessReady(:final readiness)) => [
            _summary(context, e),
            _changes(context, e),
            _parts(context, start, readiness, hrvName),
          ],
          // The card's copy for what is missing.
          _ => [
            ReadinessCard(overview: overview, now: now),
            const SizedBox(height: 12),
          ],
        },
        DetailPanel(
          title: 'How energy works',
          info: metricInfoButton(
            context,
            MetricKey.readiness,
            platform: overview.platform,
          ),
          children: [
            HealthCaption(
              'Energy starts each day from your recovery when you wake: '
              "today's $hrvName and resting heart rate against your own "
              'normal (their average over the 30 days before), last '
              "night's sleep, your sleep over the past week and your recent "
              'training load. A measure counts once it has 3 days of data. '
              'Until it has 14, and until you have logged 20 workouts in '
              'BeyondRep, the score is still learning. Through the day '
              'energy goes down with each workout you finish, with active '
              'calories above your usual for that hour, and a little with '
              'long hours awake; a nap adds a few points back. Your day '
              'runs from waking to your next main sleep, so a late session '
              'counts for the day you are still awake in. The 7 and 30 day '
              'comparison scores the days before the period without sleep '
              'heart rate. Once you have 20 workouts and 14 days of data, '
              'BeyondRep tunes how much workouts and active calories lower '
              'your energy from how you trained at different energy levels, '
              'and learns the hours you usually train, when time awake costs '
              'nothing. This is worked out on your phone each time and never '
              'saved. Energy is a suggestion for planning your '
              'training, not medical advice.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _summary(BuildContext context, Energy e) {
    final theme = Theme.of(context);
    final learning = energyLearningText(energy.learning);
    return DetailPanel(
      children: [
        Row(
          children: [
            NsScoreRing(
              value: e.value,
              size: 88,
              color: readinessBandColor(theme, e.band),
              caption: 'Energy',
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                readinessBandWords(e.band),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        HealthCaption(energyChangeText(e)),
        if (e.tuned) const HealthCaption('Tuned to your last 90 days.'),
        if (learning != null) HealthCaption(learning),
      ],
    );
  }

  Widget _changes(BuildContext context, Energy e) {
    final wake = energy.wake;
    return DetailPanel(
      title: 'Since you woke',
      trailing: wake == null
          ? null
          : 'Woke at ${formatClockTime(wake.toLocal())}',
      children: [
        for (final i in e.items)
          DetailRow(energyItemLabel(i), energyPointsText(i.points)),
        if (e.items.any((i) => i.kind == EnergyItemKind.nap && i.capped))
          const HealthCaption(
            'Naps add back up to 10 points, and never more than the day has '
            'used.',
          ),
        if (e.awakeWaived)
          const HealthCaption(
            'You usually train around now, so time awake costs nothing '
            'today.',
          ),
        if (e.items.isEmpty)
          const HealthCaption(
            'Nothing has changed your energy since you woke.',
          ),
      ],
    );
  }

  Widget _parts(
    BuildContext context,
    ReadinessOverview readiness,
    Readiness r,
    String hrvName,
  ) {
    final heart = switch (overview.heart) {
      SectionData(:final value) => value,
      SectionGap() => null,
    };
    final sleep = switch (overview.sleep) {
      SectionData(:final value) => value,
      SectionGap() => null,
    };
    final parts = {for (final p in r.parts) p.input: p};
    String normal(Baseline? b, String unit) => b == null
        ? ''
        : ' · your normal ${(b.mean - b.sd).round()}–'
              '${(b.mean + b.sd).round()} $unit';
    String share(ReadinessPart p) =>
        '${(100 * p.weight).round()}% of the score';
    final asleep = sleep == null
        ? null
        : formatDuration(sleep.lastNight.asleep);
    final weekAverage = sleep?.vsWeek == null
        ? null
        : formatDuration(
            Duration(
              minutes: (sleep!.lastNight.asleep.inMinutes - sleep.vsWeek!.delta)
                  .round(),
            ),
          );

    String? today(ReadinessInput input) => switch (input) {
      ReadinessInput.hrv => switch (heart?.hrv) {
        final v? =>
          '${v.value.round()} ms today'
              '${normal(readiness.hrvBaseline, 'ms')}',
        null => null,
      },
      ReadinessInput.restingHr => switch (heart?.restingHr) {
        final v? =>
          '${v.value.round()} bpm today'
              '${normal(readiness.restingHrBaseline, 'bpm')}',
        null => null,
      },
      ReadinessInput.sleep => switch (sleep?.score) {
        final s? => '$asleep asleep · sleep score ${s.value}',
        null => '$asleep asleep vs ${formatDuration(_sleepReference)}',
      },
      ReadinessInput.sleepDebt =>
        weekAverage == null
            ? '$asleep asleep'
            : '$asleep vs $weekAverage 7-night average',
      ReadinessInput.trainingLoad =>
        r.loadRatio == null
            ? null
            : 'Last 7 days at ${(r.loadRatio! * 100).round()}% of your usual',
    };
    String whyNot(ReadinessInput input) => switch (input) {
      ReadinessInput.hrv =>
        readiness.hasHrv
            ? 'Your normal needs 3 days of HRV in the last 30.'
            : 'No HRV today yet.',
      ReadinessInput.restingHr =>
        readiness.hasRestingHr
            ? 'Your normal needs 3 days of resting HR in the last 30.'
            : 'No resting HR today yet.',
      ReadinessInput.sleep => 'No sleep last night.',
      ReadinessInput.sleepDebt => 'Needs 3 nights in the week before.',
      ReadinessInput.trainingLoad => 'Needs 14 days of workout history and some training in the last 28 days.',
    };
    final names = {
      ReadinessInput.hrv: hrvName,
      ReadinessInput.restingHr: 'Resting HR',
      ReadinessInput.sleep: 'Sleep',
      ReadinessInput.sleepDebt: 'Sleep vs your week',
      ReadinessInput.trainingLoad: 'Training load',
    };
    // HRV and resting HR say when their usual range will appear.
    Widget about(ReadinessInput input) => metricInfoButton(
      context,
      switch (input) {
        ReadinessInput.hrv => MetricKey.hrv,
        ReadinessInput.restingHr => MetricKey.restingHeartRate,
        ReadinessInput.sleep ||
        ReadinessInput.sleepDebt => MetricKey.timeAsleep,
        ReadinessInput.trainingLoad => MetricKey.trainingLoad,
      },
      platform: overview.platform,
      showUsualPlaceholder:
          input == ReadinessInput.hrv || input == ReadinessInput.restingHr,
    );
    return DetailPanel(
      title: 'Why you started at ${r.value}',
      children: [
        for (final input in ReadinessInput.values)
          if (input == ReadinessInput.trainingLoad && parts[input] == null)
            const SizedBox.shrink()
          else if (parts[input] case final p?) ...[
            DetailRow(names[input]!, '${p.score.round()}', info: about(input)),
            HealthCaption([?today(input), share(p)].join(' · ')),
            const SizedBox(height: 6),
          ] else ...[
            DetailRow(names[input]!, 'Not counted', info: about(input)),
            HealthCaption(whyNot(input)),
            const SizedBox(height: 6),
          ],
      ],
    );
  }
}

class _RangeView extends ConsumerWidget {
  const _RangeView({required this.overview, required this.range});

  final HealthOverview overview;
  final SleepRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(readinessHistoryProvider(range));
    // While a reload (e.g. after an account switch) runs, the previous value
    // is not shown.
    final history = async.isLoading ? null : async.value;
    if (!async.isLoading && async.hasError) {
      return DetailPanel(
        children: [
          DetailUnavailable(
            gap: MetricGap.failed,
            metricName: 'Energy',
            platform: overview.platform,
            // Its own reads are guarded: a failure comes from the sleep
            // range providers it builds on.
            onRetry: () => ref
              ..invalidate(sleepRangeNightsProvider(range))
              ..invalidate(sleepRangeHrProvider(range))
              ..invalidate(readinessHistoryProvider(range)),
          ),
        ],
      );
    }
    if (history == null) return const DetailLoading();
    final theme = Theme.of(context);
    final days = range.nights;
    final first = currentRangeStart(overview.readAt, range);
    int? value(ReadinessDay d) => switch (d.result) {
      ReadinessReady(:final readiness) => readiness.value,
      ReadinessNotReady() => null,
    };
    final current = [
      for (final d in history)
        if (!d.day.isBefore(first)) value(d),
    ];
    final scored = current.nonNulls.toList();
    final previous = [
      for (final d in history)
        if (d.day.isBefore(first)) ?value(d),
    ];
    double? mean(List<int> v) =>
        v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
    final avg = mean(scored);
    final previousAvg = previous.length >= 5 ? mean(previous) : null;
    final trend = avg == null || previousAvg == null
        ? null
        : trendOf(TrendMetric.readiness, avg, previousAvg);
    final avgText = avg?.round().toString();
    final label =
        '${formatHealthDate(first)} – ${formatHealthDate(overview.readAt)}';
    final count = 'Scored on ${scored.length} of $days days';
    return DetailPanel(
      title: 'Starting energy',
      trailing: label,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 8,
          runSpacing: 2,
          children: [
            HealthValue(avgText, unit: 'avg'),
            if (trend != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _trendLabel(trend, days),
              ),
          ],
        ),
        HealthCaption(
          avg == null ? 'No starting energy in these $days days.' : count,
        ),
        const SizedBox(height: 10),
        NsBarChart(
          bars: [
            for (final (i, v) in current.indexed)
              NsBar(
                highlight: i == days - 1,
                segments: v == null
                    ? const []
                    : [
                        (
                          value: v.toDouble(),
                          color: readinessBandColor(theme, readinessBandOf(v)),
                        ),
                      ],
              ),
          ],
          referenceValue: _reference.toDouble(),
          referenceLabel: readinessBandWords(ReadinessBand.good),
          axisLabels: range == SleepRange.week
              ? [
                  for (var i = 0; i < days; i++)
                    _weekdays[DateTime(
                          first.year,
                          first.month,
                          first.day + i,
                        ).weekday -
                        1],
                ]
              : const [],
          semanticsLabel:
              'Starting energy, $label. '
              '${avgText == null ? 'No days scored' : 'Average $avgText. $count'}. '
              'Dashed line at $_reference, good to train.',
        ),
        const SizedBox(height: 6),
        const HealthCaption('Dashed line: $_reference, good to train'),
      ],
    );
  }

  Widget _trendLabel(TrendResult trend, int days) {
    final t = nsTrendOf(trend);
    return NsTrendLabel(
      direction: t.direction,
      tone: t.tone,
      text: trend.direction == TrendDirection.flat
          ? 'same as previous $days days'
          : '${trend.delta.abs().round()} vs previous $days days',
    );
  }
}
