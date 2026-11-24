import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final dart = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
  String norm(File f) => f.path.replaceAll(r'\', '/');

  test(
    'only the platform reader and the account gate wiring import the plugin',
    () {
      final offenders = dart
          .where((f) => f.readAsStringSync().contains('package:health/'))
          .map(norm)
          .toSet();
      expect(offenders, {
        'lib/features/account/account_gate.dart',
        'lib/features/health/data/platform_health_reader.dart',
      });
    },
  );

  test('sync, storage and workouts never import features/health', () {
    final offenders = dart
        .map(norm)
        .where(
          (p) =>
              p.startsWith('lib/features/sync/') ||
              p.startsWith('lib/features/account/') ||
              p.startsWith('lib/core/storage/') ||
              p.startsWith('lib/features/workouts/'),
        )
        .where((p) => p != 'lib/features/account/account_gate.dart')
        .where((p) => File(p).readAsStringSync().contains('features/health/'))
        .toList();
    expect(offenders, isEmpty);
  });
}
