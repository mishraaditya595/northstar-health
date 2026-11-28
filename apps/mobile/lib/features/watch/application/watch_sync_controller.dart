import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/ids/uuid_factory.dart';
import '../../account/account_auth_controller.dart';
import '../../account/account_auth_provider.dart';
import '../../health/application/health_overview.dart';
import '../../progress/workout_history_state.dart';
import '../../programs/application/program_providers.dart';
import '../../train/train_library_state.dart';
import '../data/watch_link.dart';
import '../data/watch_status_store.dart';
import '../data/watch_wipe_queue.dart';
import '../domain/watch_account_key.dart';
import '../domain/watch_message.dart';
import '../domain/watch_status.dart';
import 'watch_snapshots.dart';
import 'watch_status_provider.dart';
import 'watch_wipe_retrier.dart';
import 'phone_live_session.dart';
import 'watch_workout_health_inbox.dart';
import 'watch_workout_inbox.dart';

/// Ids for outgoing watch messages; tests replace it.
final watchMessageIdsProvider = Provider<UuidFactory>(
  (ref) => SecureUuidFactory(),
);

/// Tells the watch an account was permanently deleted so it drops that
/// account's unsent workouts too. Reads no provider, so the account
/// controller can call it after the signed-in scope has gone. Does nothing
/// unless a watch with the app is paired: then the wipe is persisted first
/// (outside the account store, which deletion removes) and resent by
/// `WatchWipeRetrier` until the watch acks it. Nothing is persisted on
/// Android or without a paired watch with the app, so no deleted account's
/// key is left behind. Sends nothing now when the watch is out of reach.
Future<void> announceWatchAccountDeleted({
  required WatchLink link,
  required String userId,
  required UuidFactory ids,
  required DateTime nowUtc,
  required Future<WatchWipeQueue> queue,
}) async {
  // Listened to now so a failing open is never reported as unhandled.
  final opened = queue.then<WatchWipeQueue?>((q) => q, onError: (_) => null);
  final device = await link.status();
  if (!device.supported || !device.paired || !device.installed) return;
  final messageId = ids.newId();
  final json = jsonEncode(
    buildAccountCleared(
      accountKey: watchAccountKey(userId),
      wipeUnsent: true,
      messageId: messageId,
      nowUtc: nowUtc,
    ).toJson(),
  );
  try {
    await (await opened)?.add(
      PendingWatchWipe(messageId: messageId, json: json),
    );
  } catch (_) {
    // Never stops the immediate send.
  }
  if (!await link.isReachableForUpdates()) return;
  await link.transfer(json);
  // The context holds the clear too, so the old context a watch replays on
  // launch is gone and cannot bring the account back.
  await link.updateContext({'account_cleared': json});
}

const _debounce = Duration(seconds: 2);

/// Keeps the watch's account binding, plans and today's health current. The
/// phone owns the data: it builds the messages and pushes the latest of each
/// as one application context. Nothing is sent without a paired watch with
/// the app, and identical content is never sent twice.
class WatchSyncController {
  WatchSyncController(this._ref)
    : _auth = _ref.read(accountAuthControllerProvider),
      _link = _ref.read(watchLinkProvider),
      _ids = _ref.read(watchMessageIdsProvider),
      _clock = _ref.read(wallClockProvider),
      _store = _openStore(_ref.read(watchStatusStoreProvider)) {
    _lastUser = _auth?.userId;
    _auth?.addListener(_onAuthChanged);
    _lifecycle = AppLifecycleListener(onResume: _schedule);
    _ref.listen(healthOverviewProvider, (_, _) => _schedule());
    _ref.listen(trainLibraryProvider, (_, _) => _schedule());
    _ref.listen(programWeekProvider, (_, _) => _schedule());
    _ref.listen(completedWorkoutHistoryProvider, (_, _) => _schedule());
    _ref.listen(localNowProvider, (_, _) => _schedule());
    _stateChanges = _link.watchStateChanges.listen((_) {
      // The watch may be new or may only now be reachable: send everything.
      _lastSignature = null;
      _schedule();
    });
    _reachability = _link.watchReachabilityChanges.listen(
      (_) => unawaited(_refreshDevice()),
    );
    unawaited(_loadPersisted());
    _schedule();
  }

  final Ref _ref;
  final AccountAuthController? _auth;
  final WatchLink _link;
  final UuidFactory _ids;
  final DateTime Function() _clock;
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<void> _stateChanges;
  late final StreamSubscription<void> _reachability;
  StreamSubscription<String>? _messages;
  final Future<WatchStatusStore?> _store;
  Timer? _timer;
  bool _disposed = false;
  bool _syncing = false;

  /// The account key the watch was last sent, so a sign-out can clear it.
  String? _boundKey;
  String? _lastSignature;
  String? _lastUser;

  // What the status is built from. The confirmed time is the only part that
  // outlives the process (WatchStatusStore); nothing here holds health values.
  WatchDeviceStatus _device = WatchDeviceStatus.unsupported;
  DateTime? _confirmedAt;
  DateTime? _unconfirmedSince;
  String? _sentSummary;

  /// What the next [_publish] sets the dismissed flag to. The flag itself
  /// lives in [watchLinkStateProvider] so "Not now" cannot be undone by a
  /// rebuild; only loading and forgetting set it here.
  bool? _dismissedNext;
  Set<String> _latestIds = {};
  Set<String> _previousIds = {};

  static Future<WatchStatusStore?> _openStore(
    Future<WatchStatusStore> opening,
  ) => opening.then<WatchStatusStore?>((s) => s, onError: (_) => null);

  /// Reads the confirmed time, the oldest unconfirmed send and the dismissed
  /// flag for the signed-in account.
  Future<void> _loadPersisted() async {
    final user = _auth?.userId;
    final store = await _store;
    if (_disposed || store == null || user == null || _auth?.userId != user) {
      return;
    }
    _confirmedAt = store.confirmedAt(watchAccountKey(user));
    _unconfirmedSince = store.unconfirmedSince(watchAccountKey(user));
    _dismissedNext =
        store.installHintDismissed ||
        _ref.read(watchLinkStateProvider).installHintDismissed;
    _publish();
  }

  void _publish() {
    if (_disposed) return;
    final dismissed =
        _dismissedNext ??
        _ref.read(watchLinkStateProvider).installHintDismissed;
    _dismissedNext = null;
    _ref
        .read(watchLinkStateProvider.notifier)
        .update(
          WatchLinkState(
            status: watchStatusOf(
              device: _device,
              signedIn: _auth?.userId != null,
              lastConfirmedAt: _confirmedAt,
              unconfirmedSince: _unconfirmedSince,
              now: _clock(),
            ),
            device: _device,
            sentSummary: _sentSummary,
            installHintDismissed: dismissed,
          ),
        );
  }

  /// A confirmation counts only from the signed-in account, as `stored` or
  /// `duplicate`, for the health or plans message of the latest or previous
  /// context this phone sent.
  void _onMessage(String json) {
    final user = _auth?.userId;
    if (user == null) return;
    final WatchMessage message;
    try {
      message = WatchMessage.fromJson(jsonDecode(json) as Map<String, Object?>);
    } catch (_) {
      return;
    }
    if (message is CompletedWorkout) {
      // A failed import sends no ack, so the watch keeps the workout.
      unawaited(
        _ref
            .read(watchWorkoutInboxProvider)
            .handle(message)
            .then<void>((_) {}, onError: (_) {}),
      );
      return;
    }
    if (message is WorkoutLink) {
      unawaited(
        _ref
            .read(watchWorkoutInboxProvider)
            .handleLink(message)
            .then<void>((_) {}, onError: (_) {}),
      );
      return;
    }
    if (message is WorkoutHealth) {
      // No ack while the workout is unknown or a write failed: the watch resends.
      unawaited(
        _ref
            .read(watchWorkoutHealthInboxProvider)
            .handle(message)
            .then<void>((_) {}, onError: (_) {}),
      );
      return;
    }
    if (message is! Ack) return;
    final key = watchAccountKey(user);
    if (message.accountKey != key) return;
    if (message.result != 'stored' && message.result != 'duplicate') return;
    final acked = message.ackedMessageId.toLowerCase();
    if (!_latestIds.contains(acked) && !_previousIds.contains(acked)) return;
    final at = _clock();
    _confirmedAt = at;
    _unconfirmedSince = null;
    unawaited(() async {
      try {
        final store = await _store;
        await store?.setConfirmedAt(key, at);
        await store?.clearUnconfirmed(key);
      } catch (_) {
        // The confirmation still shows for this session.
      }
    }());
    _publish();
  }

  /// Sign-out and deletion: forget what the watch confirmed and the dismissed
  /// banner, in memory and on disk.
  void _forget() {
    _confirmedAt = null;
    _unconfirmedSince = null;
    _sentSummary = null;
    _dismissedNext = false;
    _latestIds = {};
    _previousIds = {};
    unawaited(() async {
      try {
        await (await _store)?.clear();
      } catch (_) {
        // Nothing to clear when preferences are unavailable.
      }
    }());
  }

  void _schedule() {
    if (_disposed) return;
    _timer?.cancel();
    if (_auth?.userId == null) return;
    _timer = Timer(_debounce, () => unawaited(_sync()));
  }

  void _onAuthChanged() {
    final user = _auth?.userId;
    final key = user == null ? null : watchAccountKey(user);
    if (_boundKey != null && key != _boundKey) {
      _clearBound(emptyContext: key == null);
    }
    if (user != _lastUser) {
      _lastUser = user;
      // Signed out before anything was sent, or a new account: start clean.
      _forget();
      unawaited(_loadPersisted());
      _publish();
    }
    _schedule();
  }

  /// Tells the watch the bound account left (never wiping its unsent
  /// workouts), before anything else is sent.
  void _clearBound({required bool emptyContext}) {
    final old = _boundKey;
    if (old == null) return;
    _boundKey = null;
    _lastSignature = null;
    _forget();
    _timer?.cancel();
    final json = jsonEncode(
      buildAccountCleared(
        accountKey: old,
        wipeUnsent: false,
        messageId: _ids.newId(),
        nowUtc: _clock().toUtc(),
      ).toJson(),
    );
    unawaited(() async {
      await _link.transfer(json);
      // The two channels are not ordered, so the context carries the clear
      // as well: it replaces the old binding a watch would replay on launch.
      // An account switch needs no context here; the new binding replaces it.
      if (emptyContext) await _link.updateContext({'account_cleared': json});
    }());
  }

  Future<void> _sync() async {
    if (_disposed) return;
    if (_syncing) {
      _schedule();
      return;
    }
    _syncing = true;
    try {
      final user = _auth?.userId;
      if (user == null) return;
      final device = await _link.status();
      if (_disposed || _auth?.userId != user) return;
      _device = device;
      // Acknowledgments come only from a watch that is there to send them.
      if (device.supported && _messages == null) {
        _messages = _link.messages.listen(_onMessage);
        // Every other listener (the wipe retrier) subscribed at startup, so
        // the bridge may now hand over what the watch queued while closed.
        unawaited(_link.startMessages());
      }
      _publish();
      // iPad, Android and no paired watch: nothing is sent or shown.
      if (!device.supported) return;
      if (!await _link.isReachableForUpdates()) return;
      if (_disposed || _auth?.userId != user) return;

      final key = watchAccountKey(user);
      final nowUtc = _clock().toUtc();
      final history = _ref.read(completedWorkoutHistoryProvider).value;
      final sessions = history?.sessions ?? const [];
      final library = _ref.read(trainLibraryProvider).value;
      // Another account's overview is never sent.
      final overview = _ref.read(healthOverviewProvider).value;
      final binding = buildAccountBinding(
        accountKey: key,
        unit: watchLoadUnit(sessions),
        messageId: _ids.newId(),
        nowUtc: nowUtc,
      );
      final health = buildHealthSnapshot(
        accountKey: key,
        overview: overview?.ownerId == user ? overview : null,
        localNow: _ref.read(localNowProvider),
        messageId: _ids.newId(),
      );
      // The plans get what is left of the one-context budget.
      final plans = library == null
          ? null
          : buildPlansSnapshot(
              accountKey: key,
              library: library,
              week: _ref.read(programWeekProvider),
              recentSessions: sessions,
              nowUtc: nowUtc,
              messageId: _ids.newId(),
              maxBytes:
                  watchSnapshotMaxBytes -
                  _contextBytes(binding) -
                  (health == null ? 0 : _contextBytes(health)),
            );
      final messages = <WatchMessage>[binding, ?plans, ?health];
      final signature = jsonEncode({
        for (final m in messages) m.type: _content(m),
      });
      if (signature == _lastSignature && _boundKey == key) return;
      // Set before the await: a sign out while the send is in flight must
      // still find the account and tell the watch to clear it.
      _boundKey = key;
      await _link.updateContext({
        for (final m in messages) m.type: jsonEncode(m.toJson()),
      });
      if (_boundKey == key) {
        _lastSignature = signature;
        _noteSent(key);
        _previousIds = _latestIds;
        _latestIds = {
          for (final m in [plans, health])
            if (m != null) m.messageId.toLowerCase(),
        };
        _sentSummary = watchSentSummary(
          hasReadiness: health?.readiness != null,
          hasHealth: health != null,
          planCount: plans?.plans.length ?? 0,
        );
        _publish();
      }
    } finally {
      _syncing = false;
    }
  }

  /// The first send after a confirmation starts the unconfirmed clock; later
  /// sends keep it, so it always marks the oldest send nobody confirmed.
  void _noteSent(String key) {
    if (_unconfirmedSince != null) return;
    final at = _clock();
    _unconfirmedSince = at;
    unawaited(() async {
      try {
        await (await _store)?.setUnconfirmedSince(key, at);
      } catch (_) {
        // The clock still runs for this session.
      }
    }());
  }

  /// A reachability change only refreshes what the status shows.
  Future<void> _refreshDevice() async {
    if (_disposed) return;
    final user = _auth?.userId;
    if (user == null) return;
    final device = await _link.status();
    if (_disposed || _auth?.userId != user) return;
    _device = device;
    _publish();
  }

  /// Bytes the message takes in the context: its key and its JSON string.
  int _contextBytes(WatchMessage m) =>
      utf8.encode(m.type).length + utf8.encode(jsonEncode(m.toJson())).length;

  /// The message without ids and send times, which differ on every build.
  Map<String, Object?> _content(WatchMessage m) {
    final json = Map<String, Object?>.of(m.toJson())
      ..remove('message_id')
      ..remove('sent_at_utc');
    if (m is PlansSnapshot) {
      json['body'] = Map<String, Object?>.of(m.bodyJson)
        ..remove('generated_at_utc');
    }
    return json;
  }

  /// Permanent deletion: the watch also drops the account's unsent workouts.
  Future<void> accountDeleted(String userId) {
    _forget();
    return announceWatchAccountDeleted(
      link: _link,
      userId: userId,
      ids: _ids,
      nowUtc: _clock().toUtc(),
      queue: _ref.read(watchWipeQueueProvider),
    );
  }

  void dispose() {
    if (_disposed) return;
    // The signed-in scope is going away (sign-out or account switch).
    _clearBound(emptyContext: true);
    _disposed = true;
    _timer?.cancel();
    _auth?.removeListener(_onAuthChanged);
    _lifecycle.dispose();
    unawaited(_stateChanges.cancel());
    unawaited(_reachability.cancel());
    unawaited(_messages?.cancel());
  }
}

final watchSyncControllerProvider = Provider<WatchSyncController>((ref) {
  final controller = WatchSyncController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Keeps [watchSyncControllerProvider] alive for the signed-in scope.
class WatchSyncHost extends ConsumerWidget {
  const WatchSyncHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(watchSyncControllerProvider);
    // The phone's own workout is broadcast to the watch for as long as the
    // signed-in scope lives; reading the notifier does not rebuild on state.
    ref.watch(phoneLiveSessionProvider.notifier);
    return child;
  }
}
