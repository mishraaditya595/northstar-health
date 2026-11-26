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
import '../domain/watch_account_key.dart';
import '../domain/watch_message.dart';
import 'watch_snapshots.dart';

/// Ids for outgoing watch messages; tests replace it.
final watchMessageIdsProvider = Provider<UuidFactory>(
  (ref) => SecureUuidFactory(),
);

/// Tells the watch an account was permanently deleted so it drops that
/// account's unsent workouts too. Reads no provider, so the account
/// controller can call it after the signed-in scope has gone. Sends nothing
/// when no watch with the app is paired.
Future<void> announceWatchAccountDeleted({
  required WatchLink link,
  required String userId,
  required UuidFactory ids,
  required DateTime nowUtc,
}) async {
  if (!await link.isReachableForUpdates()) return;
  final json = jsonEncode(
    buildAccountCleared(
      accountKey: watchAccountKey(userId),
      wipeUnsent: true,
      messageId: ids.newId(),
      nowUtc: nowUtc,
    ).toJson(),
  );
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
      _clock = _ref.read(wallClockProvider) {
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
    _schedule();
  }

  final Ref _ref;
  final AccountAuthController? _auth;
  final WatchLink _link;
  final UuidFactory _ids;
  final DateTime Function() _clock;
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<void> _stateChanges;
  Timer? _timer;
  bool _disposed = false;
  bool _syncing = false;

  /// The account key the watch was last sent, so a sign-out can clear it.
  String? _boundKey;
  String? _lastSignature;

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
    _schedule();
  }

  /// Tells the watch the bound account left (never wiping its unsent
  /// workouts), before anything else is sent.
  void _clearBound({required bool emptyContext}) {
    final old = _boundKey;
    if (old == null) return;
    _boundKey = null;
    _lastSignature = null;
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
      if (_boundKey == key) _lastSignature = signature;
    } finally {
      _syncing = false;
    }
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
  Future<void> accountDeleted(String userId) => announceWatchAccountDeleted(
    link: _link,
    userId: userId,
    ids: _ids,
    nowUtc: _clock().toUtc(),
  );

  void dispose() {
    if (_disposed) return;
    // The signed-in scope is going away (sign-out or account switch).
    _clearBound(emptyContext: true);
    _disposed = true;
    _timer?.cancel();
    _auth?.removeListener(_onAuthChanged);
    _lifecycle.dispose();
    unawaited(_stateChanges.cancel());
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
    return child;
  }
}
