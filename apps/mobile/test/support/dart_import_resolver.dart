/// Test-only: every import/export URI of a Dart source, resolved to a
/// normalized `lib/...` path (relative and `package:<name>/` URIs), or kept
/// as written for `dart:` and other packages.
Set<String> resolveImports(
  String filePath,
  String source, {
  required String packageName,
}) {
  final directive = RegExp(
    r'''^\s*(?:import|export)\s+([^;]+);''',
    multiLine: true,
  );
  final uri = RegExp(r'''['"]([^'"]+)['"]''');
  final result = <String>{};
  for (final d in directive.allMatches(source)) {
    for (final u in uri.allMatches(d.group(1)!)) {
      final value = u.group(1)!;
      if (value.startsWith('package:$packageName/')) {
        result.add(
          _normalize('lib/${value.substring(9 + packageName.length)}'),
        );
      } else if (value.contains(':')) {
        result.add(value);
      } else {
        final dir = filePath.substring(0, filePath.lastIndexOf('/') + 1);
        result.add(_normalize('$dir$value'));
      }
    }
  }
  return result;
}

String _normalize(String path) {
  final out = <String>[];
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (out.isNotEmpty) out.removeLast();
    } else {
      out.add(part);
    }
  }
  return out.join('/');
}
