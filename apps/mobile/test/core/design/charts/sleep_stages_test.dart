import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/charts/sleep_stages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  Widget child, {
  Brightness b = Brightness.dark,
  double scale = 1,
}) => MaterialApp(
  theme: BeyondRepTheme.build(b),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: Center(child: SizedBox(width: 320, child: child)),
    ),
  ),
);

final _t0 = DateTime(2026, 1, 1, 23);
List<({DateTime from, DateTime to, NsStage stage})> _segs() => [
  (from: _t0, to: _t0.add(const Duration(hours: 2)), stage: NsStage.core),
  (
    from: _t0.add(const Duration(hours: 1)),
    to: _t0.add(const Duration(hours: 3)),
    stage: NsStage.deep,
  ),
];

void main() {
  test('NsStageColors exact values', () {
    expect(
      NsStageColors.of(NsStage.deep, Brightness.dark),
      const Color(0xFF5B48A8),
    );
    expect(
      NsStageColors.of(NsStage.core, Brightness.dark),
      const Color(0xFF8E7AE0),
    );
    expect(
      NsStageColors.of(NsStage.rem, Brightness.dark),
      BeyondRepPalette.sleepDark,
    );
    expect(
      NsStageColors.of(NsStage.awake, Brightness.dark),
      BeyondRepPalette.amberDark,
    );
    expect(
      NsStageColors.of(NsStage.deep, Brightness.light),
      const Color(0xFF3E2F7A),
    );
    expect(
      NsStageColors.of(NsStage.core, Brightness.light),
      const Color(0xFF6650AB),
    );
    expect(
      NsStageColors.of(NsStage.rem, Brightness.light),
      const Color(0xFF9C86E0),
    );
    expect(
      NsStageColors.of(NsStage.awake, Brightness.light),
      BeyondRepPalette.amberLight,
    );
  });

  for (final b in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('NsStageBar renders ($b, x$scale)', (tester) async {
        await tester.pumpWidget(
          _host(
            const NsStageBar(
              totals: {
                NsStage.deep: Duration(hours: 1),
                NsStage.core: Duration(hours: 4),
                NsStage.rem: Duration(hours: 2),
                NsStage.awake: Duration(minutes: 20),
              },
              semanticsLabel: 'Stages bar',
            ),
            b: b,
            scale: scale,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel('Stages bar'), findsOneWidget);
      });

      testWidgets('NsStageTimeline renders ($b, x$scale)', (tester) async {
        await tester.pumpWidget(
          _host(
            NsStageTimeline(
              segments: _segs(),
              startLabel: '23:00',
              endLabel: '07:00',
              semanticsLabel: 'Stages timeline',
            ),
            b: b,
            scale: scale,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel('Stages timeline'), findsOneWidget);
        for (final l in ['Awake', 'REM', 'Core', 'Deep', '23:00', '07:00']) {
          expect(find.text(l), findsOneWidget);
        }
      });
    }
  }

  testWidgets('NsStageBar empty totals renders without exception', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const NsStageBar(totals: {}, semanticsLabel: 'No stages')),
    );
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('No stages'), findsOneWidget);
  });

  testWidgets('NsStageTimeline single and empty segments', (tester) async {
    await tester.pumpWidget(
      _host(
        NsStageTimeline(
          segments: [_segs().first],
          startLabel: 'a',
          endLabel: 'b',
          semanticsLabel: 'one',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      _host(
        const NsStageTimeline(
          segments: [],
          startLabel: 'a',
          endLabel: 'b',
          semanticsLabel: 'none',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
