import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/page_header.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('warning tag uses prototype amber in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BeyondRepTheme.build(brightness),
          home: const Scaffold(body: NsTag('Needs review', warning: true)),
        ),
      );
      final text = tester.widget<Text>(find.text('Needs review'));
      expect(
        text.style!.color,
        brightness == Brightness.dark
            ? BeyondRepPalette.amberDark
            : BeyondRepPalette.amberLight,
      );
    });
  }
}
