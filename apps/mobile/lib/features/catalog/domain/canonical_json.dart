import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Canonical bytes equal to Python's
/// `json.dumps(v, sort_keys=True, separators=(",", ":"), ensure_ascii=False)`
/// encoded as UTF-8. Doubles are rejected: the catalogue only has integers.
Uint8List canonicalJsonBytes(Object? value) {
  final buffer = StringBuffer();
  _write(buffer, value, 0);
  return Uint8List.fromList(utf8.encode(buffer.toString()));
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Containers may nest at most this deep; a snapshot is about six levels.
const maxCanonicalDepth = 32;

void _write(StringBuffer out, Object? value, int depth) {
  if ((value is List || value is Map) && depth >= maxCanonicalDepth) {
    throw ArgumentError('Canonical JSON nests deeper than $maxCanonicalDepth');
  }
  if (value == null) {
    out.write('null');
  } else if (value is bool) {
    out.write(value ? 'true' : 'false');
  } else if (value is int) {
    out.write(value.toString());
  } else if (value is double) {
    throw ArgumentError('Doubles are not allowed in canonical JSON');
  } else if (value is String) {
    _writeString(out, value);
  } else if (value is List) {
    out.write('[');
    for (var i = 0; i < value.length; i++) {
      if (i > 0) out.write(',');
      _write(out, value[i], depth + 1);
    }
    out.write(']');
  } else if (value is Map) {
    final keys = <String>[];
    for (final key in value.keys) {
      if (key is! String) {
        throw ArgumentError('Canonical JSON object keys must be strings');
      }
      keys.add(key);
    }
    keys.sort(_compareCodePoints);
    out.write('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) out.write(',');
      _writeString(out, keys[i]);
      out.write(':');
      _write(out, value[keys[i]], depth + 1);
    }
    out.write('}');
  } else {
    throw ArgumentError('Unsupported canonical JSON type ${value.runtimeType}');
  }
}

int _compareCodePoints(String a, String b) {
  final ar = a.runes.iterator;
  final br = b.runes.iterator;
  while (true) {
    final hasA = ar.moveNext();
    final hasB = br.moveNext();
    if (!hasA || !hasB) {
      if (hasA == hasB) return 0;
      return hasA ? 1 : -1;
    }
    if (ar.current != br.current) return ar.current.compareTo(br.current);
  }
}

void _writeString(StringBuffer out, String value) {
  out.write('"');
  for (final unit in value.codeUnits) {
    switch (unit) {
      case 0x22:
        out.write(r'\"');
      case 0x5C:
        out.write(r'\\');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case 0x08:
        out.write(r'\b');
      case 0x0C:
        out.write(r'\f');
      default:
        if (unit < 0x20) {
          out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(unit);
        }
    }
  }
  out.write('"');
}
