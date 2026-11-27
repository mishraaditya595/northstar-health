import Flutter
import HealthKit
import WatchConnectivity

/// The live link to an Apple Watch workout (`lib/features/watch/data/watch_live_link.dart`).
/// It only moves strings: JSON `session_state` messages from the watch go to
/// Dart, and JSON `session_command` messages from Dart go to the watch. The
/// phone does not read or write any health data here. All decisions (account
/// check, freshness, commands) stay in Dart.
///
/// Two paths, the same JSON on both:
/// - iOS 17+: the watch's mirrored `HKWorkoutSession` (the system starts this
///   app in the background when the watch starts mirroring, so the handler is
///   set in `application(_:didFinishLaunchingWithOptions:)`).
/// - Any iOS, or when there is no mirrored session: `WCSession.sendMessage`
///   while the watch is reachable, which needs this app in the foreground.
final class WorkoutMirrorBridge: NSObject {
  static let channelName = "beyondrep/watch_live"

  private var channel: FlutterMethodChannel?
  /// Held as `Any` so this class compiles on iOS 15; the real types are
  /// `HKHealthStore` and the mirrored `HKWorkoutSession` (iOS 17).
  private var healthStore: Any?
  private var mirrored: Any?
  private var mirrorDelegate: Any?
  /// Dart is listening. Until then the newest message is kept, so a workout
  /// that was already running when the app launched shows at once.
  private var dartReady = false
  private var pendingMessage: String?

  /// Must run at launch, before anything else: the system can call the handler
  /// as soon as the app starts in the background. No health permission is
  /// requested here; the handler only receives the session.
  func installMirroringHandler() {
    guard #available(iOS 17.0, *), HKHealthStore.isHealthDataAvailable() else { return }
    let store = HKHealthStore()
    healthStore = store
    store.workoutSessionMirroringStartHandler = { [weak self] session in
      // Called on an arbitrary queue, and again after a lost connection.
      DispatchQueue.main.async { self?.attach(session) }
    }
  }

  /// Creates the channel once the Flutter engine exists.
  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
  }

  @available(iOS 17.0, *)
  private func attach(_ session: HKWorkoutSession) {
    let delegate = MirrorSessionDelegate()
    delegate.onData = { [weak self] chunks in
      for chunk in chunks {
        guard let json = String(data: chunk, encoding: .utf8) else { continue }
        DispatchQueue.main.async { self?.deliver(json: json) }
      }
    }
    delegate.onEnded = { [weak self, weak session] in
      DispatchQueue.main.async {
        // An older session ending must not clear a newer one.
        guard let self, let session, let current = self.mirrored as? HKWorkoutSession, current === session else { return }
        self.mirrored = nil
        self.mirrorDelegate = nil
        self.channel?.invokeMethod("liveDisconnected", arguments: nil)
      }
    }
    session.delegate = delegate
    mirrored = session
    mirrorDelegate = delegate
  }

  /// A live JSON message from the watch (either path). Safe from the main queue only.
  func deliver(json: String) {
    if dartReady {
      channel?.invokeMethod("liveMessage", arguments: json)
    } else {
      pendingMessage = json
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      dartReady = true
      if let pending = pendingMessage {
        pendingMessage = nil
        channel?.invokeMethod("liveMessage", arguments: pending)
      }
      result(nil)
    case "sendCommand":
      guard let args = call.arguments as? [String: String], let json = args["json"] else {
        result(FlutterError(code: "bad_arguments", message: nil, details: nil))
        return
      }
      send(json: json) { sent in DispatchQueue.main.async { result(sent) } }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Mirrored session first, then `sendMessage`; false when neither is available.
  private func send(json: String, completion: @escaping (Bool) -> Void) {
    if #available(iOS 17.0, *), let session = mirrored as? HKWorkoutSession {
      session.sendToRemoteWorkoutSession(data: Data(json.utf8)) { [weak self] success, _ in
        if success {
          completion(true)
        } else {
          completion(self?.sendMessage(json: json) ?? false)
        }
      }
      return
    }
    completion(sendMessage(json: json))
  }

  private func sendMessage(json: String) -> Bool {
    guard WCSession.isSupported() else { return false }
    let session = WCSession.default
    guard session.activationState == .activated, session.isReachable else { return false }
    session.sendMessage(["json": json], replyHandler: nil, errorHandler: nil)
    return true
  }
}

/// Receives what the watch sends through the mirrored session and tells the
/// bridge when it ends.
@available(iOS 17.0, *)
private final class MirrorSessionDelegate: NSObject, HKWorkoutSessionDelegate {
  var onData: (([Data]) -> Void)?
  var onEnded: (() -> Void)?

  func workoutSession(
    _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
    from fromState: HKWorkoutSessionState, date: Date
  ) {
    if toState == .ended || toState == .stopped { onEnded?() }
  }

  func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
    onEnded?()
  }

  func workoutSession(
    _ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]
  ) {
    onData?(data)
  }

  func workoutSession(
    _ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?
  ) {
    onEnded?()
  }
}
