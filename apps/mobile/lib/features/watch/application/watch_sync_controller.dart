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
  await link.transfer(
    jsonEncode(
      buildAccountCleared(
        accountKey: watchAccountKey(userId),
        wipeUnsent: true,
        messageId: ids.newId(),
        nowUtc: nowUtc,
      ).toJson(),
    ),
  );
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
    _schedule();
  }

  final Ref _ref;
  final AccountAuthController? _auth;
  final WatchLink _link;
  final UuidFactory _ids;
  final DateTime Function() _clock;
  late final AppLifecycleListener _lifecycle;
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
    unawaited(() async {
      await _link.transfer(
        jsonEncode(
          buildAccountCleared(
            accountKey: old,
            wipeUnsent: false,
            messageId: _ids.newId(),
            nowUtc: _clock().toUtc(),
          ).toJson(),
        ),
      );
      if (emptyContext) await _link.updateContext(const {});
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
      final messages = <WatchMessage>[
        buildAccountBinding(
          accountKey: key,
          unit: watchLoadUnit(sessions),
          messageId: _ids.newId(),
          nowUtc: nowUtc,
        ),
        if (library != null)
          buildPlansSnapshot(
            accountKey: key,
            library: library,
            week: _ref.read(programWeekProvider),
            recentSessions: sessions,
            nowUtc: nowUtc,
            messageId: _ids.newId(),
          ),
        ?buildHealthSnapshot(
          accountKey: key,
          overview: overview?.ownerId == user ? overview : null,
          localNow: _ref.read(localNowProvider),
          messageId: _ids.newId(),
        ),
      ];
      final signature = jsonEncode({
        for (final m in messages) m.type: _content(m),
      });
      if (signature == _lastSignature && _boundKey == key) return;
      await _link.updateContext({
        for (final m in messages) m.type: jsonEncode(m.toJson()),
      });
      _lastSignature = signature;
      _boundKey = key;
    } finally {
      _syncing = false;
    }
  }

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
