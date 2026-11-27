import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Jump to an exercise or add one. Adding lists the phone's recent exercises.
struct ExercisesSheet: View {
    @ObservedObject var model: AppModel
    let controller: WorkoutController
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if adding {
                    Text("Add exercise")
                        .font(.footnote.weight(.heavy))
                        .foregroundStyle(Palette.secondary)
                    if model.recentExercises.isEmpty {
                        Text("No recent exercises. Add them in BeyondRep on your iPhone.")
                            .font(.caption2)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(model.recentExercises.enumerated()), id: \.offset) { _, item in
                        Button(item.name) {
                            model.act { _ = try $0.addExercise(name: item.name, kind: item.kind, muscle: nil) }
                            adding = false
                            dismiss()
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                } else {
                    Text("Exercises")
                        .font(.footnote.weight(.heavy))
                        .foregroundStyle(Palette.secondary)
                    ForEach(controller.template.exercises, id: \.exerciseId) { exercise in
                        Button {
                            controller.focus(exerciseId: exercise.exerciseId)
                            model.act { _ in }
                            dismiss()
                        } label: {
                            HStack {
                                Text(exercise.name)
                                    .lineLimit(2)
                                Spacer()
                                Text("\(done(exercise))/\(exercise.sets.count)")
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.secondary)
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityLabel("\(exercise.name), \(done(exercise)) of \(exercise.sets.count) sets done")
                    }
                    Button("+ Add exercise") { adding = true }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            .padding(.horizontal, 6)
        }
        .background(Palette.canvas)
    }

    private func done(_ exercise: TemplateExercise) -> Int {
        let ids = Set(exercise.sets.map(\.setId))
        return controller.state.sets.filter { ids.contains($0.setId) }.count
    }
}
