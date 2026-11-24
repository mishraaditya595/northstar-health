import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/charts/bar_series.dart';
import '../../../core/design/charts/line_chart.dart';
import '../../../core/design/charts/score_ring.dart';
import '../../../core/design/charts/sleep_stages.dart';
import '../../../core/design/charts/trend_label.dart';
import '../../../core/design/inputs.dart';
import '../../../core/design/page_header.dart';
import '../application/health_details.dart';
import '../application/health_overview.dart';
import '../data/health_reader.dart';
import '../domain/health_types.dart';
import '../domain/sleep_nights.dart';
import '../domain/sleep_score.dart';
import '../domain/trend.dart';
import '../health_format.dart';
import '../widgets/health_card_frame.dart';
import '../widgets/metric_unavailable.dart';

const _reference = Duration(hours: 7, minutes: 30);
const _noStages = 'Stages need a watch or ring that records them.';
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

Color _sleepColor(ThemeData theme) => theme.brightness == Brightness.dark
    ? BeyondRepPalette.sleepDark
    : BeyondRepPalette.sleepLight;

/// Apple Health calls light sleep "Core"; Health Connect calls it "Light".
String _lightName(HealthPlatformKind p) =>
    p == HealthPlatformKind.appleHealth ? 'Core' : 'Light';

String _percent(Duration part, Duration whole) => whole == Duration.zero
    ? '—'
    : '${(100 * part.inSeconds / whole.inSeconds).round()}%';

/// Last night, or 7 / 30 nights, read fresh and held in memory only.
class SleepDetailPage extends ConsumerStatefulWidget {
  const SleepDetailPage({super.key});

  @override
  ConsumerState<SleepDetailPage> createState() => _SleepDetailPageState();
}

class _SleepDetailPageState extends ConsumerState<SleepDetailPage> {
  SleepRange _range = SleepRange.lastNight;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(healthOverviewProvider);
    return Scaffold(
      appBar: AppBar(
        // Opened with go (a link) there is nothing to pop: go to Health.
        leading: NsBackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/health'),
        ),
        title: const Text('Sleep'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (range, label) in const [
                (SleepRange.lastNight, 'Last night'),
                (SleepRange.week, '7 days'),
                (SleepRange.month, '30 days'),
              ])
                NsChip(
                  label: label,
                  selected: _range == range,
                  onSelected: (_) => setState(() => _range = range),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _content(async),
        ],
      ),
    );
  }

  Widget _content(AsyncValue<HealthOverview?> async) {
    final overview = async.value;
    if (overview == null) {
      if (async.hasError) {
        return InsightCard(
          icon: Icons.bedtime_outlined,
          text: const TextSpan(text: "Couldn't read health data."),
          actionLabel: 'Try again',
          onAction: () => ref.read(healthOverviewProvider.notifier).refresh(),
        );
      }
      if (async.isLoading) return const _Loading();
      return const HealthCaption('Connect health on the Health tab first.');
    }
    return switch (overview.sleep) {
      SectionGap(:final gap) => _Panel(
        children: [
          MetricUnavailable(
            gap: gap,
            metricName: 'Sleep',
            platform: overview.platform,
            onAction: () =>
                ref.read(healthOverviewProvider.notifier).requestMoreAccess(),
          ),
        ],
      ),
      SectionData(:final value) =>
        _range == SleepRange.lastNight
            ? _LastNight(overview: overview, sleep: value)
            : _RangeView(overview: overview, sleep: value, range: _range),
    };
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: CircularProgressIndicator(),
    ),
  );
}

/// A detail card: optional heading, then [children].
class _Panel extends StatelessWidget {
  const _Panel({required this.children, this.title, this.trailing});

  final String? title;
  final String? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        // Charts and rows stay separate nodes for screen readers.
        semanticContainer: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  children: [
                    Text(
                      title!,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (trailing != null) HealthCaption(trailing!),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Label on the left, value on the right; wraps under large text.
class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small label, bold value, optional caption.
class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, [this.caption]);

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.mutedColor),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        if (caption != null) HealthCaption(caption!),
      ],
    );
  }
}

/// [children] two per row.
class _Pairs extends StatelessWidget {
  const _Pairs(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: 12),
                Expanded(
                  child: i + 1 < children.length
                      ? children[i + 1]
                      : const SizedBox(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LastNight extends ConsumerWidget {
  const _LastNight({required this.overview, required this.sleep});

  final HealthOverview overview;
  final SleepOverview sleep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = sleep.lastNight;
    if (night.date != _dayOf(overview.readAt)) {
      return _Panel(
        children: [
          const HealthValue(null),
          const SizedBox(height: 4),
          const HealthCaption('No sleep recorded last night.'),
          HealthCaption('Last recorded ${formatHealthDate(night.date)}'),
        ],
      );
    }
    final extrasAsync = ref.watch(sleepNightExtrasProvider);
    // While a reload (e.g. after an account switch) runs, the previous value
    // is not shown.
    final extras = extrasAsync.isLoading ? null : extrasAsync.value;
    final score = sleep.score;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summary(context, night, score),
        _stages(night),
        _heartRate(extrasAsync.isLoading, extras),
        if (score != null) _contributors(night, score),
        if (extras != null) ?_extras(extras),
      ],
    );
  }

  Widget _summary(BuildContext context, SleepNight night, SleepScore? score) {
    final theme = Theme.of(context);
    final inBed = night.inBed ?? night.span;
    return _Panel(
      children: [
        Row(
          children: [
            NsScoreRing(
              value: score?.value,
              size: 88,
              color: _sleepColor(theme),
              caption: 'Sleep score',
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${formatDuration(night.asleep)} asleep',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  HealthCaption(
                    'In bed ${formatDuration(inBed)} · '
                    '${_percent(night.asleep, inBed)} efficient',
                  ),
                  HealthCaption(
                    '${formatTimeRange(night.start, night.end)} · '
                    '${night.source}',
                  ),
                ],
              ),
            ),
          ],
        ),
        if (score == null) ...[
          const SizedBox(height: 10),
          const HealthCaption('No score: $_noStages'),
        ],
      ],
    );
  }

  Widget _stages(SleepNight night) {
    if (!night.hasStages) {
      return const _Panel(
        title: 'Stages',
        children: [HealthCaption(_noStages)],
      );
    }
    final light = _lightName(overview.platform);
    final awakeTimes = night.segments
        .where((s) => s.stage == SleepStage.awake)
        .length;
    final start = formatClockTime(night.start);
    final end = formatClockTime(night.end);
    return _Panel(
      title: 'Stages',
      children: [
        NsStageTimeline(
          segments: [
            for (final s in night.segments)
              if (_nsStage(s.stage) case final stage?)
                (from: s.from, to: s.to, stage: stage),
          ],
          startLabel: start,
          endLabel: end,
          semanticsLabel:
              'Sleep stages, $start to $end: deep '
              '${formatDuration(night.deep)}, ${light.toLowerCase()} '
              '${formatDuration(night.light)}, REM '
              '${formatDuration(night.rem)}, awake '
              '${formatDuration(night.awake)}.',
        ),
        const SizedBox(height: 14),
        _Pairs([
          _Stat(
            'Deep',
            formatDuration(night.deep),
            '${_percent(night.deep, night.asleep)} · normal 15–20%',
          ),
          _Stat(
            'REM',
            formatDuration(night.rem),
            '${_percent(night.rem, night.asleep)} · normal 20–25%',
          ),
          _Stat(
            light,
            formatDuration(night.light),
            _percent(night.light, night.asleep),
          ),
          _Stat(
            'Awake',
            formatDuration(night.awake),
            awakeTimes == 1 ? '1 time' : '$awakeTimes times',
          ),
        ]),
      ],
    );
  }

  static NsStage? _nsStage(SleepStage s) => switch (s) {
    SleepStage.deep => NsStage.deep,
    SleepStage.light => NsStage.core,
    SleepStage.rem => NsStage.rem,
    SleepStage.awake => NsStage.awake,
    SleepStage.asleepUnspecified || SleepStage.inBed => null,
  };

  Widget _heartRate(bool loading, SleepNightExtras? extras) {
    const title = 'Heart rate while asleep';
    final samples = extras?.heartRate ?? const <HealthSample>[];
    if (loading) {
      return const _Panel(title: title, children: [_Loading()]);
    }
    if (samples.isEmpty) {
      return const _Panel(
        title: title,
        children: [
          HealthValue(null),
          HealthCaption('No heart rate recorded while asleep.'),
        ],
      );
    }
    final avg = samples.fold(0.0, (a, s) => a + s.value) / samples.length;
    final lowest = samples.reduce((a, b) => b.value < a.value ? b : a);
    final text =
        'Avg ${avg.round()} · lowest ${lowest.value.round()} bpm at '
        '${formatClockTime(lowest.from)}';
    return _Panel(
      title: title,
      children: [
        HealthCaption(text),
        const SizedBox(height: 8),
        NsLineChart(
          values: [for (final s in samples) s.value],
          semanticsLabel: 'Heart rate while asleep: $text.',
        ),
      ],
    );
  }

  Widget _contributors(SleepNight night, SleepScore score) {
    String rating(ContributorRating r) => switch (r) {
      ContributorRating.good => 'Good',
      ContributorRating.fair => 'Fair',
      ContributorRating.poor => 'Poor',
    };
    final prior = [
      for (final n in sleep.nights)
        if (n.date.isBefore(night.date)) n,
    ];
    String timing() {
      final d = bedtimeOffset(night, prior) ?? 0;
      if (d == 0) return 'At your usual time';
      return d > 0 ? '$d min later than usual' : '${-d} min earlier than usual';
    }

    String value(SleepContributor c, ContributorRating r) => switch (c) {
      SleepContributor.duration when r != ContributorRating.good =>
        'Short · ${formatDuration(night.asleep)} of ~'
            '${formatDuration(_reference)}',
      SleepContributor.timing => timing(),
      SleepContributor.efficiency =>
        '${rating(r)} · '
            '${_percent(night.asleep, night.inBed ?? night.span)}',
      _ => rating(r),
    };
    const labels = {
      SleepContributor.duration: 'Duration',
      SleepContributor.deep: 'Deep sleep',
      SleepContributor.rem: 'REM sleep',
      SleepContributor.efficiency: 'Efficiency',
      SleepContributor.timing: 'Bedtime consistency',
      SleepContributor.sleepHeartRate: 'Sleep heart rate',
    };
    final contributors = score.contributors;
    final unused = [
      if (!contributors.containsKey(SleepContributor.timing))
        'bedtime consistency needs 5 earlier nights',
      if (!contributors.containsKey(SleepContributor.sleepHeartRate))
        'sleep heart rate needs heart rate while asleep and a resting heart '
            'rate',
    ];
    return _Panel(
      title: 'What made the score',
      children: [
        for (final c in SleepContributor.values)
          if (contributors[c] case final r?)
            _Row(labels[c]!, value(c, r.rating)),
        if (unused.isNotEmpty) ...[
          const SizedBox(height: 6),
          HealthCaption('Not scored: ${unused.join('; ')}.'),
        ],
      ],
    );
  }

  Widget? _extras(SleepNightExtras extras) {
    final temp = extras.wristTemp;
    final deviation = extras.wristTempDeviation;
    final tiles = [
      if (extras.respiratoryRate case final v?)
        _Stat('Breathing', '${v.toStringAsFixed(1)} /min'),
      if (extras.bloodOxygen case final v?)
        _Stat('Blood oxygen', '${v.round()}%'),
      if (temp != null)
        deviation == null
            ? _Stat(_tempName, '${temp.toStringAsFixed(1)} °C')
            : _Stat(
                _tempName,
                '${deviation < 0 ? '−' : '+'}'
                    '${deviation.abs().toStringAsFixed(1)} °C',
                'vs your usual',
              ),
    ];
    if (tiles.isEmpty) return null;
    return _Panel(children: [_Pairs(tiles)]);
  }

  String get _tempName => overview.platform == HealthPlatformKind.appleHealth
      ? 'Wrist temp'
      : 'Skin temp';
}

class _RangeView extends ConsumerWidget {
  const _RangeView({
    required this.overview,
    required this.sleep,
    required this.range,
  });

  final HealthOverview overview;
  final SleepOverview sleep;
  final SleepRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nightsAsync = ref.watch(sleepRangeNightsProvider(range));
    final hrAsync = ref.watch(sleepRangeHrProvider(range));
    final nights = nightsAsync.isLoading ? null : nightsAsync.value;
    if (nights == null) return const _Loading();
    final hr = hrAsync.isLoading ? null : hrAsync.value;
    final heart = overview.heart;
    final stats = sleepRangeStats(
      nights: nights,
      range: range,
      readAt: overview.readAt,
      readableFrom: overview.readableFrom,
      sleepHr: hr ?? const {},
      restingHr: heart is SectionData<HeartOverview>
          ? heart.value.restingHrDaily
          : const [],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _timeAsleep(context, stats),
        if (hr == null)
          const _Panel(title: 'Averages', children: [_Loading()])
        else
          _averages(stats),
      ],
    );
  }

  Widget _timeAsleep(BuildContext context, SleepRangeStats stats) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final days = range.nights;
    final first = currentRangeStart(overview.readAt, range);
    final label =
        '${formatHealthDate(first)} – ${formatHealthDate(overview.readAt)}';
    final avg = stats.asleep.average;
    final previous = stats.asleep.previousAverage;
    final trend = avg == null || previous == null
        ? null
        : trendOf(TrendMetric.sleepDuration, avg, previous);
    final avgText = avg == null
        ? null
        : formatDuration(Duration(minutes: avg.round()));
    Color stage(NsStage s) => NsStageColors.of(s, brightness);
    final bars = [
      for (final (i, n) in stats.slots.indexed)
        NsBar(
          highlight: i == days - 1,
          segments: n == null
              ? const []
              : n.hasStages
              ? [
                  (
                    value: n.deep.inMinutes.toDouble(),
                    color: stage(NsStage.deep),
                  ),
                  (
                    value: n.light.inMinutes.toDouble(),
                    color: stage(NsStage.core),
                  ),
                  (
                    value: n.rem.inMinutes.toDouble(),
                    color: stage(NsStage.rem),
                  ),
                ]
              : [
                  (
                    value: n.asleep.inMinutes.toDouble(),
                    color: stage(NsStage.core),
                  ),
                ],
        ),
    ];
    return _Panel(
      title: 'Time asleep',
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
        if (avg == null)
          HealthCaption('No sleep recorded in these $days days.'),
        const SizedBox(height: 10),
        NsBarChart(
          bars: bars,
          referenceValue: _reference.inMinutes.toDouble(),
          referenceLabel: formatDuration(_reference),
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
              'Time asleep per night, $label. '
              '${avgText == null ? 'No nights recorded' : 'Average $avgText over ${stats.asleep.daysWithData} nights'}. '
              'Dashed line at ${formatDuration(_reference)}.',
        ),
        const SizedBox(height: 6),
        HealthCaption('Dashed line: ${formatDuration(_reference)} of sleep'),
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
          : '${formatDuration(Duration(minutes: trend.delta.abs().round()))} '
                'vs previous $days days',
    );
  }

  Widget _averages(SleepRangeStats stats) {
    String minutes(double? m) =>
        m == null ? '—' : formatDuration(Duration(minutes: m.round()));
    final bedtime = stats.bedtime;
    final staged = stats.slots.any((n) => n?.hasStages ?? false);
    return _Panel(
      title: 'Averages',
      children: [
        _Row(
          'Sleep score',
          stats.score == null ? '—' : '${stats.score!.round()}',
        ),
        _Row('Deep', minutes(stats.deep)),
        _Row('REM', minutes(stats.rem)),
        _Row(
          'Sleep heart rate',
          stats.sleepHr == null ? '—' : '${stats.sleepHr!.round()} bpm',
        ),
        _Row(
          'Usual bedtime',
          bedtime == null
              ? '—'
              : '${formatClockTime(DateTime(2000, 1, 1, 0, bedtime.minutes))}'
                    ' ± ${bedtime.spread} min',
        ),
        if (!staged) ...[
          const SizedBox(height: 6),
          const HealthCaption('Score, deep and REM: $_noStages'),
        ],
        if (bedtime == null) ...[
          const SizedBox(height: 6),
          const HealthCaption('Usual bedtime needs 5 nights.'),
        ],
      ],
    );
  }
}
