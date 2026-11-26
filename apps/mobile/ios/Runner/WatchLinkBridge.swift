import Flutter
import WatchConnectivity

/// WatchConnectivity for the Dart side (`lib/features/watch/data/watch_link.dart`).
/// It only moves strings: the phone builds the messages and the watch checks
/// them. Every call is a no-op where WatchConnectivity is unsupported (iPad).
final class WatchLinkBridge: NSObject, WCSessionDelegate {
  static let channelName = "beyondrep/watch_link"

  private var activated = false

  static func register(messenger: FlutterBinaryMessenger) -> WatchLinkBridge {
    let bridge = WatchLinkBridge()
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in bridge.handle(call, result: result) }
    return bridge
  }

  private func session() -> WCSession? {
    guard WCSession.isSupported() else { return nil }
    let session = WCSession.default
    if !activated {
      activated = true
      session.delegate = self
      session.activate()
    }
    return session
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let session = session() else {
      result(call.method == "isReachableForUpdates" ? false : nil)
      return
    }
    switch call.method {
    case "isReachableForUpdates":
      result(session.activationState == .activated && session.isPaired && session.isWatchAppInstalled)
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
  ) {}

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    // A new watch was paired; activate again so updates reach it.
    session.activate()
  }
}
