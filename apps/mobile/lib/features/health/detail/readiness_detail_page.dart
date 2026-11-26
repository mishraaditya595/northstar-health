import 'package:flutter/material.dart' hide Baseline;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/design/charts/bar_series.dart';
import '../../../core/design/charts/score_ring.dart';
import '../../../core/design/charts/trend_label.dart';
import '../application/health_details.dart';
import '../application/health_overview.dart';
import '../domain/metric_explanations.dart';
import '../domain/readiness.dart';
import '../domain/trend.dart';
import '../health_format.dart';
import '../widgets/detail_layout.dart';
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
      title: 'Readiness',
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
              metricName: 'Readiness',
              platform: overview.platform,
              onRetry: retry,
            ),
          ],
        );
        final today = todaysReadiness(overview, now);
        // An earlier day's score is never shown as today's: wait for the
        // re-read, or offer to try again.
        if (today == null && hasStaleReadiness(overview, now)) {
          return ref.watch(healthOverviewProvider).isLoading
              ? const DetailLoading()
              : unavailable(MetricGap.failed);
        }
        return switch (overview.readiness) {
          SectionGap(gap: MetricGap.noData) => ReadinessCard(
            overview: overview,
            now: now,
          ),
          SectionGap(:final gap) => unavailable(gap),
          SectionData() =>
            _range == SleepRange.lastNight
                ? _Today(overview: overview, readiness: today!, now: now)
                : _RangeView(overview: overview, range: _range),
        };
      },
    );
  }
}

class _Today extends StatelessWidget {
  const _Today({
    required this.overview,
    required this.readiness,
    required this.now,
  });

  final HealthOverview overview;
  final ReadinessOverview readiness;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final hrvName = readinessHrvName(readiness.hrvIsSdnn);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...switch (readiness.result) {
          ReadinessReady(:final readiness) => [
            _summary(context, readiness),
            _parts(context, readiness, hrvName),
          ],
          // The card's copy for what is missing.
          ReadinessNotReady() => [
            ReadinessCard(overview: overview, now: now),
            const SizedBox(height: 12),
          ],
        },
        DetailPanel(
          title: 'How readiness works',
          info: metricInfoButton(
            context,
            MetricKey.readiness,
            platform: overview.platform,
          ),
          children: [
            HealthCaption(
              "Readiness compares today's $hrvName and resting heart rate "
              'with your own normal, their average over the 30 days before '
              "today, and adds last night's sleep. A measure counts once it "
              'has 14 days of data. The 7 and 30 day comparison scores the '
              'days before the period without sleep heart rate. Readiness '
              'is a suggestion for planning your training, not medical '
              'advice.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _summary(BuildContext context, Readiness r) {
    final theme = Theme.of(context);
    return DetailPanel(
      children: [
        Row(
          children: [
            NsScoreRing(
              value: r.value,
              size: 88,
              color: readinessBandColor(theme, r.band),
              caption: 'Readiness',
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                readinessBandWords(r.band),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _parts(BuildContext context, Readiness r, String hrvName) {
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
            ? 'Your normal needs 14 days of HRV in the last 30.'
            : 'No HRV today yet.',
      ReadinessInput.restingHr =>
        readiness.hasRestingHr
            ? 'Your normal needs 14 days of resting HR in the last 30.'
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
        ReadinessInput.trainingLoad => MetricKey.readiness,
      },
      platform: overview.platform,
      showUsualPlaceholder:
          input == ReadinessInput.hrv || input == ReadinessInput.restingHr,
    );
    return DetailPanel(
      title: 'What made the score',
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
            metricName: 'Readiness',
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
      title: 'Daily readiness',
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
          avg == null ? 'No readiness score in these $days days.' : count,
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
              'Daily readiness, $label. '
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
