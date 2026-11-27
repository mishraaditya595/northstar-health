import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The phone's live link to a workout running on the Apple Watch. It carries
/// opaque JSON strings (`session_state` from the watch, `session_command` to
/// it); every decision stays in Dart. The platform side uses the mirrored
/// workout session on iOS 17 and later and falls back to WatchConnectivity
/// messages while the app is open (`ios/Runner/WorkoutMirrorBridge.swift`).
abstract interface class WatchLiveLink {
  /// JSON the watch sent, as it arrives.
  Stream<String> get messages;

  /// Fires when the mirrored session ended or the connection dropped.
  Stream<void> get disconnects;

  /// Sends one command. False when no live path to the watch exists right
  /// now; the caller decides whether to try again.
  Future<bool> sendCommand(String json);
}

/// iOS bridge. A missing plugin or a platform error never reaches the UI: it
/// means "no live link" and nothing is sent.
class MethodChannelWatchLiveLink implements WatchLiveLink {
  MethodChannelWatchLiveLink([
    this.channel = const MethodChannel('beyondrep/watch_live'),
  ]);

  final MethodChannel channel;

  /// The one instance the app uses; two would fight over the single handler.
  static final MethodChannelWatchLiveLink shared = MethodChannelWatchLiveLink();

  /// Which streams have a listener; the platform handler stays while any does.
  final Set<String> _listening = {};

  late final StreamController<String> _messages =
      StreamController<String>.broadcast(
        onListen: () => _attach('messages'),
        onCancel: () => _detach('messages'),
      );

  late final StreamController<void> _disconnects =
      StreamController<void>.broadcast(
        onListen: () => _attach('disconnects'),
        onCancel: () => _detach('disconnects'),
      );

  void _attach(String which) {
    _listening.add(which);
    channel.setMethodCallHandler((call) async {
      if (call.method == 'liveMessage' && call.arguments is String) {
        _messages.add(call.arguments as String);
      }
      if (call.method == 'liveDisconnected') _disconnects.add(null);
      return null;
    });
    // Tells the platform side that Dart listens, so a message kept from
    // before the engine started is delivered.
    if (which == 'messages') unawaited(_ready());
  }

  Future<void> _ready() async {
    try {
      await channel.invokeMethod<void>('ready');
    } on MissingPluginException {
      // No bridge on this platform.
    } on PlatformException {
      // Nothing to deliver.
    }
  }

  void _detach(String which) {
    _listening.remove(which);
    if (_listening.isEmpty) channel.setMethodCallHandler(null);
  }

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Stream<void> get disconnects => _disconnects.stream;

  @override
  Future<bool> sendCommand(String json) async {
    try {
      return await channel.invokeMethod<bool>('sendCommand', {'json': json}) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// Android and tests: no watch to follow.
class NoopWatchLiveLink implements WatchLiveLink {
  const NoopWatchLiveLink();

  @override
  Stream<String> get messages => const Stream<String>.empty();

  @override
  Stream<void> get disconnects => const Stream<void>.empty();

  @override
  Future<bool> sendCommand(String json) async => false;
}

final watchLiveLinkProvider = Provider<WatchLiveLink>(
  (ref) => defaultTargetPlatform == TargetPlatform.iOS
      ? MethodChannelWatchLiveLink.shared
      : const NoopWatchLiveLink(),
);
