/// Strict JSON reading shared by the watch contract codecs. The schemas under
/// `contracts/` forbid unknown keys and fix every range, so a lenient reader
/// would accept messages the other platforms reject.
class WatchContractException implements Exception {
  const WatchContractException(this.code);

  /// One of `unsupported_version`, `unknown_type`, `unknown_key`,
  /// `missing_field`, `invalid_value`.
  final String code;

  @override
  String toString() => 'WatchContractException($code)';
}

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final _dateTimePattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}[Tt]\d{2}:\d{2}:\d{2}(\.\d+)?([Zz]|[+-]\d{2}:\d{2})$',
);
final _accountKeyPattern = RegExp(r'^[0-9a-f]{64}$');
final _localDatePattern = RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$');

/// An object whose keys were checked against a required and optional set.
class StrictObject {
  StrictObject(
    Object? raw, {
    required Set<String> required,
    Set<String> optional = const {},
  }) : map = _asMap(raw) {
    for (final key in map.keys) {
      if (!required.contains(key) && !optional.contains(key)) {
        throw const WatchContractException('unknown_key');
      }
    }
    for (final key in required) {
      if (!map.containsKey(key)) {
        throw const WatchContractException('missing_field');
      }
    }
  }

  final Map<String, Object?> map;

  static Map<String, Object?> _asMap(Object? raw) {
    if (raw is! Map) throw const WatchContractException('invalid_value');
    final out = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) throw const WatchContractException('invalid_value');
      out[key] = entry.value;
    }
    return out;
  }

  bool has(String key) => map.containsKey(key);

  String string(String key, {int min = 1, int? max, RegExp? pattern}) {
    final v = map[key];
    // JSON Schema counts Unicode code points, not UTF-16 units.
    if (v is! String ||
        v.runes.length < min ||
        (max != null && v.runes.length > max)) {
      throw const WatchContractException('invalid_value');
    }
    if (pattern != null && !pattern.hasMatch(v)) {
      throw const WatchContractException('invalid_value');
    }
    return v;
  }

  String? optionalString(String key, {int min = 1, int? max}) =>
      has(key) ? string(key, min: min, max: max) : null;

  String uuid(String key) => string(key, pattern: _uuidPattern);

  String dateTime(String key) {
    final v = string(key, pattern: _dateTimePattern);
    // DateTime.tryParse rolls 2026-02-30 over to March, so check each part.
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[Tt](\d{2}):(\d{2}):(\d{2})')
        .firstMatch(v)!;
    final year = int.parse(m[1]!);
    final month = int.parse(m[2]!);
    final day = int.parse(m[3]!);
    final offset = RegExp(r'[+-](\d{2}):(\d{2})$').firstMatch(v);
    final valid =
        month >= 1 &&
        month <= 12 &&
        day >= 1 &&
        day <= DateTime.utc(year, month + 1, 0).day &&
        int.parse(m[4]!) <= 23 &&
        int.parse(m[5]!) <= 59 &&
        int.parse(m[6]!) <= 59 &&
        (offset == null ||
            (int.parse(offset[1]!) <= 23 && int.parse(offset[2]!) <= 59));
    if (!valid) throw const WatchContractException('invalid_value');
    return v;
  }

  String accountKey() => string('account_key', pattern: _accountKeyPattern);

  String localDate(String key) => string(key, pattern: _localDatePattern);

  String oneOf(String key, Set<String> allowed) {
    final v = map[key];
    if (v is! String || !allowed.contains(v)) {
      throw const WatchContractException('invalid_value');
    }
    return v;
  }

  int integer(String key, {int min = 0, int? max}) {
    final v = map[key];
    if (v is! num || v != v.truncate()) {
      throw const WatchContractException('invalid_value');
    }
    final n = v.toInt();
    if (n < min || (max != null && n > max)) {
      throw const WatchContractException('invalid_value');
    }
    return n;
  }

  int? optionalInteger(String key, {int min = 0, int? max}) =>
      has(key) ? integer(key, min: min, max: max) : null;

  bool boolean(String key) {
    final v = map[key];
    if (v is! bool) throw const WatchContractException('invalid_value');
    return v;
  }

  /// A number from 1 to 10 in half steps.
  num rpe(String key) {
    final v = map[key];
    if (v is! num || v < 1 || v > 10 || (v * 2) != (v * 2).truncate()) {
      throw const WatchContractException('invalid_value');
    }
    return v;
  }

  num? optionalRpe(String key) => has(key) ? rpe(key) : null;

  StrictObject object(
    String key, {
    required Set<String> required,
    Set<String> optional = const {},
  }) => StrictObject(map[key], required: required, optional: optional);

  List<Object?> list(String key, {int? max}) {
    final v = map[key];
    if (v is! List || (max != null && v.length > max)) {
      throw const WatchContractException('invalid_value');
    }
    return v;
  }

  /// A deep copy of the value so callers cannot change a decoded message.
  Map<String, Object?> copyOfObject(String key) =>
      _deepCopy(_asMap(map[key]))! as Map<String, Object?>;
}

Object? _deepCopy(Object? v) {
  if (v is Map) {
    return {for (final e in v.entries) e.key as String: _deepCopy(e.value)};
  }
  if (v is List) return [for (final e in v) _deepCopy(e)];
  return v;
}

Object? deepCopyJson(Object? v) => _deepCopy(v);
