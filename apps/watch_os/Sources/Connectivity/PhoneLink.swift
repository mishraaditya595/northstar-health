import Foundation
import WatchConnectivity

/// Receives the phone's application context and one-off user info and hands
/// them to the model. The phone is the only sender; nothing is sent back in
/// this stage.
final class PhoneLink: NSObject, WCSessionDelegate {
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?
    ) {
        guard activationState == .activated else { return }
        // The context the phone sent while the watch app was not running.
        let context = session.receivedApplicationContext
        deliver(context: context)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(context: applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        onMain { $0.receive(userInfo: userInfo) }
    }

    private func deliver(context: [String: Any]) {
        onMain { $0.receive(applicationContext: context) }
    }

    /// Callbacks arrive on a background queue. One FIFO hop to the main queue
    /// keeps them in the order WatchConnectivity delivered them, which
    /// separate Tasks would not.
    private func onMain(_ work: @escaping @MainActor (AppModel) -> Void) {
        DispatchQueue.main.async { [weak model] in
            guard let model else { return }
            MainActor.assumeIsolated { work(model) }
        }
    }
}
