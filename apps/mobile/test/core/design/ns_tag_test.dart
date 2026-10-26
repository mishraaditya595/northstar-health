import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/design/northstar_theme.dart';
import 'package:northstar_health/core/design/page_header.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('warning tag uses prototype amber in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NorthstarTheme.build(brightness),
          home: const Scaffold(body: NsTag('Needs review', warning: true)),
        ),
      );
      final text = tester.widget<Text>(find.text('Needs review'));
      expect(
        text.style!.color,
        brightness == Brightness.dark
            ? NorthstarPalette.amberDark
            : NorthstarPalette.amberLight,
      );
    });
  }
}
