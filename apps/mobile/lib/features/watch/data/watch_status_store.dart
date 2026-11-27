import 'package:shared_preferences/shared_preferences.dart';

/// What the watch status remembers across launches: when the watch last
/// confirmed a sync and the oldest send it has not confirmed since, per
/// account, and that the install banner was dismissed. Both are timestamps or flags; no health values are kept here.
/// Cleared on sign-out and account deletion.
class WatchStatusStore {
  WatchStatusStore(this._prefs);

  final SharedPreferences _prefs;

  static const _confirmedPrefix = 'watch_status.confirmed.';
  static const _unconfirmedPrefix = 'watch_status.unconfirmed.';
  static const _dismissedKey = 'watch_status.install_hint_dismissed';

  static Future<WatchStatusStore> open() async =>
      WatchStatusStore(await SharedPreferences.getInstance());

  /// Clears without keeping a store open, for the account-deletion path that
  /// runs after the signed-in scope is gone.
  static Future<void> clearStored() async {
    try {
      await (await open()).clear();
    } catch (_) {
      // Nothing to clear when preferences are unavailable.
    }
  }

  /// When the watch last confirmed it stored data for [accountKey].
  DateTime? confirmedAt(String accountKey) {
    final ms = _prefs.getInt('$_confirmedPrefix$accountKey');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setConfirmedAt(String accountKey, DateTime at) =>
      _prefs.setInt('$_confirmedPrefix$accountKey', at.millisecondsSinceEpoch);

  /// The time of the oldest send to [accountKey] the watch has not confirmed
  /// since; null when nothing is waiting for a confirmation.
  DateTime? unconfirmedSince(String accountKey) {
    final ms = _prefs.getInt('$_unconfirmedPrefix$accountKey');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setUnconfirmedSince(String accountKey, DateTime at) => _prefs
      .setInt('$_unconfirmedPrefix$accountKey', at.millisecondsSinceEpoch);

  Future<void> clearUnconfirmed(String accountKey) =>
      _prefs.remove('$_unconfirmedPrefix$accountKey');

  bool get installHintDismissed => _prefs.getBool(_dismissedKey) ?? false;

  Future<void> dismissInstallHint() => _prefs.setBool(_dismissedKey, true);

  Future<void> clear() async {
    // All removals start at once, so the cache is already clean when a read
    // follows the call.
    await Future.wait([
      for (final key in _prefs.getKeys().toList())
        if (key.startsWith(_confirmedPrefix) ||
            key.startsWith(_unconfirmedPrefix) ||
            key == _dismissedKey)
          _prefs.remove(key),
    ]);
  }
}
