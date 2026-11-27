import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Exercise names with "sets × reps", then Start. `planId` nil means today's
/// program workout. Start builds a fresh template, so ids are new each time.
struct PlanPreviewView: View {
    @ObservedObject var model: AppModel
    let planId: String?

    var body: some View {
        let template = model.template(planId: planId)
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let template {
                    Text(template.name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(template.exercises, id: \.exerciseId) { exercise in
                        HStack {
                            Text(exercise.name)
                                .font(.caption2)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(2)
                            Spacer()
                            Text(Self.summary(exercise))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    if model.canStart {
                        Button("Start") {
                            Task { if let fresh = model.template(planId: planId) { await model.startWorkout(fresh) } }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.performance)
                        .foregroundStyle(Palette.canvas)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                } else {
                    Text("This plan is not on your watch yet.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondary)
                }
            }
            .padding(.horizontal, 6)
        }
        .background(Palette.canvas)
    }

    /// "3 \u{00D7} 8", "3 \u{00D7} 0:45" or just the set count.
    static func summary(_ exercise: TemplateExercise) -> String {
        let working = exercise.sets.filter { $0.kind == "working" }
        guard let first = working.first else { return "\(exercise.sets.count) sets" }
        if let reps = first.targetReps { return "\(working.count) \u{00D7} \(reps)" }
        if let seconds = first.targetSeconds {
            return "\(working.count) \u{00D7} \(seconds / 60):\(String(format: "%02d", seconds % 60))"
        }
        return "\(working.count) sets"
    }
}
