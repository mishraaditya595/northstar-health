import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The word "readiness" is gone from user-visible text: every string literal
/// in lib/ avoids it, except the wire key `'readiness'` and route paths.
void main() {
  test('no user-visible string in lib/ says readiness', () {
    final literal = RegExp(r'''(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''');
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // Interpolated code is not text: `${readiness.x}` is an identifier.
        final line = lines[i].replaceAll(RegExp(r'\$\{[^{}]*\}'), '');
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') ||
            trimmed.startsWith('import ') ||
            trimmed.startsWith('export ')) {
          continue;
        }
        for (final m in literal.allMatches(line)) {
          final text = m.group(1) ?? m.group(2) ?? '';
          if (!RegExp('readiness', caseSensitive: false).hasMatch(text)) {
            continue;
          }
          if (text == 'readiness' || text.contains('/health/readiness')) {
            continue;
          }
          hits.add('${entity.path}:${i + 1}: $text');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
