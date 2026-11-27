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

  testWidgets('onTap makes the whole card a tap target with visible ink', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        Brightness.light,
        InsightCard(
          icon: Icons.watch_outlined,
          text: const TextSpan(text: 'Whole card'),
          onTap: () => taps++,
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(InsightCard),
        matching: find.byType(InkWell),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Whole card'));
    expect(taps, 1);
  });

  testWidgets('without onTap there is no ink well', (tester) async {
    await tester.pumpWidget(
      _app(
        Brightness.light,
        const InsightCard(
          icon: Icons.watch_outlined,
          text: TextSpan(text: 'Plain'),
        ),
      ),
    );
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('each two-action button meets the tap target guideline', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        Brightness.light,
        InsightCard(
          icon: Icons.watch_outlined,
          text: const TextSpan(text: 'Hello'),
          actionLabel: 'Show me how',
          onAction: () {},
          secondaryActionLabel: 'Not now',
          onSecondaryAction: () {},
        ),
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  group('layout', () {
    const banner = TextSpan(
      children: [
        TextSpan(
          text: "BeyondRep isn't on your watch yet",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        TextSpan(
          text:
              '\nOpen the Watch app on this iPhone, find BeyondRep under '
              'Available Apps and tap Install.',
        ),
      ],
    );
    final messageFinder = find.descendant(
      of: find.byType(InsightCard),
      matching: find.textContaining("BeyondRep isn't", findRichText: true),
    );

    Future<void> pump(
      WidgetTester tester, {
      required bool two,
      TextDirection direction = TextDirection.ltr,
      double scale = 1,
    }) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          Brightness.light,
          Directionality(
            textDirection: direction,
            // In a list, as on Today, so the card takes its own height.
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                InsightCard(
                  icon: Icons.watch_outlined,
                  text: banner,
                  actionLabel: 'Show me how',
                  onAction: () {},
                  secondaryActionLabel: two ? 'Not now' : null,
                  onSecondaryAction: two ? () {} : null,
                ),
              ],
            ),
          ),
          scale: scale,
        ),
      );
    }

    testWidgets('two actions start under the message text', (tester) async {
      await pump(tester, two: true);
      final label = tester.getTopLeft(find.text('Show me how')).dx;
      expect(label, closeTo(tester.getTopLeft(messageFinder).dx, 0.5));
    });

    testWidgets('two actions leave no tall band under the labels', (
      tester,
    ) async {
      await pump(tester, two: true);
      final card = tester.getRect(find.byType(InsightCard));
      final label = tester.getRect(find.text('Not now'));
      expect(card.bottom - label.bottom, lessThanOrEqualTo(20));
    });

    testWidgets('two actions line up with the text in RTL', (tester) async {
      await pump(tester, two: true, direction: TextDirection.rtl);
      final text = tester.getTopRight(messageFinder).dx;
      expect(
        tester.getTopRight(find.text('Show me how')).dx,
        closeTo(text, 0.5),
      );
    });

    testWidgets('two actions line up with the text at text scale 1.3', (
      tester,
    ) async {
      await pump(tester, two: true, scale: 1.3);
      final text = tester.getTopLeft(messageFinder).dx;
      expect(
        tester.getTopLeft(find.text('Show me how')).dx,
        closeTo(text, 0.5),
      );
      expect(tester.getTopLeft(find.text('Not now')).dx, closeTo(text, 0.5));
    });

    testWidgets('one action stays on the message row', (tester) async {
      await pump(tester, two: false);
      final text = tester.getRect(messageFinder);
      final dy = tester.getCenter(find.text('Show me how')).dy;
      expect(dy, inInclusiveRange(text.top, text.bottom));
    });
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
