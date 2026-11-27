import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/watch_link.dart';
import '../data/watch_wipe_queue.dart';
import '../domain/watch_message.dart';

final watchWipeQueueProvider = Provider<Future<WatchWipeQueue>>(
  (ref) => WatchWipeQueue.open(),
);

/// Resends a persisted account-deletion wipe until the watch confirms it. One
/// per process, started at launch and independent of the signed-in scope: the
/// account the wipe is for no longer exists. It sends user info only, never
/// the application context, because another account may be bound by then.
class WatchWipeRetrier {
  WatchWipeRetrier({required this.link, required this.queue});

  final WatchLink link;
  final Future<WatchWipeQueue> queue;

  /// Sent since [start] or the last watch state change.
  final Set<String> _sent = {};
  StreamSubscription<String>? _messages;
  StreamSubscription<void>? _state;
  AppLifecycleListener? _lifecycle;
  bool _disposed = false;

  void start() {
    _messages = link.messages.listen(_onMessage);
    _state = link.watchStateChanges.listen((_) {
      _sent.clear();
      unawaited(retry());
    });
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(retry()));
    unawaited(retry());
  }

  Future<void> retry() async {
    try {
      final pending = (await queue).pending();
      if (_disposed || pending.isEmpty) return;
      if (!await link.isReachableForUpdates() || _disposed) return;
      for (final wipe in pending) {
        if (_sent.add(wipe.messageId)) await link.transfer(wipe.json);
      }
    } catch (_) {
      // The wipe stays queued and is tried again on the next trigger.
    }
  }

  void _onMessage(String json) {
    final WatchMessage message;
    try {
      message = WatchMessage.fromJson(jsonDecode(json) as Map<String, Object?>);
    } catch (_) {
      return;
    }
    if (message is! Ack) return;
    if (message.result != 'stored' && message.result != 'duplicate') return;
    final acked = message.ackedMessageId.toLowerCase();
    unawaited(() async {
      try {
        await (await queue).remove(acked);
      } catch (_) {
        // Kept; the next ack or launch removes it.
      }
    }());
  }

  void dispose() {
    _disposed = true;
    unawaited(_messages?.cancel());
    unawaited(_state?.cancel());
    _lifecycle?.dispose();
  }
}
