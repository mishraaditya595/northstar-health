import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme_controller.dart';
import 'beyondrep_theme.dart';

/// Prototype `.app-topbar`: eyebrow, large title, theme switch and avatar.
class PageHeader extends ConsumerWidget {
  const PageHeader({
    required this.title,
    this.eyebrow,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? eyebrow;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = theme.mutedColor;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                Text(
                  eyebrow!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                title,
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontSize: 35,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2.2,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
        for (final action in actions) ...[action, const SizedBox(width: 8)],
        SquareButton(
          tooltip: dark ? 'Use light mode' : 'Use dark mode',
          onPressed: () => ref
              .read(themeControllerProvider.notifier)
              .toggle(theme.brightness),
          child: Icon(
            dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            size: 20,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: dark ? BeyondRepPalette.lime : const Color(0xFFE5EDDF),
            border: dark ? null : Border.all(color: const Color(0xFFD2DFD0)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            'A',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: dark ? BeyondRepPalette.heroDark : const Color(0xFF245137),
            ),
          ),
        ),
      ],
    );
  }
}

class SquareButton extends StatelessWidget {
  const SquareButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
    super.key,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: SizedBox(width: 48, height: 48, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// Prototype `.list-card`: glyph box, title and subtitle, optional trailing.
class NsListCard extends StatelessWidget {
  const NsListCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = theme.mutedColor;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: dark
                      ? BeyondRepPalette.forestSoftDark
                      : BeyondRepPalette.forestSoftLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 20, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              trailing ??
                  (onTap == null
                      ? const SizedBox.shrink()
                      : Icon(Icons.chevron_right, color: muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Prototype `.tag` pill. [warning] uses the prototype amber tokens for
/// states that need attention (for example a workout not synced).
class NsTag extends StatelessWidget {
  const NsTag(this.label, {this.warning = false, super.key});

  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: warning
            ? (dark
                  ? BeyondRepPalette.amberSoftDark
                  : BeyondRepPalette.amberSoftLight)
            : (dark
                  ? BeyondRepPalette.forestSoftDark
                  : BeyondRepPalette.forestSoftLight),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: warning
              ? (dark
                    ? BeyondRepPalette.amberDark
                    : BeyondRepPalette.amberLight)
              : (dark ? BeyondRepPalette.lime : const Color(0xFF253F2C)),
        ),
      ),
    );
  }
}

/// Prototype `.insight-card`: tinted card with a mark, text and optional action.
class InsightCard extends StatelessWidget {
  const InsightCard({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    super.key,
  });

  final IconData icon;
  final InlineSpan text;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// A second, quieter action ("Not now"). With it the actions sit under the
  /// text, so two buttons never squeeze the words at large text sizes.
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mark = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: dark
            ? BeyondRepPalette.sleepSoftDark
            : BeyondRepPalette.sleepSoftLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        size: 16,
        color: dark ? BeyondRepPalette.sleepDark : BeyondRepPalette.sleepLight,
      ),
    );
    final message = Expanded(
      child: Text.rich(
        text,
        style: theme.textTheme.bodySmall?.copyWith(height: 1.55),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        color: dark ? BeyondRepPalette.darkSoft : BeyondRepPalette.lightSoft,
        borderRadius: BorderRadius.circular(22),
      ),
      child: secondaryActionLabel == null
          ? Row(
              children: [
                mark,
                const SizedBox(width: 12),
                message,
                if (actionLabel != null)
                  TextButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [mark, const SizedBox(width: 12), message]),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    children: [
                      if (actionLabel != null)
                        TextButton(
                          onPressed: onAction,
                          child: Text(actionLabel!),
                        ),
                      TextButton(
                        onPressed: onSecondaryAction,
                        child: Text(secondaryActionLabel!),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Prototype `.back-button`: rounded-square back control for sub-page app bars.
class NsBackButton extends StatelessWidget {
  const NsBackButton({this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: BackButton(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            fixedSize: const Size(44, 44),
            backgroundColor: scheme.surface,
            foregroundColor: scheme.onSurface,
            side: BorderSide(color: scheme.outline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}
