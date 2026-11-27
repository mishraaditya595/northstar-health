import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// A ring that counts down to the rest deadline. The deadline comes from the
/// journal, so it is right after a relaunch; the haptic at zero is scheduled by
/// `AppModel` from the same deadline.
struct RestPage: View {
    @ObservedObject var model: AppModel
    let controller: WorkoutController

    @Environment(\.isLuminanceReduced) private var dimmed

    private var deadline: Date? { _ = model.revision; return controller.restDeadline }

    var body: some View {
        VStack(spacing: 6) {
            Text("Rest")
                .font(.footnote.weight(.heavy))
                .foregroundStyle(Palette.secondary)
            if let deadline {
                TimelineView(.periodic(from: .now, by: dimmed ? 60 : 1)) { context in
                    ring(remaining: max(0, deadline.timeIntervalSince(context.date)))
                }
                HStack(spacing: 6) {
                    Button("+30 s") { model.act { try $0.extendRest() } }
                        .frame(minHeight: 44)
                    Button("Skip") { model.act { try $0.skipRest() } }
                        .frame(minHeight: 44)
                }
                if let next = controller.cursor.current {
                    Text("Next: \(next.exercise.name) \u{00B7} set \(next.indexInExercise + 1) of \(next.countInExercise)")
                        .font(.caption2)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Not resting")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .padding(.horizontal, 6)
        .background(Palette.canvas)
    }

    private func ring(remaining: TimeInterval) -> some View {
        let fraction = min(1, remaining / max(1, model.restTotalSeconds))
        let seconds = Int(remaining.rounded(.up))
        return ZStack {
            Circle().stroke(Palette.surface, lineWidth: 8)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Palette.performance, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // The always-on dimmed state shows whole minutes, no seconds.
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
