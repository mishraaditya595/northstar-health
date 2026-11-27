/// What iOS says about the paired Apple Watch. No watch is the same as an
/// unsupported device (iPad, Android): nothing about it is shown.
class WatchDeviceStatus {
  const WatchDeviceStatus({
    required this.supported,
    required this.paired,
    required this.installed,
    required this.reachable,
  });

  static const unsupported = WatchDeviceStatus(
    supported: false,
    paired: false,
    installed: false,
    reachable: false,
  );

  final bool supported;
  final bool paired;

  /// The BeyondRep watch app is installed on the paired watch.
  final bool installed;
  final bool reachable;

  @override
  bool operator ==(Object other) =>
      other is WatchDeviceStatus &&
      other.supported == supported &&
      other.paired == paired &&
      other.installed == installed &&
      other.reachable == reachable;

  @override
  int get hashCode => Object.hash(supported, paired, installed, reachable);
}

/// The watch as the phone presents it. "Synced" only ever means the watch
/// sent an acknowledgment back; the phone never claims one it has not heard.
sealed class WatchStatus {
  const WatchStatus();
}

/// No paired watch, an unsupported device, or signed out: show nothing.
final class WatchHidden extends WatchStatus {
  const WatchHidden();
}

/// A watch is paired but BeyondRep is not on it.
final class WatchNotInstalled extends WatchStatus {
  const WatchNotInstalled();
}

/// The app is installed and the watch has not confirmed anything yet.
final class WatchWaiting extends WatchStatus {
  const WatchWaiting();
}

final class WatchSynced extends WatchStatus {
  const WatchSynced(this.at);

  /// When the phone last heard a confirmation from the watch.
  final DateTime at;

  @override
  bool operator ==(Object other) => other is WatchSynced && other.at == at;

  @override
  int get hashCode => Object.hash(WatchSynced, at);
}

final class WatchStale extends WatchStatus {
  const WatchStale(this.at);

  /// The last confirmation, 48 hours or more ago.
  final DateTime at;

  @override
  bool operator ==(Object other) => other is WatchStale && other.at == at;

  @override
  int get hashCode => Object.hash(WatchStale, at);
}

const watchStaleAfter = Duration(hours: 48);

WatchStatus watchStatusOf({
  required WatchDeviceStatus device,
  required bool signedIn,
  required DateTime? lastConfirmedAt,
  required DateTime? lastSentAt,
  required DateTime now,
}) {
  if (!signedIn || !device.supported || !device.paired) {
    return const WatchHidden();
  }
  if (!device.installed) return const WatchNotInstalled();
  final confirmed = lastConfirmedAt;
  if (confirmed == null) return const WatchWaiting();
  // Stale needs something sent after the last confirmation: with nothing
  // newer to confirm, the old confirmation is still the truth.
  final sentSince = lastSentAt != null && lastSentAt.isAfter(confirmed);
  if (sentSince && now.difference(confirmed) >= watchStaleAfter) {
    return WatchStale(confirmed);
  }
  return WatchSynced(confirmed);
}

/// `Readiness, health, 3 plans`: what the last context held, or null when it
/// held nothing.
String? watchSentSummary({
  required bool hasReadiness,
  required bool hasHealth,
  required int planCount,
}) {
  final parts = [
    if (hasReadiness) 'readiness',
    if (hasHealth) 'health',
    if (planCount > 0) '$planCount ${planCount == 1 ? 'plan' : 'plans'}',
  ];
  if (parts.isEmpty) return null;
  final text = parts.join(', ');
  return text[0].toUpperCase() + text.substring(1);
}
