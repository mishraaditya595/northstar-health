import 'package:beyondrep/features/watch/domain/watch_account_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const user = '00000000-0000-4000-8000-000000000001';

  test('same user gives the same 64-hex key', () {
    final key = watchAccountKey(user);
    expect(key, watchAccountKey(user));
    expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('different users give different keys', () {
    expect(
      watchAccountKey(user),
      isNot(watchAccountKey('00000000-0000-4000-8000-000000000002')),
    );
  });

  test('key does not contain the user id', () {
    expect(watchAccountKey(user), isNot(contains('00000000')));
  });

  test('known vector', () {
    expect(
      watchAccountKey(user),
      '8318745b2c23be8d735f953dd25a130436b1c29235843acbe1803b71485d883f',
    );
  });
}
