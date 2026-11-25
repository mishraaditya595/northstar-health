import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/hero_frame.dart';

Widget _host(Widget child, {double width = 360, double scale = 1}) =>
    MaterialApp(
      theme: BeyondRepTheme.build(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

void main() {
  testWidgets('renders text, filled first action and slots', (tester) async {
    var primary = 0;
    await tester.pumpWidget(
      _host(
        NsHeroFrame(
          eyebrow: 'READINESS',
          title: 'Ready',
          subtitle: 'Slept well',
          leading: const SizedBox(key: Key('lead'), width: 60, height: 60),
          actions: [
            NsHeroAction('Go', () => primary++),
            NsHeroAction('More', () {}),
          ],
          child: const SizedBox(key: Key('kid'), height: 20),
        ),
      ),
    );
    expect(find.text('READINESS'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Slept well'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    expect(primary, 1);
    final lead = tester.getRect(find.byKey(const Key('lead')));
    final title = tester.getRect(find.text('Ready'));
    expect(lead.right + 14, lessThanOrEqualTo(title.left));
    final sub = tester.getRect(find.text('Slept well'));
    final kid = tester.getRect(find.byKey(const Key('kid')));
    expect(kid.top - sub.bottom, 12);
    expect(kid.bottom, lessThan(tester.getRect(find.byType(FilledButton)).top));
  });

  testWidgets('null title shows spinner and hides slots', (tester) async {
    await tester.pumpWidget(
      _host(
        const NsHeroFrame(
          eyebrow: 'NEXT UP',
          leading: SizedBox(key: Key('lead')),
          child: SizedBox(key: Key('kid')),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('lead')), findsNothing);
    expect(find.byKey(const Key('kid')), findsNothing);
  });

  testWidgets('text scale 2.0 at 320 px does not overflow', (tester) async {
    await tester.pumpWidget(
      _host(
        NsHeroFrame(
          eyebrow: 'READINESS',
          title: 'Ready to train today',
          subtitle: 'Sleep and resting heart rate look steady this week.',
          leading: const SizedBox(width: 72, height: 72),
          actions: [NsHeroAction('Open', () {}), NsHeroAction('More', () {})],
          child: const Wrap(children: [Text('Sleep 82'), Text('HRV 41')]),
        ),
        width: 320,
        scale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
