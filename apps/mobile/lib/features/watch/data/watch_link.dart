import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/watch_status.dart';

/// The phone's side of the watch link (Apple Watch or Wear OS). It carries opaque JSON strings
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

  /// Fires when only the watch's reachability changed (it woke or went out of
  /// range). Nothing needs resending; the status just refreshes.
  Stream<void> get watchReachabilityChanges;

  /// What iOS says about the paired watch; unsupported without a bridge.
  Future<WatchDeviceStatus> status();

  /// JSON strings the watch sent (acknowledgments), as they arrive.
  Stream<String> get messages;

  /// Asks the bridge to hand over watch messages that arrived before Dart was
  /// ready (Android keeps them as Data Layer items). Call it once, after every
  /// listener that needs them has subscribed to [messages]: the stream is
  /// broadcast, so a message delivered earlier would reach nobody and be
  /// deleted. iOS delivers as messages arrive and ignores it.
  Future<void> startMessages();
}

/// Platform bridge (`ios/Runner/WatchLinkBridge.swift`, Android
/// `WearLinkBridge.kt`). A missing plugin or a
/// platform error never reaches the UI: it means "no watch" and nothing is
/// sent.
class MethodChannelWatchLink implements WatchLink {
  MethodChannelWatchLink([
    this.channel = const MethodChannel('beyondrep/watch_link'),
  ]);

  final MethodChannel channel;

  /// The one instance the app uses. Two instances would fight over the single
  /// platform handler, and the wipe retrier must hear acks while the
  /// signed-in controller listens too.
  static final MethodChannelWatchLink shared = MethodChannelWatchLink();

  /// The instance whose stream is listened to; only it owns the platform
  /// callback, so a stale instance cannot remove a newer one's handler.
  static MethodChannelWatchLink? _handling;

  /// Which streams have a listener; the handler stays while any does.
  final Set<String> _listening = {};

  late final StreamController<void> _changes = StreamController<void>.broadcast(
    onListen: () => _attach('changes'),
    onCancel: () => _detach('changes'),
  );

  late final StreamController<void> _reachability =
      StreamController<void>.broadcast(
        onListen: () => _attach('reachability'),
        onCancel: () => _detach('reachability'),
      );

  late final StreamController<String> _messages =
      StreamController<String>.broadcast(
        onListen: () => _attach('messages'),
        onCancel: () => _detach('messages'),
      );

  void _attach(String which) {
    _listening.add(which);
    _handling = this;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'watchStateChanged') _changes.add(null);
      if (call.method == 'watchReachabilityChanged') _reachability.add(null);
      if (call.method == 'watchMessage' && call.arguments is String) {
        _messages.add(call.arguments as String);
      }
      return null;
    });
  }

  @override
  Future<void> startMessages() async {
    try {
      await channel.invokeMethod<void>('startMessages');
    } on MissingPluginException {
      // No bridge on this platform.
    } on PlatformException {
      // Not user actionable; the next explicit start asks again.
    }
  }

  void _detach(String which) {
    _listening.remove(which);
    if (_listening.isNotEmpty || !identical(_handling, this)) return;
    _handling = null;
    channel.setMethodCallHandler(null);
  }

  @override
  Stream<void> get watchStateChanges => _changes.stream;

  @override
  Stream<void> get watchReachabilityChanges => _reachability.stream;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Future<WatchDeviceStatus> status() async {
    try {
      final raw = await channel.invokeMapMethod<String, Object?>('watchStatus');
      if (raw == null) return WatchDeviceStatus.unsupported;
      return WatchDeviceStatus(
        supported: raw['supported'] == true,
        paired: raw['paired'] == true,
        installed: raw['installed'] == true,
        reachable: raw['reachable'] == true,
      );
    } on MissingPluginException {
      return WatchDeviceStatus.unsupported;
    } on PlatformException {
      return WatchDeviceStatus.unsupported;
    }
  }

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

/// Other platforms and tests: nothing to send to.
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

  @override
  Stream<void> get watchReachabilityChanges => const Stream<void>.empty();

  @override
  Future<WatchDeviceStatus> status() async => WatchDeviceStatus.unsupported;

  @override
  Stream<String> get messages => const Stream<String>.empty();

  @override
  Future<void> startMessages() async {}
}

final watchLinkProvider = Provider<WatchLink>(
  (ref) =>
      defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android
      ? MethodChannelWatchLink.shared
      : const NoopWatchLink(),
);
