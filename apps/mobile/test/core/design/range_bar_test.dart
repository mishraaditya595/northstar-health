import 'package:beyondrep/core/design/charts/range_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _bar({double? value}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 300,
      child: NsRangeBar(low: 55, high: 61, value: value, min: 40, max: 80),
    ),
  ),
);

void main() {
  testWidgets('no marker without a value', (tester) async {
    await tester.pumpWidget(_bar());
    expect(find.byKey(const Key('ns-range-marker')), findsNothing);
  });

  testWidgets('marker shows for a value and clamps outside the range', (
    tester,
  ) async {
    await tester.pumpWidget(_bar(value: 58));
    expect(find.byKey(const Key('ns-range-marker')), findsOneWidget);
    await tester.pumpWidget(_bar(value: 500));
    expect(tester.takeException(), isNull);
    final marker = tester.getRect(find.byKey(const Key('ns-range-marker')));
    final bar = tester.getRect(find.byType(NsRangeBar));
    expect(marker.right, lessThanOrEqualTo(bar.right));
    await tester.pumpWidget(_bar(value: -5));
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byKey(const Key('ns-range-marker'))).left,
      greaterThanOrEqualTo(bar.left),
    );
  });
}
