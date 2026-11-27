import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

enum WatchPage: Hashable {
    case home, train
}

/// Where a tap on Home leads.
enum WatchRoute: Hashable {
    case metric(Metric)
    case readiness
    case sync
}

/// Home and Train are two vertical pages (the crown scrolls between them);
/// a tap on a tile, the hero or the status line pushes a detail screen.
struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var page: WatchPage = .home
    @AppStorage("didShowTrainHint") private var didShowTrainHint = false

    private var isReady: Bool {
        if case .ready = model.glance { return true }
        return false
    }

    /// The hint shows once, after the phone has paired and sent a glance.
    private var showHint: Binding<Bool> {
        Binding(
            get: { !didShowTrainHint && isReady },
            set: { if !$0 { didShowTrainHint = true } })
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                HomePage(glance: model.glance, syncLine: model.syncLine, page: $page)
                    .tag(WatchPage.home)
                TrainPage(glance: model.glance)
                    .tag(WatchPage.train)
            }
            .tabViewStyle(.verticalPage)
            .navigationDestination(for: WatchRoute.self) { route in
                destination(route)
            }
        }
        .fullScreenCover(isPresented: showHint) {
            TrainHintView { didShowTrainHint = true }
        }
    }

    @ViewBuilder
    private func destination(_ route: WatchRoute) -> some View {
        switch route {
        case .metric(let metric):
            if let detail = model.detail(for: metric) {
                switch metric {
                case .sleep: SleepDetailView(detail: detail)
                case .restingHr: TrendDetailView(detail: detail, metric: metric, style: .line)
                case .hrv: TrendDetailView(detail: detail, metric: metric, style: .line)
                case .steps: TrendDetailView(detail: detail, metric: metric, style: .bars)
                }
            } else {
                NoDataView()
            }
        case .readiness:
            if case .ready(let glance) = model.glance, let line = glance.readiness {
                ReadinessDetailView(line: line, reason: glance.readinessReason, factors: glance.factors)
            } else {
                NoDataView()
            }
        case .sync:
            SyncView(line: model.syncLine)
        }
    }
}

/// A detail screen for a day that has no snapshot (for example after
/// midnight, before the phone refreshes).
struct NoDataView: View {
    var body: some View {
        Text(GlanceState.refreshCaption)
            .font(.footnote)
            .foregroundStyle(Palette.secondary)
            .padding()
            .frame(maxHeight: .infinity)
            .background(Palette.canvas)
    }
}
