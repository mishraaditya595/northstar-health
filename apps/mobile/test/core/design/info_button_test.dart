import 'package:beyondrep/core/design/info_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('info button has a 48 dp target and a labelled tap', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: NsInfoButton(
              label: 'About Resting heart rate',
              onPressed: () => taps++,
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(NsInfoButton));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    await tester.tap(find.bySemanticsLabel('About Resting heart rate'));
    expect(taps, 1);
  });
}
