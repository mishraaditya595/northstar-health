import Foundation
import WatchConnectivity
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Receives the phone's application context and one-off user info and hands
/// them to the model. The only thing sent back is an `ack` (ids and a result,
/// never health values) for each message the watch stored.
final class PhoneLink: NSObject, WCSessionDelegate {
    private weak var model: AppModel?

    @MainActor
    init(model: AppModel) {
        self.model = model
        super.init()
        model.link = self
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?
    ) {
        guard activationState == .activated else { return }
        let reachable = session.isReachable
        onMain { $0.setPhoneReachable(reachable) }
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

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        onMain { $0.setPhoneReachable(reachable) }
    }

    /// Queued by the system, so an ack survives the phone being away.
    func send(acks: [String]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        for json in acks {
            WCSession.default.transferUserInfo(["json": json])
        }
    }

    /// Queues a finished workout for the phone. The system keeps the transfer
    /// until the phone receives it, so it survives the phone being away.
    func send(completed message: WatchMessage) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
            let data = try? message.jsonData()
        else { return }
        WCSession.default.transferUserInfo(["json": String(decoding: data, as: UTF8.self)])
    }

    /// Message ids of transfers still in flight, so one is not queued twice.
    func outstandingIds() -> Set<String> {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return [] }
        var ids = Set<String>()
        for transfer in WCSession.default.outstandingUserInfoTransfers where transfer.isTransferring {
            guard let text = transfer.userInfo["json"] as? String,
                let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
                let id = object["message_id"] as? String
            else { continue }
            ids.insert(id.lowercased())
        }
        return ids
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
