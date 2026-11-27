import Foundation
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Where a live `session_state` goes while a workout runs. The mirrored
/// HealthKit session is first (it keeps the iPhone app alive in the
/// background); WatchConnectivity `sendMessage` is the fallback while the
/// iPhone app is reachable. A state is latest-wins, so it is never queued
/// with `transferUserInfo`: with no live path it is dropped, and the next
/// state replaces it. Only `session_state` JSON travels here, never heart rate
/// or energy.
@MainActor
final class LiveLink {
    private let recorder: WorkoutRecorder
    private let phone: () -> PhoneLink?

    init(recorder: WorkoutRecorder, phone: @escaping () -> PhoneLink?) {
        self.recorder = recorder
        self.phone = phone
    }

    /// Sends `message` on the best live path: the mirrored session, and the
    /// WatchConnectivity message when there is no mirror or HealthKit reports
    /// the mirrored send failed. A state nobody could take is dropped.
    func send(_ message: WatchMessage) {
        guard let data = try? message.jsonData() else { return }
        let json = String(decoding: data, as: UTF8.self)
        guard recorder.isMirroring else {
            _ = phone()?.sendLive(json: json)
            return
        }
        recorder.send(data) { [weak self] sent in
            guard !sent else { return }
            Task { @MainActor in _ = self?.phone()?.sendLive(json: json) }
        }
    }

    /// Sends the last state of a workout (`status: ended`) and waits for the
    /// mirrored session to report it handled (at most 3 s) before the caller
    /// ends that session; when it did not, the state goes by
    /// WatchConnectivity too. Without a mirrored session it is the plain send.
    func sendEnded(_ message: WatchMessage) async {
        guard let data = try? message.jsonData() else { return }
        if recorder.isMirroring, await recorder.sendAndWait(data, timeout: 3) { return }
        _ = phone()?.sendLive(json: String(decoding: data, as: UTF8.self))
    }
}
