import 'dart:math';

/// A cryptographically random, non-identifying version-4 UUID.
abstract interface class UuidFactory {
  String newId();
}

class SecureUuidFactory implements UuidFactory {
  SecureUuidFactory() : _random = Random.secure();
  final Random _random;

  @override
  String newId() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
