import 'package:flutter/material.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../domain/health_types.dart';

/// Shared shell of the overview cards: icon, title, optional trailing text
/// and chevron, then [children]. [semanticsLabel] replaces the children for
/// screen readers when set; leave it null when a child has its own action.
///
/// [info] is the card's header explain button; [bodyInfos] are explain
/// buttons placed inside [children] with a [HealthInfoAnchor] of the same
/// index. They are drawn above the card and keep their own semantics nodes,
/// so a [semanticsLabel] that hides the card's content does not hide them.
class HealthCardFrame extends StatefulWidget {
  const HealthCardFrame({
    required this.title,
    required this.icon,
    required this.children,
    this.sleepTint = false,
    this.trailing,
    this.semanticsLabel,
    this.onTap,
    this.info,
    this.bodyInfos = const [],
    this.footer,
    super.key,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool sleepTint;
  final Widget? trailing;
  final String? semanticsLabel;
  final VoidCallback? onTap;

  /// Explain button right of the title, before any chevron.
  final Widget? info;
  final List<Widget> bodyInfos;

  /// Action row under the content. It sits outside the card's tap target and
  /// outside [semanticsLabel], so it stays its own button for screen readers.
  final Widget? footer;

  @override
  State<HealthCardFrame> createState() => _HealthCardFrameState();
}

class _HealthCardFrameState extends State<HealthCardFrame> {
  final _header = LayerLink();
  final _body = <LayerLink>[];

  @override
  Widget build(BuildContext context) {
    while (_body.length < widget.bodyInfos.length) {
      _body.add(LayerLink());
    }
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final iconBg = widget.sleepTint
        ? (dark
              ? BeyondRepPalette.sleepSoftDark
              : BeyondRepPalette.sleepSoftLight)
        : (dark
              ? BeyondRepPalette.forestSoftDark
              : BeyondRepPalette.forestSoftLight);
    final iconColor = widget.sleepTint
        ? (dark ? BeyondRepPalette.sleepDark : BeyondRepPalette.sleepLight)
        : theme.colorScheme.primary;
    final onTap = widget.onTap;
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (widget.trailing != null)
                // Shares the row with the title instead of pushing the info
                // button and chevron out at large text.
                Flexible(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: widget.trailing,
                  ),
                ),
              if (widget.info != null)
                CompositedTransformTarget(
                  link: _header,
                  child: const SizedBox(width: 24, height: 32),
                ),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 20, color: theme.mutedColor),
            ],
          ),
          const SizedBox(height: 10),
          ...widget.children,
        ],
      ),
    );
    final label = widget.semanticsLabel;
    final footer = widget.footer;
    final hasInfo =
        widget.info != null || widget.bodyInfos.isNotEmpty || footer != null;
    final tappable = onTap == null
        ? content
        : InkWell(onTap: onTap, child: content);
    Widget follower(LayerLink link, Widget child) => Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.center,
        followerAnchor: Alignment.center,
        child: child,
      ),
    );
    // The label node stays outermost, as without buttons. The content is
    // hidden from screen readers by ExcludeSemantics instead of
    // excludeSemantics, so the buttons above it keep their own nodes.
    return Semantics(
      container: true,
      label: label,
      button: onTap != null,
      onTap: label == null ? null : onTap,
      excludeSemantics: label != null && !hasInfo,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: !hasInfo
            ? tappable
            : Stack(
                children: [
                  _InfoLinks(
                    body: _body,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ExcludeSemantics(
                          excluding: label != null,
                          child: tappable,
                        ),
                        if (footer != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: footer,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.info != null) follower(_header, widget.info!),
                  for (final (i, info) in widget.bodyInfos.indexed)
                    follower(_body[i], info),
                ],
              ),
      ),
    );
  }
}

class _InfoLinks extends InheritedWidget {
  const _InfoLinks({required this.body, required super.child});

  final List<LayerLink> body;

  @override
  bool updateShouldNotify(_InfoLinks old) => false;
}

/// Marks where a [HealthCardFrame.bodyInfos] button sits inside the card's
/// content: reserves [width] x [height] and the button is centred on it.
class HealthInfoAnchor extends StatelessWidget {
  const HealthInfoAnchor({
    required this.index,
    this.width = 24,
    this.height = 20,
    super.key,
  });

  final int index;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_InfoLinks>();
    final link = scope == null || index >= scope.body.length
        ? null
        : scope.body[index];
    final box = SizedBox(width: width, height: height);
    return link == null
        ? box
        : CompositedTransformTarget(link: link, child: box);
  }
}

/// Muted stand-in while the overview loads; never shows a value.
class HealthCardPlaceholder extends StatelessWidget {
  const HealthCardPlaceholder({
    required this.title,
    required this.icon,
    this.sleepTint = false,
    super.key,
  });

  final String title;
  final IconData icon;
  final bool sleepTint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HealthCardFrame(
      title: title,
      icon: icon,
      sleepTint: sleepTint,
      semanticsLabel: '$title loading',
      children: [
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: theme.extension<BeyondRepColors>()!.border.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ],
    );
  }
}

/// Big value line: `—` in muted colour when missing, never `0`.
class HealthValue extends StatelessWidget {
  const HealthValue(this.value, {this.unit, super.key});

  final String? value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
    final style = theme.textTheme.headlineSmall?.copyWith(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      letterSpacing: -1,
      color: v == null ? theme.mutedColor : null,
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 4,
      children: [
        Text(v ?? '—', style: style),
        if (v != null && unit != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              unit!,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

/// Muted caption line under a value.
class HealthCaption extends StatelessWidget {
  const HealthCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(color: theme.mutedColor),
    );
  }
}

/// [daily] laid onto the [days] local days ending at [today], null where a
/// day has no value (charts draw gaps, never zeros).
List<double?> dailySlots(List<DayValue> daily, DateTime today, int days) {
  final byDay = {for (final d in daily) d.day: d.value};
  return [
    for (var i = days - 1; i >= 0; i--)
      byDay[DateTime(today.year, today.month, today.day - i)],
  ];
}
