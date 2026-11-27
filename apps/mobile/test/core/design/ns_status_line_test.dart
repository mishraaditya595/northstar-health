import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/status_line.dart';
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
  testWidgets('shows its text and reports taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        Brightness.light,
        NsStatusLine('Apple Watch · synced 10:43', onTap: () => taps++),
      ),
    );
    expect(find.text('Apple Watch · synced 10:43'), findsOneWidget);
    await tester.tap(find.text('Apple Watch · synced 10:43'));
    expect(taps, 1);
  });

  testWidgets('without onTap it is plain text, not a button', (tester) async {
    await tester.pumpWidget(
      _app(Brightness.light, const NsStatusLine('Quiet')),
    );
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('the tap target is at least 48 dp tall', (tester) async {
    await tester.pumpWidget(
      _app(Brightness.light, NsStatusLine('Quiet', onTap: () {})),
    );
    expect(
      tester.getSize(find.byType(InkWell)).height,
      greaterThanOrEqualTo(48),
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('wraps at text scale 2 in $brightness', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          SizedBox(
            width: 320,
            child: NsStatusLine('Apple Watch · synced 10:43', onTap: () {}),
          ),
          scale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
