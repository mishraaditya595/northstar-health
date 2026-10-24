import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/design/stats.dart';

void main() {
  testWidgets('StatTile shows value, unit, trend and caption', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatTile(
            label: 'Volume',
            value: '12,400',
            unit: 'kg',
            trend: NsTrend.up,
            trendLabel: '8%',
            caption: 'This week',
          ),
        ),
      ),
    );
    expect(find.text('Volume'), findsOneWidget);
    expect(find.textContaining('12,400'), findsOneWidget);
    expect(find.text('8%'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('StatTile is tappable only when given a handler', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatTile(label: 'Time', value: '1h', onTap: () => taps++),
        ),
      ),
    );
    await tester.tap(find.byType(StatTile));
    expect(taps, 1);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('month grid starts on the right weekday and marks days', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NsMonthCalendar(
            month: DateTime.utc(2026, 10),
            highlighted: const {3, 20},
            today: DateTime.utc(2026, 10, 24),
          ),
        ),
      ),
    );
    expect(find.text('October 2026'), findsOneWidget);
    // 1 Oct 2026 is a Thursday: Sunday-first, so it sits in the fifth column.
    final headers = [
      for (final letter in const ['S', 'M', 'T', 'W', 'T', 'F', 'S']) letter,
    ];
    expect(headers, hasLength(7));
    final one = tester.getCenter(find.text('1'));
    final two = tester.getCenter(find.text('2'));
    final four = tester.getCenter(find.text('4')); // the first Sunday
    final eight = tester.getCenter(find.text('8')); // Thursday again
    expect(two.dx, greaterThan(one.dx));
    expect(eight.dx, closeTo(one.dx, 1));
    expect(one.dx - four.dx, closeTo(4 * (two.dx - one.dx), 1));
    expect(find.bySemanticsLabel('3 October, trained'), findsOneWidget);
    expect(find.bySemanticsLabel('24 October, today'), findsOneWidget);
    expect(find.bySemanticsLabel('4 October'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
  });

  testWidgets('arrows call back and can be disabled', (tester) async {
    var previous = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NsMonthCalendar(
            month: DateTime.utc(2026, 10),
            highlighted: const {},
            onPrevious: () => previous++,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Previous month'));
    expect(previous, 1);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_right),
          )
          .onPressed,
      isNull,
    );
  });
}
