import 'package:flutter/material.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/charts/score_ring.dart';
import '../../../core/design/charts/trend_label.dart';
import '../../../core/design/hero_frame.dart';
import '../../../core/design/page_header.dart';
import '../application/health_overview.dart';
import '../domain/energy.dart';
import '../domain/metric_explanations.dart';
import '../domain/readiness.dart';
import '../domain/trend.dart';
import '../health_format.dart';
import 'energy_text.dart';
import 'health_card_frame.dart';
import 'metric_info_sheet.dart';
import 'metric_unavailable.dart';

const _eyebrow = 'ENERGY';
const _scoreEyebrow = 'ENERGY NOW';

/// Ring, score and bar colour for [band]: primary when good, amber when
/// fair, red when low.
Color readinessBandColor(ThemeData theme, ReadinessBand band) {
  final dark = theme.brightness == Brightness.dark;
  return switch (band) {
    ReadinessBand.good => theme.colorScheme.primary,
    ReadinessBand.fair =>
      dark ? BeyondRepPalette.amberDark : BeyondRepPalette.amberLight,
    ReadinessBand.low =>
      dark ? BeyondRepPalette.redDark : BeyondRepPalette.redLight,
  };
}

/// Soft background that goes with [readinessBandColor].
Color readinessBandSoftColor(ThemeData theme, ReadinessBand band) {
  final dark = theme.brightness == Brightness.dark;
  return switch (band) {
    ReadinessBand.good =>
      dark ? BeyondRepPalette.forestSoftDark : BeyondRepPalette.forestSoftLight,
    ReadinessBand.fair =>
      dark ? BeyondRepPalette.amberSoftDark : BeyondRepPalette.amberSoftLight,
    ReadinessBand.low =>
      dark ? BeyondRepPalette.redSoftDark : BeyondRepPalette.redSoftLight,
  };
}

/// `Readiness starts after 4 more days with data.`
String readinessBuildingText(int days) =>
    'Readiness starts after $days more ${days == 1 ? 'day' : 'days'} '
    'with data.';

String readinessBandWords(ReadinessBand band) => switch (band) {
  ReadinessBand.good => 'Good to train',
  ReadinessBand.fair => 'Train as planned, watch effort',
  ReadinessBand.low => 'Recovery low',
};

String readinessHrvName(bool sdnn) => sdnn ? 'HRV (SDNN)' : 'HRV (RMSSD)';

/// The reasons line under a score, e.g. `HRV (SDNN) above your normal ·
/// slept 7h 12m`; empty when no input has a reason to give.
String readinessReasons(
  HealthOverview overview,
  ReadinessOverview value,
  Readiness readiness,
) {
  final sleep = switch (overview.sleep) {
    SectionData(:final value) => value,
    SectionGap() => null,
  };
  final inputs = {for (final p in readiness.parts) p.input};
  final hrvName = readinessHrvName(value.hrvIsSdnn);
  String vsNormal(TrendResult? t) => switch (t?.direction) {
    TrendDirection.up => 'above',
    TrendDirection.down => 'below',
    _ => 'about',
  };
  final reasons = [
    if (inputs.contains(ReadinessInput.hrv))
      '$hrvName ${vsNormal(value.hrvVsNormal)} your normal',
    if (inputs.contains(ReadinessInput.restingHr))
      'resting HR ${vsNormal(value.restingHrVsNormal)} your normal',
    if (sleep != null) 'slept ${formatDuration(sleep.lastNight.asleep)}',
    if (readiness.loadRatio case final r? when r > 1.3)
      'training load above your usual',
  ].join(' · ');
  return reasons.isEmpty
      ? reasons
      : reasons[0].toUpperCase() + reasons.substring(1);
}

/// One readiness input as the watch shows it: [input] is a `watch_link`
/// contract string, [status] at most 24 code points, [tone] `good`,
/// `neutral` or `caution`.
class ReadinessFactor {
  const ReadinessFactor({
    required this.input,
    required this.status,
    required this.tone,
  });

  final String input;
  final String status;
  final String tone;
}

/// The inputs behind a score with the same trend words as
/// [readinessReasons]: sleep, HRV, resting HR, then training load.
List<ReadinessFactor> readinessFactors(
  HealthOverview overview,
  ReadinessOverview value,
  Readiness readiness,
) {
  final inputs = {for (final p in readiness.parts) p.input};
  ReadinessFactor vsUsual(
    String input,
    TrendResult? t, {
    required TrendDirection better,
  }) {
    final direction = t?.direction;
    return ReadinessFactor(
      input: input,
      status: switch (direction) {
        TrendDirection.up => 'Above usual',
        TrendDirection.down => 'Below usual',
        _ => 'About usual',
      },
      tone: direction == null || direction == TrendDirection.flat
          ? 'neutral'
          : direction == better
          ? 'good'
          : 'caution',
    );
  }

  final sleep = switch (overview.sleep) {
    SectionData(:final value) => value,
    SectionGap() => null,
  };
  final ratio = readiness.loadRatio;
  return [
    if (inputs.contains(ReadinessInput.sleep) && sleep != null)
      ReadinessFactor(
        input: 'sleep',
        status: 'Slept ${formatDuration(sleep.lastNight.asleep)}',
        tone: sleep.lastNight.asleep >= const Duration(hours: 7)
            ? 'good'
            : sleep.lastNight.asleep < const Duration(hours: 6)
            ? 'caution'
            : 'neutral',
      ),
    if (inputs.contains(ReadinessInput.hrv))
      vsUsual('hrv', value.hrvVsNormal, better: TrendDirection.up),
    if (inputs.contains(ReadinessInput.restingHr))
      vsUsual(
        'resting_hr',
        value.restingHrVsNormal,
        better: TrendDirection.down,
      ),
    if (ratio != null)
      ReadinessFactor(
        input: 'training_load',
        status: ratio > 1.3 ? 'Above usual' : 'Normal',
        tone: ratio > 1.3 ? 'caution' : 'neutral',
      ),
  ];
}

/// Energy hero on the Health tab: the score with its change since morning and
/// reasons, or what is missing for one. [overview] is null while loading.
/// [onTap] opens the detail for a score and handles Manage / Try again for a
/// gap.
class ReadinessCard extends StatelessWidget {
  const ReadinessCard({
    required this.overview,
    required this.now,
    this.refreshing = false,
    this.onTap,
    this.onAllowMore,
    super.key,
  });

  final HealthOverview? overview;

  /// The device's local time: energy outlives its waking day only briefly.
  final DateTime now;

  /// A re-read is in flight; shown instead of a score from an earlier day.
  final bool refreshing;
  final VoidCallback? onTap;
  final VoidCallback? onAllowMore;

  @override
  Widget build(BuildContext context) {
    final overview = this.overview;
    if (overview == null) {
      return const NsHeroFrame(
        eyebrow: _eyebrow,
        loadingLabel: 'Loading energy',
      );
    }
    final platform = overview.platform;
    if (hasStaleEnergy(overview, now)) {
      return refreshing
          ? const NsHeroFrame(eyebrow: _eyebrow, loadingLabel: 'Loading energy')
          : _OutlinedCard(
              onTap: onTap,
              children: [
                MetricUnavailable(
                  gap: MetricGap.failed,
                  metricName: 'Energy',
                  platform: platform,
                ),
              ],
            );
    }
    return switch (overview.energy) {
      SectionGap(gap: MetricGap.noData) => _notEnough(context, overview, null),
      SectionGap(:final gap) => _OutlinedCard(
        onTap: onTap,
        children: [
          MetricUnavailable(
            gap: gap,
            metricName: 'Energy',
            platform: platform,
            onAction: onAllowMore,
          ),
        ],
      ),
      SectionData(:final value) => switch ((value.energy, value.start.result)) {
        (final energy?, ReadinessReady(:final readiness)) => _ready(
          context,
          overview,
          value,
          energy,
          readiness,
        ),
        (_, ReadinessNotReady(:final daysUntilBaseline?)) => _building(
          context,
          overview,
          value.start,
          daysUntilBaseline,
        ),
        (null, ReadinessReady()) => _resets(context, overview),
        _ => _notEnough(context, overview, value.start),
      },
    };
  }

  Widget _ready(
    BuildContext context,
    HealthOverview overview,
    EnergyOverview energyOverview,
    Energy energy,
    Readiness readiness,
  ) {
    final value = energyOverview.start;
    final heart = _heart(overview);
    final sleep = _sleep(overview);
    final inputs = {for (final p in readiness.parts) p.input};
    final sentence = readinessReasons(overview, value, readiness);
    final basedOn = !inputs.contains(ReadinessInput.restingHr)
        ? 'Based on HRV and sleep'
        : !inputs.contains(ReadinessInput.hrv)
        ? 'Based on sleep and resting HR'
        : null;
    final words = readinessBandWords(energy.band);
    final change = energyChangeText(energy);
    final learning = energyLearningText(energyOverview.learning);

    final hrv = value.hasHrv ? heart?.hrv?.value.round() : null;
    final rhr = value.hasRestingHr ? heart?.restingHr?.value.round() : null;
    final chips = [
      _Chip(
        label: readinessHrvName(value.hrvIsSdnn),
        value: hrv == null ? null : '$hrv ms',
        trend: value.hrvVsNormal,
      ),
      _Chip(
        label: 'Resting HR',
        value: rhr == null ? null : '$rhr bpm',
        trend: value.restingHrVsNormal,
      ),
      _Chip(
        label: 'Sleep',
        value: sleep == null ? null : formatDuration(sleep.lastNight.asleep),
        trend: sleep?.vsWeek,
        needsBaseline: false,
      ),
    ];
    final label = [
      'Energy now ${energy.value} of 100, $words.',
      '$change.',
      if (sentence.isNotEmpty) '$sentence.',
      if (basedOn != null) '$basedOn.',
      ?learning,
      for (final c in chips) '${c.spoken}.',
    ].join(' ');

    // The hero is dark green in both themes, so its slots use dark colours.
    final heroTheme = BeyondRepTheme.build(Brightness.dark);
    final ringColor = readinessBandColor(heroTheme, energy.band);
    // The label node stays outermost; ExcludeSemantics (not excludeSemantics)
    // hides the hero's content so the info button keeps its own node.
    return Semantics(
      container: true,
      button: onTap != null,
      label: label,
      onTap: onTap,
      child: Stack(
        children: [
          ExcludeSemantics(
            child: GestureDetector(
              onTap: onTap,
              child: NsHeroFrame(
                eyebrow: _scoreEyebrow,
                title: words,
                subtitle: [
                  change,
                  if (sentence.isNotEmpty) sentence,
                  ?basedOn,
                ].join('\n'),
                leading: Theme(
                  data: heroTheme,
                  child: NsScoreRing(
                    value: energy.value,
                    size: 76,
                    color: ringColor,
                    caption: 'Energy',
                  ),
                ),
                child: Theme(
                  data: heroTheme,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (i, chip) in chips.indexed) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(child: chip),
                          ],
                        ],
                      ),
                      if (learning != null) ...[
                        const SizedBox(height: 10),
                        Builder(
                          builder: (context) {
                            final theme = Theme.of(context);
                            return Text(
                              learning,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.mutedColor,
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Theme(data: heroTheme, child: _info(context, overview)),
          ),
        ],
      ),
    );
  }

  Widget _building(
    BuildContext context,
    HealthOverview overview,
    ReadinessOverview value,
    int days,
  ) {
    final title = energyBuildingText(days);
    final measures = [
      if (value.hasHrv) readinessHrvName(value.hrvIsSdnn),
      if (value.hasRestingHr) 'resting HR',
    ];
    final body = measures.isEmpty
        ? null
        : 'Building your normal for ${measures.join(' and ')}.';
    final tags = _inputTags(overview, value);
    return _OutlinedCard(
      info: _info(context, overview),
      semanticsLabel: [
        'Energy: $title',
        ?body,
        '${tags.join(', ')}.',
      ].join(' '),
      children: [
        _OutlinedTitle(title),
        if (body != null) ...[const SizedBox(height: 6), HealthCaption(body)],
        const SizedBox(height: 10),
        _Tags(tags),
      ],
    );
  }

  /// No sleep last night or no HRV / resting HR today; [value] is null when
  /// neither sleep nor heart has any data.
  Widget _notEnough(
    BuildContext context,
    HealthOverview overview,
    ReadinessOverview? value,
  ) {
    const title = 'Not enough data for a score';
    final body =
        "Energy needs last night's sleep plus HRV or resting heart rate. "
        'A watch or ring that syncs to '
        '${healthPlatformName(overview.platform)} provides these.';
    final tags = _inputTags(overview, value);
    return _OutlinedCard(
      info: _info(context, overview),
      semanticsLabel: 'Energy: $title. $body ${tags.join(', ')}.',
      children: [
        const _OutlinedTitle(title),
        const SizedBox(height: 6),
        HealthCaption(body),
        const SizedBox(height: 10),
        _Tags(tags),
      ],
    );
  }

  /// The start is scored but the waking day has ended: no energy to show
  /// until the next main sleep.
  Widget _resets(BuildContext context, HealthOverview overview) {
    const title = 'Energy resets after your next sleep';
    const body =
        'Your day started more than 20 hours ago. '
        'Energy starts again from your next main sleep.';
    return _OutlinedCard(
      info: _info(context, overview),
      semanticsLabel: 'Energy: $title. $body',
      children: const [
        _OutlinedTitle(title),
        SizedBox(height: 6),
        HealthCaption(body),
      ],
    );
  }

  Widget _info(BuildContext context, HealthOverview overview) =>
      metricInfoButton(
        context,
        MetricKey.readiness,
        platform: overview.platform,
      );

  /// `Sleep: 7h 12m`, `HRV: none`, `Resting HR: none`.
  List<String> _inputTags(HealthOverview overview, ReadinessOverview? value) {
    final sleep = value != null && value.hasSleep ? _sleep(overview) : null;
    final heart = _heart(overview);
    final hrv = value != null && value.hasHrv ? heart?.hrv : null;
    final rhr = value != null && value.hasRestingHr ? heart?.restingHr : null;
    return [
      'Sleep: ${sleep == null ? 'none' : formatDuration(sleep.lastNight.asleep)}',
      'HRV: ${hrv == null ? 'none' : '${hrv.value.round()} ms'}',
      'Resting HR: ${rhr == null ? 'none' : '${rhr.value.round()} bpm'}',
    ];
  }

  static SleepOverview? _sleep(HealthOverview o) => switch (o.sleep) {
    SectionData(:final value) => value,
    SectionGap() => null,
  };

  static HeartOverview? _heart(HealthOverview o) => switch (o.heart) {
    SectionData(:final value) => value,
    SectionGap() => null,
  };
}

/// One input under the score: name, value or `—`, and its trend words.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.value,
    required this.trend,
    this.needsBaseline = true,
  });

  final String label;
  final String? value;
  final TrendResult? trend;

  /// HRV and resting HR compare with a 30-day normal; sleep with its week.
  final bool needsBaseline;

  String get _note => value == null
      ? 'None today'
      : trend == null && needsBaseline
      ? 'No normal yet'
      : '';

  String get _words => switch (trend?.tone) {
    TrendTone.better => 'better',
    TrendTone.worse => 'worse',
    _ => 'same',
  };

  String get spoken {
    final t = trend;
    if (value == null) return '$label: none today';
    if (t == null) return '$label $value${_note.isEmpty ? '' : ', $_note'}';
    return '$label $value, $_words';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = trend;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: BeyondRepPalette.darkCanvas.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.mutedColor,
            ),
          ),
          Text(
            value ?? '—',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: value == null ? theme.mutedColor : null,
            ),
          ),
          if (value != null && t != null)
            NsTrendLabel(
              direction: nsTrendOf(t).direction,
              tone: nsTrendOf(t).tone,
              text: _words,
            )
          else if (_note.isNotEmpty)
            Text(
              _note,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.mutedColor,
              ),
            ),
        ],
      ),
    );
  }
}

/// Plain bordered card for the states without a score (the kit has no
/// dashed border).
class _OutlinedCard extends StatelessWidget {
  const _OutlinedCard({
    required this.children,
    this.semanticsLabel,
    this.onTap,
    this.info,
  });

  final List<Widget> children;
  final String? semanticsLabel;
  final VoidCallback? onTap;

  /// Explain button in the top right corner, above the card's content.
  final Widget? info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _eyebrow,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.mutedColor,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
    final label = semanticsLabel;
    final tappable = onTap == null
        ? content
        : InkWell(onTap: onTap, child: content);
    return Semantics(
      container: true,
      label: label,
      button: onTap != null,
      onTap: label == null ? null : onTap,
      excludeSemantics: label != null && info == null,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: info == null
            ? tappable
            : Stack(
                children: [
                  ExcludeSemantics(excluding: label != null, child: tappable),
                  Positioned(top: 4, right: 4, child: info!),
                ],
              ),
      ),
    );
  }
}

class _OutlinedTitle extends StatelessWidget {
  const _OutlinedTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w800),
  );
}

class _Tags extends StatelessWidget {
  const _Tags(this.tags);

  final List<String> tags;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [for (final t in tags) NsTag(t)],
  );
}
