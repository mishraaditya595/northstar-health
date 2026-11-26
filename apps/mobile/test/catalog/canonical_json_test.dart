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

  test('allows 32 levels of nesting and rejects 33 with ArgumentError', () {
    Object nested(int depth) {
      Object value = 'leaf';
      for (var i = 0; i < depth; i++) {
        value = [value];
      }
      return value;
    }

    expect(canonicalJsonBytes(nested(32)), isNotEmpty);
    expect(() => canonicalJsonBytes(nested(33)), throwsArgumentError);
    // A hostile depth fails fast instead of overflowing the stack.
    expect(() => canonicalJsonBytes(nested(100000)), throwsArgumentError);
    Object nestedMap(int depth) {
      Object value = 1;
      for (var i = 0; i < depth; i++) {
        value = {'k': value};
      }
      return value;
    }

    expect(canonicalJsonBytes(nestedMap(32)), isNotEmpty);
    expect(() => canonicalJsonBytes(nestedMap(33)), throwsArgumentError);
  });

  test('maxBytes stops a hostile document early with ArgumentError', () {
    final huge = {'k': 'x' * (50 * 1024 * 1024)};
    expect(() => canonicalJsonBytes(huge, maxBytes: 1000), throwsArgumentError);
    // Exactly at the cap is fine, one byte over is not (multi-byte aware).
    final bytes = canonicalJsonBytes({'n': 'ü'});
    expect(canonicalJsonBytes({'n': 'ü'}, maxBytes: bytes.length), bytes);
    expect(
      () => canonicalJsonBytes({'n': 'ü'}, maxBytes: bytes.length - 1),
      throwsArgumentError,
    );
  });
}
