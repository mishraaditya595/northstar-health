import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/design/northstar_theme.dart';

/// Compact-width bottom nav: floating pill from the Performance V2 prototype
/// (`.bottom-nav` / `.nav-item` in prototypes/performance-v2/performance-v2.css).
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xE0161F22) : const Color(0xE3F5F9F7);
    final border = dark ? const Color(0x33B2C7C2) : const Color(0x2150645F);
    final inactive = dark ? const Color(0xFF9DAAAA) : const Color(0xFF647674);
    final activeBackground = dark
        ? NorthstarPalette.lime.withValues(alpha: .12)
        : const Color(0xFFE0EACA);
    final activeColor = dark ? NorthstarPalette.lime : const Color(0xFF273C29);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(23),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .34 : .12),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(23),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(23),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Expanded(
                        child: _Item(
                          destination: destinations[i],
                          selected: i == selectedIndex,
                          color: i == selectedIndex ? activeColor : inactive,
                          background: i == selectedIndex
                              ? activeBackground
                              : Colors.transparent,
                          onTap: () => onSelected(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.destination,
    required this.selected,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final NavigationDestination destination;
  final bool selected;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 55),
            child: IconTheme(
              data: IconThemeData(color: color, size: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  selected
                      ? destination.selectedIcon ?? destination.icon
                      : destination.icon,
                  const SizedBox(height: 4),
                  Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
