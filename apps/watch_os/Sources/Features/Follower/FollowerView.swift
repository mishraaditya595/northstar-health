import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// A workout the iPhone owns, followed from the watch: Set, Rest and Overview
/// pages like a watch workout, but every change is a command to the iPhone and
/// shows as saved only when the iPhone lists it as applied. The iPhone's
/// engine is the only authority; the watch keeps no workout rows of its own.
/// Heart rate is read here from the watch's own session and never sent.
struct FollowerView: View {
    @ObservedObject var model: AppModel
    @State private var page = 0

    var body: some View {
        if let follower = model.follower {
            Group {
                if let state = readRevision(follower.state) {
                    TabView(selection: $page) {
                        FollowerSetPage(model: model, recorder: model.recorder, follower: follower, state: state)
                            .tag(0)
                        FollowerRestPage(model: model, follower: follower, state: state)
                            .tag(1)
                        FollowerOverviewPage(model: model, follower: follower, state: state)
                            .tag(2)
                    }
                    .tabViewStyle(.page)
                    .onChange(of: state.restDeadline) { _, deadline in
                        page = deadline == nil ? 0 : 1
                    }
                    .onChange(of: model.revision) { _, _ in
                        if page == 1, state.restRemaining(now: Date()) == nil { page = 0 }
                    }
                } else {
                    connecting
                }
            }
            .background(Palette.canvas)
        }
    }

    /// Redraws when the model bumps its revision.
    private func readRevision(_ state: PhoneWorkoutState?) -> PhoneWorkoutState? {
        _ = model.revision
        return state
    }

    private var connecting: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Connecting to your iPhone\u{2026}")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}

/// The line over every follower page: where the workout runs, heart rate, the
/// clock, and a notice when the iPhone has been quiet.
struct FollowerHeader: View {
    @ObservedObject var recorder: WorkoutRecorder
    let state: PhoneWorkoutState
    let stale: Bool
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Label(recorder.heartRate.map(String.init) ?? "\u{2014}", systemImage: "heart.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.heart)
                    .accessibilityLabel(recorder.heartRate.map { "Heart rate \($0)" } ?? "Heart rate not available")
                Spacer()
                if !dimmed {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(SetPage.clock(state.elapsed(now: context.date)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
            Text(stale ? "iPhone out of reach" : state.isPaused ? "On your iPhone \u{00B7} paused" : "On your iPhone")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(stale ? Palette.caution : Palette.secondary)
        }
    }
}

struct FollowerSetPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var recorder: WorkoutRecorder
    let follower: FollowerSession
    let state: PhoneWorkoutState

    @State private var values: SetValues?
    @State private var focus: SetInput.Field = .weight
    @State private var crown: Double = 0

    private var stale: Bool { _ = model.revision; return follower.isStale(now: Date()) }
    private var current: (exercise: PhoneExercise, set: PhoneSet, index: Int)? {
        guard let id = state.currentSetId, let exercise = state.exercise(ofSet: id), let set = state.set(id),
            let index = exercise.sets.firstIndex(where: { $0.setId == id })
        else { return nil }
        return (exercise, set, index)
    }
    private var unit: String { values?.inputUnit ?? model.inputUnit }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                FollowerHeader(recorder: recorder, state: state, stale: stale)
                if let current, let values {
                    content(current: current, values: values)
                } else {
                    Text("All planned sets done")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                    Text("Finish on the Overview page or on your iPhone.")
                        .font(.caption2)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                }
                failures
            }
            .padding(.horizontal, 6)
        }
        .focusable()
        .onAppear { reset() }
        .onChange(of: state.currentSetId) { _, _ in reset() }
        .digitalCrownRotation(
            $crown, from: SetInput.range(focus, unit: unit).lowerBound, through: SetInput.range(focus, unit: unit).upperBound,
            by: SetInput.step(focus, unit: unit), sensitivity: .medium, isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crown) { _, value in
            if let current = values { values = SetInput.applying(value, to: focus, values: current) }
        }
    }

    private func content(current: (exercise: PhoneExercise, set: PhoneSet, index: Int), values: SetValues)
        -> some View
    {
        let saving = follower.isSaving(setId: current.set.setId)
        return VStack(spacing: 6) {
            Text(current.exercise.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            Text("Set \(current.index + 1) of \(current.exercise.sets.count)")
                .font(.caption2)
                .foregroundStyle(Palette.secondary)
            HStack(spacing: 6) {
                if !current.exercise.isTimed {
                    box(text: SetPage.weightText(SetInput.value(of: .weight, in: values)), caption: unit, field: .weight)
                    box(text: "\(Int(SetInput.value(of: .reps, in: values)))", caption: "reps", field: .reps)
                } else {
                    box(text: "\(Int(SetInput.value(of: .seconds, in: values)))", caption: "sec", field: .seconds)
                }
            }
            Button {
                let now = Date()
                model.follow { follower, _ in
                    follower.logSet(
                        setId: values.setId, reps: values.reps, durationSeconds: values.durationSeconds,
                        loadGrams: values.loadGrams, inputUnit: values.inputUnit, now: now)
                }
            } label: {
                Text(saving ? "Saving\u{2026}" : "Log set")
                    .font(.footnote.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.performance)
            .foregroundStyle(Palette.canvas)
            .disabled(saving || stale)
        }
    }

    private func box(text: String, caption: String, field: SetInput.Field) -> some View {
        Button {
            focus = field
            if let values { crown = SetInput.value(of: field, in: values) }
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
        .accessibilityLabel("\(caption) \(text)")
        .accessibilityAddTraits(focus == field ? .isSelected : [])
    }

    /// A command the iPhone refused or never confirmed, with what to do.
    @ViewBuilder
    private var failures: some View {
        ForEach(follower.commands.filter { $0.phase != .pending }, id: \.id) { command in
            FollowerCommandNotice(model: model, command: command)
        }
    }

    private func reset() {
        guard let current else {
            values = nil
            return
        }
        let set = current.set
        let unitName = set.inputUnit ?? model.inputUnit
        let next = SetValues(
            setId: set.setId, exerciseId: current.exercise.exerciseId, position: set.position, kind: set.kind,
            inputUnit: unitName, reps: set.reps, durationSeconds: set.durationSeconds, loadGrams: set.loadGrams)
        values = next
        focus = current.exercise.isTimed ? .seconds : .weight
        crown = SetInput.value(of: focus, in: next)
    }
}

/// "Couldn't save" or the iPhone's refusal, with Try again and Dismiss.
struct FollowerCommandNotice: View {
    @ObservedObject var model: AppModel
    let command: FollowerCommand

    private var text: String {
        switch command.phase {
        case .rejected(let reason):
            switch reason {
            case "not_allowed": return "Open your iPhone to do that."
            case "not_editable": return "That set can't be changed now."
            default: return "Your iPhone didn't take that."
            }
        default: return "Couldn't save"
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.caution)
                .multilineTextAlignment(.center)
            HStack {
                if command.phase == .failed {
                    Button("Try again") { model.followerRetry(commandId: command.id) }
                        .frame(minHeight: 44)
                }
                Button("Dismiss") { model.followerDismiss(commandId: command.id) }
                    .frame(minHeight: 44)
            }
        }
    }
}

struct FollowerRestPage: View {
    @ObservedObject var model: AppModel
    let follower: FollowerSession
    let state: PhoneWorkoutState
    @Environment(\.isLuminanceReduced) private var dimmed

    private var stale: Bool { _ = model.revision; return follower.isStale(now: Date()) }

    var body: some View {
        VStack(spacing: 6) {
            Text("Rest")
                .font(.footnote.weight(.heavy))
                .foregroundStyle(Palette.secondary)
            if let deadline = state.restDeadline {
                TimelineView(.periodic(from: .now, by: dimmed ? 60 : 1)) { context in
                    ring(remaining: max(0, deadline.timeIntervalSince(context.date)))
                }
                HStack(spacing: 6) {
                    Button("+30 s") {
                        let left = Int(max(0, deadline.timeIntervalSinceNow).rounded(.up))
                        model.follow { $0.startRest(seconds: left + 30, now: $1) }
                    }
                    .frame(minHeight: 44)
                    Button("Skip") { model.follow { $0.clearRest(now: $1) } }
                        .frame(minHeight: 44)
                }
                .disabled(stale)
            } else {
                Text("Not resting")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .padding(.horizontal, 6)
    }

    private func ring(remaining: TimeInterval) -> some View {
        let seconds = Int(remaining.rounded(.up))
        let fraction = min(1, remaining / 90)
        return ZStack {
            Circle().stroke(Palette.surface, lineWidth: 8)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Palette.performance, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(dimmed ? "\(max(1, (seconds + 59) / 60)) min" : String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.title2.weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .foregroundStyle(Palette.ink)
        }
        .frame(width: 90, height: 90)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rest, \(seconds) seconds left")
    }
}

struct FollowerOverviewPage: View {
    @ObservedObject var model: AppModel
    let follower: FollowerSession
    let state: PhoneWorkoutState
    @State private var confirming: Confirm?

    private enum Confirm: String, Identifiable {
        case finish, discard
        var id: String { rawValue }
    }

    private var stale: Bool { _ = model.revision; return follower.isStale(now: Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(state.name)
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(Palette.ink)
                ForEach(state.exercises, id: \.exerciseId) { exercise in
                    HStack {
                        Text(exercise.name)
                            .font(.caption2)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("\(exercise.sets.filter(\.isCompleted).count)/\(exercise.sets.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Palette.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                Button(state.isPaused ? "Resume" : "Pause") {
                    model.follow { state.isPaused ? $0.resume(now: $1) : $0.pause(now: $1) }
                }
                .frame(minHeight: 44)
                .disabled(stale)
                Button("Finish workout") { confirming = .finish }
                    .frame(minHeight: 44)
                    .disabled(stale)
                Button("Discard", role: .destructive) { confirming = .discard }
                    .frame(minHeight: 44)
                    .disabled(stale)
            }
            .padding(.horizontal, 6)
        }
        .sheet(item: $confirming) { which in
            VStack(spacing: 6) {
                Text(which == .finish ? "Finish on your iPhone?" : "Discard this workout?")
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                if which == .discard {
                    Text("Your iPhone asks you to confirm.")
                        .font(.caption2)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                }
                Button(which == .finish ? "Finish" : "Discard", role: which == .discard ? .destructive : nil) {
                    model.follow { which == .finish ? $0.finish(now: $1) : $0.discard(now: $1) }
                    confirming = nil
                }
                .frame(minHeight: 44)
                Button("Keep going") { confirming = nil }
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 6)
        }
    }
}
