import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

struct EndConfirmView: View {
    @ObservedObject var model: AppModel
    let controller: WorkoutController
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDiscard = false

    private var hasSets: Bool { _ = model.revision; return controller.canSave }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if confirmingDiscard {
                    Text("Discard this workout? It is deleted from your watch.")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Discard", role: .destructive) {
                        model.discardWorkout()
                        dismiss()
                    }
                    .frame(minHeight: 44)
                    Button("Keep going") { confirmingDiscard = false }
                        .frame(minHeight: 44)
                } else {
                    Text("End workout?")
                        .font(.footnote.weight(.heavy))
                        .foregroundStyle(Palette.ink)
                    Button("Save workout") {
                        dismiss()
                        Task { await model.finishWorkout() }
                    }
                    .disabled(!hasSets)
                    .frame(minHeight: 44)
                    if !hasSets {
                        Text("No sets logged yet.")
                            .font(.caption2)
                            .foregroundStyle(Palette.secondary)
                    }
                    Button("Keep going") { dismiss() }
                        .frame(minHeight: 44)
                    Button("Discard", role: .destructive) { confirmingDiscard = true }
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 6)
        }
        .background(Palette.canvas)
    }
}
