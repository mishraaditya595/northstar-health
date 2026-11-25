import 'package:flutter/material.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/page_header.dart';
import '../domain/training_insights.dart';
import '../health_format.dart';

/// One plain-language training tie-in: a sentence and a caption with the
/// counts behind it.
class TrainingInsightLine extends StatelessWidget {
  const TrainingInsightLine._({
    required this.icon,
    required this.sentence,
    required this.caption,
    super.key,
  });

  factory TrainingInsightLine.sleep(SleepAfterTraining insight, {Key? key}) {
    final more = insight.difference > Duration.zero;
    return TrainingInsightLine._(
      key: key,
      icon: Icons.bedtime_outlined,
      sentence:
          'You slept ${formatDuration(insight.difference.abs())} '
          '${more ? 'more' : 'less'} on nights after training',
      caption:
          '${insight.trainingNights} nights after training vs '
          '${insight.otherNightsCount} other nights, last 30 days',
    );
  }

  factory TrainingInsightLine.restingHr(
    RestingHrAfterHard insight, {
    Key? key,
  }) {
    final higher = insight.difference > 0;
    return TrainingInsightLine._(
      key: key,
      icon: Icons.favorite_border,
      sentence:
          'Resting HR was ${insight.difference.abs().round()} bpm '
          '${higher ? 'higher' : 'lower'} the morning after your biggest '
          'sessions',
      caption:
          '${insight.hardDays} mornings vs ${insight.otherDaysCount} other '
          'days, last 30 days',
    );
  }

  final IconData icon;
  final String sentence;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.extension<BeyondRepColors>()!.muted;
    return Semantics(
      container: true,
      label: '$sentence. $caption',
      excludeSemantics: true,
      child: InsightCard(
        icon: icon,
        text: TextSpan(
          children: [
            TextSpan(text: sentence),
            TextSpan(
              text: '\n$caption',
              style: TextStyle(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
