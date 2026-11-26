import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/charts/range_bar.dart';
import '../../../core/design/dialogs.dart';
import '../../../core/design/info_button.dart';
import '../data/health_reader.dart';
import '../domain/metric_explanations.dart';
import '../health_format.dart';

/// Metrics whose numbers read better with one decimal.
const _oneDecimal = {
  MetricKey.vo2Max,
  MetricKey.weight,
  MetricKey.bodyFat,
  MetricKey.wristTemperature,
};

String _number(MetricKey key, double v) =>
    _oneDecimal.contains(key) ? v.toStringAsFixed(1) : formatCount(v);

/// Opens the plain-language explanation for [key]. [usual] adds the user's
/// own range from data already in memory; [showUsualPlaceholder] says why it
/// is missing when there are fewer than 14 days.
Future<void> showMetricInfo(
  BuildContext context,
  MetricKey key, {
  required HealthPlatformKind platform,
  MetricUsual? usual,
  String? unit,
  bool showUsualPlaceholder = false,
  bool showTermsLink = true,
}) {
  final e = explanationFor(key, platform);
  final router = GoRouter.maybeOf(context);
  return showNsSheet<void>(
    context,
    heightFactor: 0.7,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final muted = theme.mutedColor;
      final heading = theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
      );
      Widget section(String title, String body) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: heading),
            const SizedBox(height: 6),
            Text(body, style: theme.textTheme.bodyMedium),
          ],
        ),
      );
      return ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          24 + MediaQuery.paddingOf(sheetContext).bottom,
        ),
        children: [
          Semantics(
            header: true,
            child: Text(
              e.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(e.what, style: theme.textTheme.bodyMedium),
          if (usual != null) ...[
            const SizedBox(height: 20),
            Text('Yours', style: heading),
            const SizedBox(height: 10),
            if (!usual.dailyAverage) ...[
              _bar(usual),
              const SizedBox(height: 8),
            ],
            Text(
              usual.dailyAverage
                  ? 'Your daily average ${_number(key, usual.low)}'
                  : 'Your usual ${_number(key, usual.low)} to '
                        '${_number(key, usual.high)}'
                        '${unit == null ? '' : ' $unit'}',
              style: theme.textTheme.bodyMedium,
            ),
            if (usual.today != null)
              Text(
                'Today ${_number(key, usual.today!)}',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
          ] else if (showUsualPlaceholder) ...[
            const SizedBox(height: 20),
            Text(
              "We'll show your usual range after 14 days of data.",
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          section('What it tells you', e.tells),
          section('In BeyondRep', e.inBeyondRep),
          if (showTermsLink) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  router?.push('/health/terms');
                },
                child: const Text('All health terms'),
              ),
            ),
          ],
        ],
      );
    },
  );
}

Widget _bar(MetricUsual usual) {
  final pad = (usual.high - usual.low) + 1;
  var min = usual.low - pad * 1.5;
  var max = usual.high + pad * 1.5;
  final today = usual.today;
  if (today != null) {
    if (today < min) min = today;
    if (today > max) max = today;
  }
  return NsRangeBar(
    low: usual.low,
    high: usual.high,
    value: today,
    min: min,
    max: max,
  );
}

/// An [NsInfoButton] labelled `About <title>` that opens [showMetricInfo].
Widget metricInfoButton(
  BuildContext context,
  MetricKey key, {
  required HealthPlatformKind platform,
  MetricUsual? usual,
  String? unit,
  bool showUsualPlaceholder = false,
}) => NsInfoButton(
  label: 'About ${explanationFor(key, platform).title}',
  onPressed: () => showMetricInfo(
    context,
    key,
    platform: platform,
    usual: usual,
    unit: unit,
    showUsualPlaceholder: showUsualPlaceholder,
  ),
);
