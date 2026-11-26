import 'package:flutter/material.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/charts/score_ring.dart';
import '../../../core/design/hero_frame.dart';
import '../data/health_reader.dart';
import '../domain/metric_explanations.dart';
import '../domain/readiness.dart';
import 'metric_info_sheet.dart';
import 'readiness_card.dart';

/// Today's readiness on the dark green hero: ring in the band colour, band
/// advice as the headline, the reasons, an explain button and a chevron.
/// The whole hero opens the readiness detail through [onOpen].
class ReadinessHero extends StatelessWidget {
  const ReadinessHero({
    required this.readiness,
    required this.reasons,
    required this.platform,
    required this.onOpen,
    super.key,
  });

  final Readiness readiness;
  final String reasons;
  final HealthPlatformKind platform;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final words = readinessBandWords(readiness.band);
    // The hero is dark green in both themes, so its slots use dark colours.
    final heroTheme = BeyondRepTheme.build(Brightness.dark);
    final band = readiness.band.name.toUpperCase();
    final label = [
      'Readiness ${readiness.value}, $words.',
      if (reasons.isNotEmpty) '$reasons.',
      'See why',
    ].join(' ');
    // The label node stays outermost; ExcludeSemantics (not excludeSemantics)
    // hides the hero's content so the info button keeps its own node.
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onOpen,
      child: Stack(
        children: [
          ExcludeSemantics(
            child: GestureDetector(
              onTap: onOpen,
              child: NsHeroFrame(
                eyebrow: 'READINESS · $band',
                title: words,
                subtitle: reasons.isEmpty ? null : reasons,
                leading: Theme(
                  data: heroTheme,
                  child: NsScoreRing(
                    value: readiness.value,
                    size: 64,
                    color: readinessBandColor(heroTheme, readiness.band),
                    caption: 'Readiness',
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Theme(
              data: heroTheme,
              child: Row(
                children: [
                  metricInfoButton(
                    context,
                    MetricKey.readiness,
                    platform: platform,
                  ),
                  const ExcludeSemantics(
                    child: Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: Color(0xFFBCCFC1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
