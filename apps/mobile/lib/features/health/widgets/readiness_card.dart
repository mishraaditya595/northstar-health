import 'package:flutter/material.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/charts/score_ring.dart';
import '../../../core/design/charts/trend_label.dart';
import '../../../core/design/hero_frame.dart';
import '../../../core/design/page_header.dart';
import '../application/health_overview.dart';
import '../domain/readiness.dart';
import '../domain/trend.dart';
import '../health_format.dart';
import 'health_card_frame.dart';
import 'metric_unavailable.dart';

const _eyebrow = 'READINESS';

String readinessBandWords(ReadinessBand band) => switch (band) {
  ReadinessBand.good => 'Good to train',
  ReadinessBand.fair => 'Train as planned, watch effort',
  ReadinessBand.low => 'Recovery low',
};

String _hrvName(bool sdnn) => sdnn ? 'HRV (SDNN)' : 'HRV (RMSSD)';

/// Readiness hero on the Health tab: the score with its reasons, or what is
/// missing for one. [overview] is null while loading. [onTap] opens the
/// detail for a score and handles Manage / Try again for a gap.
class ReadinessCard extends StatelessWidget {
  const ReadinessCard({
    required this.overview,
    this.onTap,
    this.onAllowMore,
    super.key,
  });

  final HealthOverview? overview;
  final VoidCallback? onTap;
  final VoidCallback? onAllowMore;

  @override
  Widget build(BuildContext context) {
    final overview = this.overview;
    if (overview == null) {
      return const NsHeroFrame(
        eyebrow: _eyebrow,
        loadingLabel: 'Loading readiness',
      );
    }
    final platform = overview.platform;
    return switch (overview.readiness) {
      SectionGap(gap: MetricGap.noData) => _notEnough(overview, null),
      SectionGap(:final gap) => _OutlinedCard(
        onTap: onTap,
        children: [
          MetricUnavailable(
            gap: gap,
            metricName: 'Readiness',
            platform: platform,
            onAction: onAllowMore,
          ),
        ],
      ),
      SectionData(:final value) => switch (value.result) {
        ReadinessReady(:final readiness) => _ready(overview, value, readiness),
        ReadinessNotReady(:final daysUntilBaseline?) => _building(
          overview,
          value,
          daysUntilBaseline,
        ),
        ReadinessNotReady() => _notEnough(overview, value),
      },
    };
  }

  Widget _ready(
    HealthOverview overview,
    ReadinessOverview value,
    Readiness readiness,
  ) {
    final heart = _heart(overview);
    final sleep = _sleep(overview);
    final inputs = {for (final p in readiness.parts) p.input};
    final hrvName = _hrvName(value.hrvIsSdnn);
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
    ].join(' · ');
    final sentence = reasons.isEmpty
        ? reasons
        : reasons[0].toUpperCase() + reasons.substring(1);
    final basedOn = !inputs.contains(ReadinessInput.restingHr)
        ? 'Based on HRV and sleep'
        : !inputs.contains(ReadinessInput.hrv)
        ? 'Based on sleep and resting HR'
        : null;
    final words = readinessBandWords(readiness.band);

    final hrv = value.hasHrv ? heart?.hrv?.value.round() : null;
    final rhr = value.hasRestingHr ? heart?.restingHr?.value.round() : null;
    final chips = [
      _Chip(
        label: 'HRV',
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
      'Readiness ${readiness.value} of 100, $words, $sentence.',
      if (basedOn != null) '$basedOn.',
      for (final c in chips) '${c.spoken}.',
    ].join(' ');

    final ringColor = readiness.band == ReadinessBand.good
        ? BeyondRepPalette.lime
        : BeyondRepPalette.amberDark;
    // The hero is dark green in both themes, so its slots use dark colours.
    final heroTheme = BeyondRepTheme.build(Brightness.dark);
    return Semantics(
      container: true,
      button: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: NsHeroFrame(
          eyebrow: _eyebrow,
          title: words,
          subtitle: [sentence, ?basedOn].join('\n'),
          leading: Theme(
            data: heroTheme,
            child: NsScoreRing(
              value: readiness.value,
              size: 76,
              color: ringColor,
              caption: 'Readiness',
            ),
          ),
          child: Theme(
            data: heroTheme,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, chip) in chips.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: chip),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _building(HealthOverview overview, ReadinessOverview value, int days) {
    final title =
        'Readiness starts after $days more ${days == 1 ? 'day' : 'days'} '
        'with data.';
    final measures = [
      if (value.hasHrv) _hrvName(value.hrvIsSdnn),
      if (value.hasRestingHr) 'resting HR',
    ];
    final body = measures.isEmpty
        ? null
        : 'Building your normal for ${measures.join(' and ')}.';
    final tags = _inputTags(overview, value);
    return _OutlinedCard(
      semanticsLabel: [
        'Readiness: $title',
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
  Widget _notEnough(HealthOverview overview, ReadinessOverview? value) {
    const title = 'Not enough data for a score';
    final body =
        "Readiness needs last night's sleep plus HRV or resting heart rate. "
        'A watch or ring that syncs to '
        '${healthPlatformName(overview.platform)} provides these.';
    final tags = _inputTags(overview, value);
    return _OutlinedCard(
      semanticsLabel: 'Readiness: $title. $body ${tags.join(', ')}.',
      children: [
        const _OutlinedTitle(title),
        const SizedBox(height: 6),
        HealthCaption(body),
        const SizedBox(height: 10),
        _Tags(tags),
      ],
    );
  }

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
  });

  final List<Widget> children;
  final String? semanticsLabel;
  final VoidCallback? onTap;

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
    return Semantics(
      container: true,
      label: label,
      button: onTap != null,
      onTap: label == null ? null : onTap,
      excludeSemantics: label != null,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
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
