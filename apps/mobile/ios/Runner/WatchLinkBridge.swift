import Flutter
import WatchConnectivity

/// WatchConnectivity for the Dart side (`lib/features/watch/data/watch_link.dart`).
/// It only moves strings: the phone builds the messages and the watch checks
/// them. Every call is a no-op where WatchConnectivity is unsupported (iPad).
final class WatchLinkBridge: NSObject, WCSessionDelegate {
  static let channelName = "beyondrep/watch_link"

  private var channel: FlutterMethodChannel?

  /// Activates the session at launch, so the first send after launch does not
  /// find an inactive session and get dropped.
  static func register(messenger: FlutterBinaryMessenger) -> WatchLinkBridge {
    let bridge = WatchLinkBridge()
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    bridge.channel = channel
    channel.setMethodCallHandler { call, result in bridge.handle(call, result: result) }
    if WCSession.isSupported() {
      let session = WCSession.default
      session.delegate = bridge
      session.activate()
    }
    return bridge
  }

  private func session() -> WCSession? {
    WCSession.isSupported() ? WCSession.default : nil
  }

  /// Tells Dart the watch state changed so it can send again. Delegate
  /// callbacks arrive on a background queue; Flutter channels need the main one.
  private func notifyWatchStateChanged() {
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("watchStateChanged", arguments: nil)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let session = session() else {
      switch call.method {
      case "isReachableForUpdates": result(false)
      case "watchStatus":
        // iPad and other devices without WatchConnectivity: nothing is shown.
        result(["supported": false, "paired": false, "installed": false, "reachable": false])
      default: result(nil)
      }
      return
    }
    switch call.method {
    case "isReachableForUpdates":
      result(session.activationState == .activated && session.isPaired && session.isWatchAppInstalled)
    case "watchStatus":
      let active = session.activationState == .activated
      result([
        "supported": true,
        "paired": active && session.isPaired,
        "installed": active && session.isPaired && session.isWatchAppInstalled,
        "reachable": active && session.isReachable,
      ])
    case "updateContext":
      guard let context = call.arguments as? [String: String] else {
        result(FlutterError(code: "bad_arguments", message: nil, details: nil))
        return
      }
      do {
        try session.updateApplicationContext(context)
        result(nil)
      } catch {
        result(FlutterError(code: "wc_failed", message: nil, details: nil))
      }
    case "transfer":
      guard let args = call.arguments as? [String: String], let json = args["json"] else {
        result(FlutterError(code: "bad_arguments", message: nil, details: nil))
        return
      }
      _ = session.transferUserInfo(["json": json])
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?
  ) {
    if activationState == .activated { notifyWatchStateChanged() }
  }

  func sessionWatchStateDidChange(_ session: WCSession) {
    notifyWatchStateChanged()
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    notifyWatchStateChanged()
  }

  /// The watch's acknowledgments arrive as user info (`["json": String]`) and
  /// go to Dart, which decides what they mean.
  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    guard let json = userInfo["json"] as? String else { return }
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("watchMessage", arguments: json)
    }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    // A new watch was paired; activate again so updates reach it.
    session.activate()
  }
}
