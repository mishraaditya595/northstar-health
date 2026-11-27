import SwiftUI

@main
struct BeyondRepWatchApp: App {
    @StateObject private var model: AppModel
    private let link: PhoneLink
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        link = PhoneLink(model: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.refresh()
                        model.sendQueued()
                    }
                }
        }
    }
}
