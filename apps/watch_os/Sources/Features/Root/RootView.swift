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
    /// Today's program workout, or the plan with this id.
    case today
    case plan(String)
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

    private var isRecording: Bool {
        guard let status = model.workout?.status else { return false }
        return status == "active" || status == "paused"
    }

    var body: some View {
        Group {
            if let summary = model.summary {
                SummaryView(model: model, summary: summary)
            } else if isRecording {
                WorkoutView(model: model)
            } else if model.follower != nil {
                // A workout the iPhone owns (stage 5b).
                FollowerView(model: model)
            } else {
                browser
            }
        }
        .task { await model.restoreWorkout() }
    }

    private var browser: some View {
        NavigationStack {
            TabView(selection: $page) {
                HomePage(glance: model.glance, syncLine: model.syncLine, page: $page)
                    .tag(WatchPage.home)
                TrainPage(
                    glance: model.glance, canStart: model.canStart, isStarting: model.isStarting,
                    onQuickWorkout: { Task { await model.startWorkout(.quick()) } }
                )
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
        // The Home reads this watch's own health; the first time it asks for
        // permission. Also when the phone pairs while the Home is showing.
        .onAppear { Task { await model.homeAppeared() } }
        .onChange(of: isReady) { _, ready in
            if ready { Task { await model.homeAppeared() } }
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
            SyncView(line: model.syncLine, waiting: model.waiting)
        case .today:
            PlanPreviewView(model: model, planId: nil)
        case .plan(let id):
            PlanPreviewView(model: model, planId: id)
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
