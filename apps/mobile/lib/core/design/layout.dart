import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Windows at least this wide (dp) use the wide layouts.
const double kWideWindowWidth = 840;

/// True when the window, not the parent constraint, is wide.
bool isWideWindow(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideWindowWidth;

/// Equal-width cells in rows. The column count follows the width and the text
/// scale, so large text gets fewer, wider columns instead of overflowing.
class NsResponsiveGrid extends StatelessWidget {
  const NsResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 320,
    this.maxColumns = 3,
    this.spacing = 12,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    // Half the text growth is enough: card text wraps, it does not need a
    // fully proportional column.
    final itemWidth = minItemWidth * (1 + (scale - 1) / 2);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = math
            .max(
              1,
              math.min(
                maxColumns,
                ((constraints.maxWidth + spacing) / (itemWidth + spacing))
                    .floor(),
              ),
            )
            .toInt();
        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
          final cells = <Widget>[];
          for (var i = 0; i < columns; i++) {
            if (i > 0) cells.add(SizedBox(width: spacing));
            final index = start + i;
            cells.add(
              Expanded(
                child: index < children.length
                    ? children[index]
                    : const SizedBox.shrink(),
              ),
            );
          }
          rows.add(
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

/// Main and side content: beside each other on a wide window, stacked
/// (main first) otherwise.
class NsSplitColumns extends StatelessWidget {
  const NsSplitColumns({
    super.key,
    required this.main,
    required this.side,
    this.mainFlex = 3,
    this.sideFlex = 2,
    this.gap = 20,
  });

  final List<Widget> main;
  final List<Widget> side;
  final int mainFlex;
  final int sideFlex;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (!isWideWindow(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [...main, ...side],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: mainFlex,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: main,
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          flex: sideFlex,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: side,
          ),
        ),
      ],
    );
  }
}

/// A list with a detail pane beside it on a wide window; the list alone
/// otherwise. When the window narrows while an item is open, [onCollapsed]
/// is called once with [selectedRoute] so the owner can push it as a page.
class NsListDetail extends StatefulWidget {
  const NsListDetail({
    super.key,
    required this.list,
    required this.detail,
    required this.emptyDetail,
    this.selectedRoute,
    this.onCollapsed,
    this.listWidth = 360,
  });

  final Widget list;
  final Widget? detail;
  final Widget emptyDetail;
  final String? selectedRoute;
  final ValueChanged<String>? onCollapsed;
  final double listWidth;

  @override
  State<NsListDetail> createState() => _NsListDetailState();
}

class _NsListDetailState extends State<NsListDetail> {
  bool? _wasWide;

  @override
  Widget build(BuildContext context) {
    final wide = isWideWindow(context);
    final route = widget.selectedRoute;
    if (_wasWide == true && !wide && route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onCollapsed?.call(route);
      });
    }
    _wasWide = wide;
    if (!wide) return widget.list;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: widget.listWidth, child: widget.list),
        const VerticalDivider(width: 1),
        Expanded(child: widget.detail ?? widget.emptyDetail),
      ],
    );
  }
}

/// Wide window: [select] the item in place. Narrow: push its [route].
void openListItem(
  BuildContext context, {
  required String route,
  required VoidCallback select,
}) {
  if (isWideWindow(context)) {
    select();
  } else {
    context.push(route);
  }
}
