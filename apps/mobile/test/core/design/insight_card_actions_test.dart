import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/page_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Brightness b, Widget child, {double scale = 1}) => MaterialApp(
  theme: BeyondRepTheme.build(b),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('one action keeps the single-row layout', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        Brightness.light,
        InsightCard(
          icon: Icons.watch_outlined,
          text: const TextSpan(text: 'Hello'),
          actionLabel: 'Act',
          onAction: () => taps++,
        ),
      ),
    );
    expect(find.text('Not now'), findsNothing);
    await tester.tap(find.text('Act'));
    expect(taps, 1);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'two actions both fire and fit at text scale 2 in $brightness',
      (tester) async {
        var first = 0;
        var second = 0;
        await tester.pumpWidget(
          _app(
            brightness,
            InsightCard(
              icon: Icons.watch_outlined,
              text: const TextSpan(
                text: 'BeyondRep is not on your watch yet. Open the Watch app.',
              ),
              actionLabel: 'Show me how',
              onAction: () => first++,
              secondaryActionLabel: 'Not now',
              onSecondaryAction: () => second++,
            ),
            scale: 2,
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Show me how'));
        await tester.tap(find.text('Not now'));
        expect([first, second], [1, 1]);
      },
    );
  }
}
