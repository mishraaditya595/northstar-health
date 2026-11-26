import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'today_program_test_support.dart';

void main() {
  testWidgets('wide Today puts Recent health beside the hero', (tester) async {
    await pumpTodayProgram(
      tester,
      week: programWeekFixture(),
      size: const Size(1194, 834),
    );
    final health = tester.getTopLeft(find.text('Recent health'));
    final week = tester.getTopLeft(find.text('This week'));
    expect(health.dy, lessThan(week.dy));
    expect(health.dx, greaterThan(1194 / 2));
  });

  testWidgets('portrait iPad Today keeps one column', (tester) async {
    await pumpTodayProgram(
      tester,
      week: programWeekFixture(),
      size: const Size(820, 1180),
    );
    final health = tester.getTopLeft(find.text('Recent health'));
    final week = tester.getTopLeft(find.text('This week'));
    expect(health.dy, lessThan(week.dy));
    expect(health.dx, week.dx);
    // Narrow order: the hero is above Recent health.
    expect(tester.getTopLeft(find.text('Today').first).dy, lessThan(health.dy));
  });

  testWidgets('wide Today at 2x text has no overflow', (tester) async {
    await pumpTodayProgram(
      tester,
      week: programWeekFixture(),
      size: const Size(1366, 1024),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });
}
