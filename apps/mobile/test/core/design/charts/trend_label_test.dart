import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/charts/trend_label.dart';
import 'package:beyondrep/core/design/stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: BeyondRepTheme.build(Brightness.dark),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('NsTrendLabel shows arrow and text', (tester) async {
    await tester.pumpWidget(
      _host(
        const NsTrendLabel(
          direction: NsTrend.down,
          tone: NsTrendTone.better,
          text: '3 bpm this month',
        ),
      ),
    );
    expect(find.text('▼ 3 bpm this month'), findsOneWidget);
  });

  testWidgets('flat and up use their own glyphs', (tester) async {
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            NsTrendLabel(
              direction: NsTrend.flat,
              tone: NsTrendTone.same,
              text: 'steady',
            ),
            NsTrendLabel(
              direction: NsTrend.up,
              tone: NsTrendTone.worse,
              text: 'higher',
            ),
          ],
        ),
      ),
    );
    expect(find.text('● steady'), findsOneWidget);
    expect(find.text('▲ higher'), findsOneWidget);
  });

  testWidgets('better and worse differ in colour, neutral is muted', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            NsTrendLabel(
              direction: NsTrend.up,
              tone: NsTrendTone.better,
              text: 'a',
            ),
            NsTrendLabel(
              direction: NsTrend.up,
              tone: NsTrendTone.worse,
              text: 'b',
            ),
            NsTrendLabel(
              direction: NsTrend.up,
              tone: NsTrendTone.neutral,
              text: 'c',
            ),
          ],
        ),
      ),
    );
    Color? colorOf(String t) => tester.widget<Text>(find.text(t)).style!.color;
    expect(colorOf('▲ a'), BeyondRepPalette.lime);
    expect(colorOf('▲ b'), BeyondRepPalette.amberDark);
    expect(colorOf('▲ c'), BeyondRepPalette.darkMuted);
  });
}
