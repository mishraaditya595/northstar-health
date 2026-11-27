import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One `account_cleared` (wipe unsent) message waiting for the watch to
/// confirm it. The JSON holds the account key HMAC, never the user id.
class PendingWatchWipe {
  const PendingWatchWipe({required this.messageId, required this.json});

  final String messageId;
  final String json;
}

/// Account deletion removes the account store, so the wipe the watch still
/// owes an answer for is kept in preferences outside it. Not cleared by
/// `WatchStatusStore.clear()`; an entry leaves only when the watch acks it.
class WatchWipeQueue {
  WatchWipeQueue(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'watch_link.pending_wipes';
  static const _keep = 10;

  static Future<WatchWipeQueue> open() async =>
      WatchWipeQueue(await SharedPreferences.getInstance());

  List<PendingWatchWipe> pending() {
    try {
      final raw = _prefs.getString(_key);
      if (raw == null) return const [];
      return [
        for (final item in jsonDecode(raw) as List<Object?>)
          if (item case {
            'message_id': final String id,
            'json': final String json,
          })
            PendingWatchWipe(messageId: id, json: json),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> add(PendingWatchWipe wipe) {
    final all = [
      for (final w in pending())
        if (w.messageId != wipe.messageId) w,
      wipe,
    ];
    return _write(all.length > _keep ? all.sublist(all.length - _keep) : all);
  }

  Future<void> remove(String messageId) {
    final all = pending();
    final kept = [
      for (final w in all)
        if (w.messageId != messageId) w,
    ];
    if (kept.length == all.length) return Future.value();
    return _write(kept);
  }

  Future<void> _write(List<PendingWatchWipe> wipes) => _prefs.setString(
    _key,
    jsonEncode([
      for (final w in wipes) {'message_id': w.messageId, 'json': w.json},
    ]),
  );
}
