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
}

/// iOS bridge (`ios/Runner/WatchLinkBridge.swift`). A missing plugin or a
/// platform error never reaches the UI: it means "no watch" and nothing is
/// sent.
class MethodChannelWatchLink implements WatchLink {
  const MethodChannelWatchLink([
    this.channel = const MethodChannel('beyondrep/watch_link'),
  ]);

  final MethodChannel channel;

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
}

final watchLinkProvider = Provider<WatchLink>(
  (ref) => defaultTargetPlatform == TargetPlatform.iOS
      ? const MethodChannelWatchLink()
      : const NoopWatchLink(),
);
