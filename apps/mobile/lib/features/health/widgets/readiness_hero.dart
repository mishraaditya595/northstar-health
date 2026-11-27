import 'package:flutter/material.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/charts/score_ring.dart';
import '../../../core/design/hero_frame.dart';
import '../data/health_reader.dart';
import '../domain/energy.dart';
import '../domain/metric_explanations.dart';
import 'energy_text.dart';
import 'metric_info_sheet.dart';
import 'readiness_card.dart';

/// Energy now on the dark green hero: ring in the band colour, band advice as
/// the headline, the change since morning, the learning note, an explain
/// button and a chevron. The whole hero opens the energy detail through
/// [onOpen].
class ReadinessHero extends StatelessWidget {
  const ReadinessHero({
    required this.energy,
    required this.learning,
    required this.platform,
    required this.onOpen,
    super.key,
  });

  final Energy energy;
  final EnergyLearning learning;
  final HealthPlatformKind platform;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final words = readinessBandWords(energy.band);
    final change = energyChangeText(energy);
    final learningText = energyLearningText(learning);
    // The hero is dark green in both themes, so its slots use dark colours.
    final heroTheme = BeyondRepTheme.build(Brightness.dark);
    final band = energy.band.name.toUpperCase();
    final label = [
      'Energy now ${energy.value} of 100, $words.',
      '$change.',
      ?learningText,
      'See why',
    ].join(' ');
    // At large text the explain button and chevron get their own strip under
    // the text instead of sitting over the eyebrow and title.
    final large = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
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
                eyebrow: 'ENERGY NOW · $band',
                title: words,
                subtitle: change,
                leading: Theme(
                  data: heroTheme,
                  child: NsScoreRing(
                    value: energy.value,
                    size: 64,
                    color: readinessBandColor(heroTheme, energy.band),
                    caption: 'Energy',
                  ),
                ),
                child: learningText == null && !large
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (learningText != null)
                            Text(
                              learningText,
                              style: const TextStyle(
                                color: Color(0xFFBCCFC1),
                                fontSize: 12,
                              ),
                            ),
                          if (large) const SizedBox(height: 48),
                        ],
                      ),
              ),
            ),
          ),
          Positioned(
            top: large ? null : 4,
            bottom: large ? 8 : null,
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
                  ExcludeSemantics(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onOpen,
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(4, 14, 12, 14),
                        child: Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: Color(0xFFBCCFC1),
                        ),
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
