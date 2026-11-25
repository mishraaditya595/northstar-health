import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/charts/line_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
  theme: BeyondRepTheme.build(Brightness.dark),
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
    testWidgets('NsLineChart handles null gaps and a single value (x$scale)', (
      tester,
    ) async {
      for (final values in <List<double?>>[
        [null, 54, null],
        [54],
        [50, null, 52, 56],
        [null, null],
      ]) {
        await tester.pumpWidget(
          _host(
            NsLineChart(
              values: values,
              semanticsLabel: 'Resting heart rate',
              dots: true,
              rollingAverage: values.map((v) => v).toList(),
              band: (low: 48, high: 58, label: 'Normal range'),
              startLabel: 'Nov 1',
              endLabel: 'Nov 7',
            ),
            scale: scale,
          ),
        );
        expect(tester.takeException(), isNull);
      }
      expect(find.bySemanticsLabel('Resting heart rate'), findsOneWidget);
    });

    testWidgets('NsSparkline exposes semantics (x$scale)', (tester) async {
      await tester.pumpWidget(
        _host(
          const NsSparkline(
            values: [null, 52, 54, null, 53],
            color: Colors.teal,
            semanticsLabel: 'Steps trend',
          ),
          scale: scale,
        ),
      );
      expect(find.bySemanticsLabel('Steps trend'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
