import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The phone's side of the Apple Watch link. It carries opaque JSON strings
/// built by `watch_snapshots.dart`; all decisions stay in Dart.
abstract interface class WatchLink {
  /// True only when a watch is paired and has the BeyondRep app installed.
  Future<bool> isReachableForUpdates();

  /// Replaces the application context: the watch keeps only the latest value
  /// per key. An empty map clears it.
  Future<void> updateContext(Map<String, String> latestByType);

  /// Queues one message for guaranteed delivery (WatchConnectivity user info).
  Future<void> transfer(String json);

  /// Fires when the session finishes activating or a watch is paired,
  /// unpaired or gets the app installed, so a send that was dropped for lack
  /// of a reachable watch can be tried again.
  Stream<void> get watchStateChanges;
}

/// iOS bridge (`ios/Runner/WatchLinkBridge.swift`). A missing plugin or a
/// platform error never reaches the UI: it means "no watch" and nothing is
/// sent.
class MethodChannelWatchLink implements WatchLink {
  MethodChannelWatchLink([
    this.channel = const MethodChannel('beyondrep/watch_link'),
  ]);

  final MethodChannel channel;

  /// The instance whose stream is listened to; only it owns the platform
  /// callback, so a stale instance cannot remove a newer one's handler.
  static MethodChannelWatchLink? _handling;

  late final StreamController<void> _changes = StreamController<void>.broadcast(
    onListen: _attach,
    onCancel: _detach,
  );

  void _attach() {
    _handling = this;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'watchStateChanged') _changes.add(null);
      return null;
    });
  }

  void _detach() {
    if (!identical(_handling, this)) return;
    _handling = null;
    channel.setMethodCallHandler(null);
  }

  @override
  Stream<void> get watchStateChanges => _changes.stream;

  @override
  Future<bool> isReachableForUpdates() async {
    try {
      return await channel.invokeMethod<bool>('isReachableForUpdates') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> updateContext(Map<String, String> latestByType) async {
    try {
      await channel.invokeMethod<void>('updateContext', latestByType);
    } on MissingPluginException {
      // No bridge on this platform.
    } on PlatformException {
      // WatchConnectivity errors are not user actionable.
    }
  }

  @override
  Future<void> transfer(String json) async {
    try {
      await channel.invokeMethod<void>('transfer', {'json': json});
    } on MissingPluginException {
      // No bridge on this platform.
    } on PlatformException {
      // WatchConnectivity errors are not user actionable.
    }
  }
}

/// Android and tests: nothing to send to.
class NoopWatchLink implements WatchLink {
  const NoopWatchLink();

  @override
  Future<bool> isReachableForUpdates() async => false;

  @override
  Future<void> updateContext(Map<String, String> latestByType) async {}

  @override
  Future<void> transfer(String json) async {}

  @override
  Stream<void> get watchStateChanges => const Stream<void>.empty();
}

final watchLinkProvider = Provider<WatchLink>(
  (ref) => defaultTargetPlatform == TargetPlatform.iOS
      ? MethodChannelWatchLink()
      : const NoopWatchLink(),
);
