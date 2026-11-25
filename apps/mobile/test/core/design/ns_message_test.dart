import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  Future<void> open(WidgetTester tester, void Function(BuildContext) show) =>
      tester.pumpWidget(
        MaterialApp(
          theme: BeyondRepTheme.build(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => show(context),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

  testWidgets('a plain message has no action', (tester) async {
    await open(tester, (c) => showNsMessage(c, 'Saved'));
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byType(SnackBarAction), findsNothing);
  });

  testWidgets('an action label runs its callback', (tester) async {
    var taps = 0;
    await open(
      tester,
      (c) => showNsMessage(
        c,
        'Saved to My Plans',
        actionLabel: 'Edit',
        onAction: () => taps++,
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    await tester.tap(find.text('Edit'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('a message with an action still times out', (tester) async {
    await open(
      tester,
      (c) => showNsMessage(c, 'Saved', actionLabel: 'Edit', onAction: () {}),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('Saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    test('the snackbar action is readable (${brightness.name})', () {
      final theme = BeyondRepTheme.build(brightness).snackBarTheme;
      expect(theme.actionTextColor, isNotNull);
      expect(
        _ratio(theme.actionTextColor!, theme.backgroundColor!),
        greaterThanOrEqualTo(4.5),
      );
    });
  }
}
