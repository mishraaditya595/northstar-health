import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The opaque account key the watch holds instead of the user id (ADR-0012):
/// lowercase hex HMAC-SHA-256 of [userId] under a fixed app constant.
String watchAccountKey(String userId) => Hmac(
  sha256,
  utf8.encode('beyondrep.watch.account.v1'),
).convert(utf8.encode(userId)).toString();
