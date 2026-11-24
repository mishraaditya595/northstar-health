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
}
