import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files whose `'readiness'` literal is the unchanged watch wire key.
const _wireKeyFiles = {
  'lib/features/watch/domain/watch_message.dart',
  'lib/features/watch/application/watch_snapshots.dart',
};

/// The `file:line: text` hits for user-visible "readiness" in [lines].
List<String> readinessHits(String path, List<String> lines) {
  final literal = RegExp(r'''(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''');
  final hits = <String>[];
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
      if (!RegExp('readiness', caseSensitive: false).hasMatch(text)) continue;
      if (text == 'readiness' && _wireKeyFiles.contains(path)) continue;
      if (text.contains('/health/readiness')) continue;
      hits.add('$path:${i + 1}: $text');
    }
  }
  return hits;
}

/// The word "readiness" is gone from user-visible text: every string literal
/// in lib/ avoids it, except the wire key in the watch files and route paths.
void main() {
  test('no user-visible string in lib/ says readiness', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      hits.addAll(readinessHits(entity.path, entity.readAsLinesSync()));
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('the bare wire key is exempt only in the watch files', () {
    const line = "if (hasReadiness) 'readiness',";
    expect(
      readinessHits('lib/features/watch/domain/watch_status.dart', [line]),
      hasLength(1),
    );
    expect(
      readinessHits('lib/features/watch/domain/watch_message.dart', [line]),
      isEmpty,
    );
    expect(
      readinessHits('lib/features/watch/application/watch_snapshots.dart', [
        line,
      ]),
      isEmpty,
    );
    expect(readinessHits('lib/x.dart', ["Text('Readiness 5')"]), hasLength(1));
    expect(
      readinessHits('lib/x.dart', ["context.push('/health/readiness')"]),
      isEmpty,
    );
  });
}
