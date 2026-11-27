import 'package:flutter/material.dart';

import 'beyondrep_theme.dart';

/// One hero button; the first in [NsHeroFrame.actions] is the filled primary.
class NsHeroAction {
  const NsHeroAction(this.label, this.onPressed);
  final String label;
  final VoidCallback onPressed;
}

/// Dark green hero card (Today, Health readiness).
class NsHeroFrame extends StatelessWidget {
  const NsHeroFrame({
    super.key,
    required this.eyebrow,
    this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
    this.child,
    this.loadingLabel = 'Loading your plans',
  });

  final String eyebrow;

  /// Null while loading: a spinner replaces title, subtitle, slots and actions.
  final String? title;
  final String? subtitle;

  /// The first action is the filled primary button.
  final List<NsHeroAction> actions;

  /// Left of the title block, for example a score ring.
  final Widget? leading;

  /// Under the subtitle and above the actions, for example chips.
  final Widget? child;

  /// Screen reader label of the loading spinner.
  final String loadingLabel;

  /// The muted green of the subtitle, for text placed in [child].
  static const Color subtleColor = Color(0xFFBCCFC1);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const subtle = subtleColor;
    final titleBlock = title == null
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.8,
                  ),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: subtle,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? BeyondRepPalette.heroDark : BeyondRepPalette.heroLight,
          border: Border.all(color: BeyondRepPalette.heroBorder),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -32,
              bottom: -55,
              child: IgnorePointer(
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: BeyondRepPalette.lime.withValues(alpha: .25),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: BeyondRepPalette.lime.withValues(alpha: .04),
                        spreadRadius: 22,
                      ),
                      BoxShadow(
                        color: BeyondRepPalette.lime.withValues(alpha: .03),
                        spreadRadius: 44,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: const TextStyle(
                      color: Color(0xFFB7DBC1),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 9),
                  if (title == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Semantics(
                          label: loadingLabel,
                          child: const CircularProgressIndicator(),
                        ),
                      ),
                    )
                  else ...[
                    if (leading == null)
                      titleBlock
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          leading!,
                          const SizedBox(width: 14),
                          Expanded(child: titleBlock),
                        ],
                      ),
                    if (child != null) ...[const SizedBox(height: 12), child!],
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 17),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          FilledButton(
                            onPressed: actions.first.onPressed,
                            style: FilledButton.styleFrom(
                              backgroundColor: BeyondRepPalette.lime,
                              foregroundColor: const Color(0xFF111A10),
                              minimumSize: const Size(0, 46),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 17,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            child: Text(actions.first.label),
                          ),
                          for (final action in actions.skip(1))
                            TextButton(
                              onPressed: action.onPressed,
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFCFE4D3),
                                minimumSize: const Size(44, 44),
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              child: Text(action.label),
                            ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
