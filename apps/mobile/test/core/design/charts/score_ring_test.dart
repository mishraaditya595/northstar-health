import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/charts/score_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: BeyondRepTheme.build(Brightness.dark),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('NsScoreRing null shows a dash', (tester) async {
    await tester.pumpWidget(
      _host(
        const NsScoreRing(
          value: null,
          size: 80,
          color: Colors.purple,
          caption: 'Sleep score',
        ),
      ),
    );
    expect(find.text('—'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('no score')), findsOneWidget);
  });

  testWidgets('NsScoreRing semantics', (tester) async {
    await tester.pumpWidget(
      _host(
        const NsScoreRing(
          value: 74,
          size: 80,
          color: Colors.purple,
          caption: 'Sleep score',
        ),
      ),
    );
    expect(find.text('74'), findsOneWidget);
    expect(find.bySemanticsLabel('Sleep score 74 of 100'), findsOneWidget);
  });

  testWidgets('NsScoreRing 100 fits at text scale 2.0', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BeyondRepTheme.build(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: Center(
              child: NsScoreRing(value: 100, size: 80, color: Colors.purple),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('NsScoreRing empty caption has no stray separator', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const NsScoreRing(value: 74, size: 80, color: Colors.purple)),
    );
    expect(find.bySemanticsLabel('74 of 100'), findsOneWidget);
    await tester.pumpWidget(
      _host(const NsScoreRing(value: null, size: 80, color: Colors.purple)),
    );
    expect(find.bySemanticsLabel('no score'), findsOneWidget);
  });
}
