import 'package:beyondrep/features/health/domain/weight_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a comma or a point and rounds to 0.1', () {
    expect(parseWeightKg('72,4'), 72.4);
    expect(parseWeightKg(' 72.45 '), 72.5);
    expect(parseWeightKg('20'), 20.0);
    expect(parseWeightKg('400.04'), 400.0);
  });

  test('rejects anything else or out of range', () {
    expect(parseWeightKg('abc'), isNull);
    expect(parseWeightKg(''), isNull);
    expect(parseWeightKg('19.9'), isNull);
    expect(parseWeightKg('400.05'), isNull);
    expect(parseWeightKg('-70'), isNull);
    expect(parseWeightKg('1e2'), isNull);
    expect(parseWeightKg('.5'), isNull);
  });

  test('a very long digit string is rejected, not thrown on', () {
    expect(parseWeightKg('9' * 400), isNull);
  });

  test('a trailing separator is accepted', () {
    expect(parseWeightKg('72.'), 72.0);
    expect(parseWeightKg('72,'), 72.0);
  });
}
