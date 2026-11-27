import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// The three pages of a running workout: the set, the rest and the overview.
/// A new rest brings up the Rest page; it ends back on the set.
struct WorkoutView: View {
    @ObservedObject var model: AppModel
    @State private var page = 0

    var body: some View {
        if let controller = model.workout {
            TabView(selection: $page) {
                SetPage(model: model, recorder: model.recorder, controller: controller)
                    .tag(0)
                RestPage(model: model, controller: controller)
                    .tag(1)
                OverviewPage(model: model, recorder: model.recorder, controller: controller)
                    .tag(2)
            }
            .tabViewStyle(.page)
            .onChange(of: controller.restDeadline) { _, deadline in
                page = deadline == nil ? 0 : 1
            }
            .onChange(of: model.revision) { _, _ in
                // The rest ran out by itself: back to the next set.
                if page == 1, controller.restDeadline.map({ $0 <= Date() }) ?? true { page = 0 }
            }
        }
    }
}
