import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Weight and reps (or seconds) side by side. The crown changes the box with
/// the green outline; a tap on the other box moves the outline; one button
/// logs the set.
struct SetPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var recorder: WorkoutRecorder
    let controller: WorkoutController

    @State private var values: SetValues?
    @State private var focus: SetInput.Field = .weight
    @State private var crown: Double = 0
    @State private var rpeSetId: String?
    @State private var showExercises = false
    @Environment(\.isLuminanceReduced) private var dimmed

    private var current: SetPosition? { _ = model.revision; return controller.cursor.current }
    private var unit: String { values?.inputUnit ?? model.inputUnit }
    private var timed: Bool { current?.exercise.kind == "duration" }

    var body: some View {
        // Scrolls so "Log set" stays reachable at large Dynamic Type sizes.
        ScrollView {
            VStack(spacing: 6) {
                topRow
                if let position = current, let values {
                    content(position: position, values: values)
                } else {
                    allDone
                }
            }
            .padding(.horizontal, 6)
        }
        .background(Palette.canvas)
        .focusable()
        .onAppear { reset() }
        .onChange(of: current?.set.setId) { _, _ in reset() }
        .digitalCrownRotation(
            $crown, from: SetInput.range(focus, unit: unit).lowerBound, through: SetInput.range(focus, unit: unit).upperBound,
            by: SetInput.step(focus, unit: unit), sensitivity: .medium, isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crown) { _, value in
            if let current = values { values = SetInput.applying(value, to: focus, values: current) }
        }
        .sheet(item: Binding(get: { rpeSetId.map(RpeTarget.init) }, set: { rpeSetId = $0?.id })) { target in
            RpeSheet(
                onChoose: { rpe in
                    model.act { try $0.setRpe(setId: target.id, rpe: rpe) }
                    rpeSetId = nil
                },
                onSkip: { rpeSetId = nil })
        }
        .sheet(isPresented: $showExercises) {
            ExercisesSheet(model: model, controller: controller)
        }
    }

    private var topRow: some View {
        HStack {
            Label(recorder.heartRate.map(String.init) ?? "\u{2014}", systemImage: "heart.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.heart)
                .accessibilityLabel(recorder.heartRate.map { "Heart rate \($0)" } ?? "Heart rate not available")
            Spacer()
            if !dimmed {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.clock(context.date.timeIntervalSince(controller.startedAt)))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
    }

    private func content(position: SetPosition, values: SetValues) -> some View {
        VStack(spacing: 6) {
            Text(position.exercise.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            Text("Set \(position.indexInExercise + 1) of \(position.countInExercise)")
                .font(.caption2)
                .foregroundStyle(Palette.secondary)
            HStack(spacing: 6) {
                if !timed {
                    box(
                        text: Self.weightText(SetInput.value(of: .weight, in: values)), caption: unit,
                        field: .weight,
                        label: "Weight \(Self.weightText(SetInput.value(of: .weight, in: values))) \(unit == "lb" ? "pounds" : "kilograms")")
                    box(
                        text: "\(Int(SetInput.value(of: .reps, in: values)))", caption: "reps", field: .reps,
                        label: "\(Int(SetInput.value(of: .reps, in: values))) reps")
                } else {
                    box(
                        text: "\(Int(SetInput.value(of: .seconds, in: values)))", caption: "sec", field: .seconds,
                        label: "\(Int(SetInput.value(of: .seconds, in: values))) seconds")
                }
            }
            Text("Turn the crown \u{00B7} tap the other box to switch")
                .font(.caption2)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                log(values)
            } label: {
                Text("Log set")
                    .font(.footnote.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.performance)
            .foregroundStyle(Palette.canvas)
        }
    }

    private func box(text: String, caption: String, field: SetInput.Field, label: String) -> some View {
        Button {
            focus = field
            syncCrown()
        } label: {
            VStack(spacing: 0) {
                Text(text)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(Palette.ink)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(focus == field ? Palette.performance : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(focus == field ? .isSelected : [])
    }

    private var allDone: some View {
        VStack(spacing: 6) {
            Text("All planned sets done")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            if let exerciseId = controller.addSetExerciseId {
                Button("Add set") {
                    _ = try? controller.addSet(exerciseId: exerciseId)
                    model.act { _ in }
                }
                .frame(minHeight: 44)
            }
            Button("Exercises") { showExercises = true }
                .frame(minHeight: 44)
        }
    }

    private func log(_ values: SetValues) {
        let setId = values.setId
        model.act { try $0.log(values) }
        // Only offer RPE when the set is stored.
        if controller.state.sets.contains(where: { $0.setId == setId && $0.status == "completed" }) {
            rpeSetId = setId
        }
    }

    private func reset() {
        guard let position = controller.cursor.current else {
            values = nil
            return
        }
        let next = controller.cursor.prefill(for: position, unit: model.inputUnit)
        values = next
        focus = position.exercise.kind == "duration" ? .seconds : .weight
        syncCrown()
    }

    private func syncCrown() {
        if let values { crown = SetInput.value(of: focus, in: values) }
    }

    static func weightText(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}

private struct RpeTarget: Identifiable {
    let id: String
}
