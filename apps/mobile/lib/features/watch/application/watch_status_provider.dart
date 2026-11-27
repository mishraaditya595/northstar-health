import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/watch_status_store.dart';
import '../domain/watch_status.dart';

/// Everything the UI shows about the watch. Fed by `WatchSyncController`;
/// it starts hidden, so a page built without the controller (signed out,
/// tests) shows nothing.
class WatchLinkState {
  const WatchLinkState({
    this.status = const WatchHidden(),
    this.device = WatchDeviceStatus.unsupported,
    this.sentSummary,
    this.installHintDismissed = false,
  });

  final WatchStatus status;
  final WatchDeviceStatus device;

  /// What the last context held ("Readiness, health, 3 plans"), null before
  /// anything was sent.
  final String? sentSummary;

  /// "Not now" was chosen on the install banner.
  final bool installHintDismissed;

  WatchLinkState copyWith({bool? installHintDismissed}) => WatchLinkState(
    status: status,
    device: device,
    sentSummary: sentSummary,
    installHintDismissed: installHintDismissed ?? this.installHintDismissed,
  );
}

/// Opens the store behind the confirmed time and the dismissed flag; tests
/// may replace it.
final watchStatusStoreProvider = Provider<Future<WatchStatusStore>>(
  (ref) => WatchStatusStore.open(),
);

class WatchLinkStateNotifier extends Notifier<WatchLinkState> {
  @override
  WatchLinkState build() => const WatchLinkState();

  void update(WatchLinkState next) => state = next;

  /// "Not now": hides the install banner for good on this phone.
  Future<void> dismissInstallHint() async {
    state = state.copyWith(installHintDismissed: true);
    try {
      await (await ref.read(watchStatusStoreProvider)).dismissInstallHint();
    } catch (_) {
      // The banner stays hidden for this session.
    }
  }
}

final watchLinkStateProvider =
    NotifierProvider<WatchLinkStateNotifier, WatchLinkState>(
      WatchLinkStateNotifier.new,
    );

/// The watch as the phone presents it; see [WatchStatus].
final watchStatusProvider = Provider<WatchStatus>(
  (ref) => ref.watch(watchLinkStateProvider.select((s) => s.status)),
);
