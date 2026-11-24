import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/dart_import_resolver.dart';

void main() {
  final dart = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
  String norm(File f) => f.path.replaceAll(r'\', '/');

  Set<String> importsOf(String path) => resolveImports(
    path,
    File(path).readAsStringSync(),
    packageName: 'beyondrep',
  );

  test('the resolver sees relative imports the old substring match missed', () {
    const source = "import '../health/data/health_reader.dart';";
    expect(source.contains('features/health/'), isFalse);
    expect(
      resolveImports(
        'lib/features/sync/sync_service.dart',
        source,
        packageName: 'beyondrep',
      ),
      {'lib/features/health/data/health_reader.dart'},
    );
  });

  test('the resolver handles package, export, conditional and plugin URIs', () {
    const source = '''
import 'package:beyondrep/features/health/health_page.dart' show X;
export "../../core/storage/a.dart";
import 'package:health/health.dart' as h;
import 'dart:io';
import 'sibling.dart'
    if (dart.library.io) 'other.dart';
''';
    expect(
      resolveImports(
        'lib/features/sync/deep/file.dart',
        source,
        packageName: 'beyondrep',
      ),
      {
        'lib/features/health/health_page.dart',
        'lib/features/core/storage/a.dart',
        'package:health/health.dart',
        'dart:io',
        'lib/features/sync/deep/sibling.dart',
        'lib/features/sync/deep/other.dart',
      },
    );
  });

  test('only platform_health_reader.dart imports package:health', () {
    final offenders = dart
        .map(norm)
        .where((p) => importsOf(p).any((i) => i.startsWith('package:health/')))
        .toSet();
    expect(offenders, {'lib/features/health/data/platform_health_reader.dart'});
  });

  test('sync, storage and workouts never import features/health', () {
    // account_gate.dart is the single permitted exception: it provides the
    // health reader override for the signed-in scope.
    const allowed = 'lib/features/account/account_gate.dart';
    final offenders = dart
        .map(norm)
        .where(
          (p) =>
              p.startsWith('lib/features/sync/') ||
              p.startsWith('lib/features/account/') ||
              p.startsWith('lib/core/storage/') ||
              p.startsWith('lib/features/workouts/'),
        )
        .where((p) => p != allowed)
        .where(
          (p) => importsOf(p).any((i) => i.startsWith('lib/features/health/')),
        )
        .toList();
    expect(offenders, isEmpty);
    expect(
      importsOf(allowed).any((i) => i.startsWith('lib/features/health/')),
      isTrue,
      reason: 'the explicit exception must still be needed',
    );
  });

  List<String> filesUnder(String dir) {
    final d = Directory(dir);
    expect(d.existsSync(), isTrue, reason: '$dir must exist');
    return dart.map(norm).where((p) => p.startsWith('$dir/')).toList();
  }

  test('health domain imports only dart: and domain files', () {
    final files = filesUnder('lib/features/health/domain');
    expect(files, isNotEmpty);
    final offenders = [
      for (final p in files)
        for (final i in importsOf(p))
          if (!i.startsWith('dart:') &&
              !i.startsWith('lib/features/health/domain/'))
            '$p -> $i',
    ];
    expect(offenders, isEmpty);
  });

  test('health application and domain never import objectbox or dart:io', () {
    final files = [
      ...filesUnder('lib/features/health/application'),
      ...filesUnder('lib/features/health/domain'),
    ];
    final offenders = [
      for (final p in files)
        for (final i in importsOf(p))
          if (i.contains('objectbox') || i == 'dart:io') '$p -> $i',
    ];
    expect(offenders, isEmpty);
  });
}
