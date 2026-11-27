import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Today's program workout first, then the plans. A tap opens the plan
/// preview with Start. Without an account binding there is no Start button.
struct TrainPage: View {
    let glance: GlanceState
    var canStart = false
    var onQuickWorkout: () -> Void = {}

    var body: some View {
        ScrollView {
            switch glance {
            case .notPaired:
                Text("Open BeyondRep on your iPhone to sign in.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondary)
                    .padding()
            case .ready(let glance):
                TrainContent(glance: glance, canStart: canStart, onQuickWorkout: onQuickWorkout)
            }
        }
        .background(Palette.canvas)
    }
}

private struct TrainContent: View {
    let glance: Glance
    let canStart: Bool
    let onQuickWorkout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Train")
                .font(.footnote.weight(.heavy))
                .foregroundStyle(Palette.secondary)
            if let today = glance.today {
                NavigationLink(value: WatchRoute.today) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Palette.performance)
                    Text(today.name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = today.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.performance, lineWidth: 1))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Today, \(today.name)" + (today.subtitle.map { ", \($0)" } ?? ""))
                }
                .buttonStyle(.plain)
            }
            if glance.plans.isEmpty && glance.today == nil {
                Text("No plans yet. Create one in BeyondRep on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(glance.plans, id: \.id) { plan in
                NavigationLink(value: WatchRoute.plan(plan.id)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if plan.exerciseCount > 0 {
                        Text(plan.exerciseCount == 1 ? "1 exercise" : "\(plan.exerciseCount) exercises")
                            .font(.caption2)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
            }
            if canStart {
                Button("+ Quick workout", action: onQuickWorkout)
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, 8)
    }
}

#if DEBUG
#Preview("Train") {
    TrainPage(glance: PreviewData.glance)
}

#Preview("Train, can start") {
    NavigationStack { TrainPage(glance: PreviewData.glance, canStart: true) }
}

#Preview("Train, no plans") {
    TrainPage(glance: .ready(PreviewData.emptyPlans))
}
#endif
