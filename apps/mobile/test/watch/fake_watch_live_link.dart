import 'dart:async';

import 'package:beyondrep/features/watch/data/watch_live_link.dart';

/// A live link for tests: the test pushes watch messages and disconnects, and
/// reads what the phone sent.
class FakeWatchLiveLink implements WatchLiveLink {
  final _messages = StreamController<String>.broadcast(sync: true);
  final _disconnects = StreamController<void>.broadcast(sync: true);

  /// Every command JSON the phone sent, including resends.
  final sent = <String>[];

  /// What [sendCommand] answers; false models "no live path".
  bool canSend = true;

  void receive(String json) => _messages.add(json);
  void disconnect() => _disconnects.add(null);

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Stream<void> get disconnects => _disconnects.stream;

  @override
  Future<bool> sendCommand(String json) async {
    sent.add(json);
    return canSend;
  }

  Future<void> dispose() async {
    await _messages.close();
    await _disconnects.close();
  }
}
