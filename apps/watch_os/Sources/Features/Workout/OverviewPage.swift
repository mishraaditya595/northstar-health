import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

struct OverviewPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var recorder: WorkoutRecorder
    let controller: WorkoutController

    @State private var showEnd = false
    @State private var showExercises = false
    @Environment(\.isLuminanceReduced) private var dimmed

    private var paused: Bool { _ = model.revision; return controller.status == "paused" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                row("Time") {
                    if paused {
                        Text("Paused").foregroundStyle(Palette.caution)
                    } else if dimmed {
                        Text("\u{2014}").foregroundStyle(Palette.secondary)
                    } else {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(SetPage.clock(context.date.timeIntervalSince(controller.startedAt)))
                        }
                    }
                }
                row("Heart rate") {
                    Text(recorder.heartRate.map(String.init) ?? "\u{2014}")
                        .foregroundStyle(Palette.heart)
                        .accessibilityLabel(recorder.heartRate.map { "Heart rate \($0)" } ?? "Heart rate not available")
                }
                row("Sets") {
                    let cursor = controller.cursor
                    Text("\(cursor.completedCount) / \(cursor.plannedCount)")
                        .accessibilityLabel("\(cursor.completedCount) of \(cursor.plannedCount) sets")
                }
                Button(paused ? "Resume" : "Pause") { model.pauseOrResume() }
                    .frame(maxWidth: .infinity, minHeight: 44)
                Button("Exercises") { showExercises = true }
                    .frame(maxWidth: .infinity, minHeight: 44)
                Button("End", role: .destructive) { showEnd = true }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 6)
        }
        .background(Palette.canvas)
        .sheet(isPresented: $showEnd) { EndConfirmView(model: model, controller: controller) }
        .sheet(isPresented: $showExercises) { ExercisesSheet(model: model, controller: controller) }
    }

    private func row<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Palette.secondary)
            Spacer()
            value()
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }
}
