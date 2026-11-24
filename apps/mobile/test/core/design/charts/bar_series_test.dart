import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/charts/bar_series.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
  theme: BeyondRepTheme.build(Brightness.light),
  builder: (context, c) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: c!,
  ),
  home: Scaffold(
    body: Center(child: SizedBox(width: 320, child: child)),
  ),
);

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('NsBarChart exposes its semantics label (x$scale)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          NsBarChart(
            bars: [
              const NsBar(segments: []),
              NsBar(segments: [(value: 400, color: Colors.purple)]),
            ],
            semanticsLabel: 'Time asleep, 7 nights',
            referenceValue: 480,
            referenceLabel: '8h',
            axisLabels: const ['Mon', 'Tue'],
          ),
          scale: scale,
        ),
      );
      expect(find.bySemanticsLabel('Time asleep, 7 nights'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('NsBarChart paints with an empty-segment bar (x$scale)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          NsBarChart(
            bars: [
              const NsBar(segments: []),
              NsBar(
                segments: [(value: 400, color: Colors.purple)],
                highlight: true,
              ),
            ],
            semanticsLabel: 'x',
          ),
          scale: scale,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('NsBarChart with all bars empty and no reference (x$scale)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const NsBarChart(
            bars: [
              NsBar(segments: []),
              NsBar(segments: []),
            ],
            semanticsLabel: 'x',
          ),
          scale: scale,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
