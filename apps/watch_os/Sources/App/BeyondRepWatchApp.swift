import HealthKit
import SwiftUI
import WatchKit

/// Receives the launch the iPhone asks for (`startWatchApp(with:)`) when a
/// workout starts on the phone. The model decides whether to join.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    /// Set by `BeyondRepWatchApp` once the model exists.
    @MainActor static weak var model: AppModel?

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await Self.model?.joinPhoneWorkout(configuration: workoutConfiguration)
        }
    }
}

@main
struct BeyondRepWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var model: AppModel
    private let link: PhoneLink
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        WatchAppDelegate.model = model
        link = PhoneLink(model: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.pruneStale()
                        model.refresh()
                        model.sendQueued()
                        model.startPeriodicHealthRefresh()
                        Task { await model.refreshWatchHealth() }
                    } else {
                        model.stopPeriodicHealthRefresh()
                    }
                }
        }
    }
}
