import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
