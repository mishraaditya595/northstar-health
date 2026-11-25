import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/features/catalog/domain/canonical_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sorts keys by code point and removes whitespace', () {
    final bytes = canonicalJsonBytes({
      'b': 1,
      'a': [true, null, 'x'],
    });
    expect(utf8.decode(bytes), '{"a":[true,null,"x"],"b":1}');
  });

  test('keeps non-ASCII as UTF-8', () {
    final bytes = canonicalJsonBytes({'n': 'Sumo-Kreuzheben ü'});
    expect(bytes, containsAllInOrder([0xC3, 0xBC]));
  });

  test('escapes like Python', () {
    final text = utf8.decode(canonicalJsonBytes('a"b\\c\n\t\u0001/'));
    expect(text, r'"a\"b\\c\n\t\u0001/"');
  });

  test('rejects doubles', () {
    expect(() => canonicalJsonBytes({'x': 45.0}), throwsArgumentError);
  });

  test('matches published release 1', () {
    final sql = File(
      '../../supabase/migrations/20261126000100_catalog_release_1.sql',
    ).readAsStringSync();
    final start = sql.indexOf(r'$catalog$') + r'$catalog$'.length;
    final end = sql.indexOf(r'$catalog$', start);
    final body = sql.substring(start, end);
    final decoded = jsonDecode(body);

    final lock = jsonDecode(
      File('../../catalog/releases.lock.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final release1 = (lock['releases']! as List)
        .cast<Map<String, Object?>>()
        .firstWhere((r) => r['release'] == 1);

    expect(utf8.decode(canonicalJsonBytes(decoded)), body);
    expect(sha256Hex(canonicalJsonBytes(decoded)), release1['sha256']);
  });
}
