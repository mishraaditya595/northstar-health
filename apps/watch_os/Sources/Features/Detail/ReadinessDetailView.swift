import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// The score, the phone's one-line reason and one line per input, in the
/// phone's wording.
struct ReadinessDetailView: View {
    let line: ReadinessLine
    let reason: String?
    let factors: [Glance.Factor]

    private var color: Color {
        switch line.band {
        case "good": return Palette.performance
        case "fair": return Palette.caution
        default: return Palette.destructive
        }
    }

    private func name(_ input: String) -> String {
        switch input {
        case "sleep": return "Sleep"
        case "hrv": return "HRV"
        case "resting_hr": return "Resting HR"
        case "training_load": return "Training load"
        default: return input
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ReadinessRing(score: line.score, color: color, size: 52)
                    Text(line.headline)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Energy \(line.score) of 100, \(line.headline)")
                if let reason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(factors, id: \.input) { factor in
                    HStack {
                        Text(name(factor.input))
                            .font(.caption2)
                            .foregroundStyle(Palette.secondary)
                        Spacer(minLength: 4)
                        Text(factor.status)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.tone(factor.tone))
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(8)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(name(factor.input)), \(factor.status)")
                }
            }
            .padding(.horizontal, 8)
        }
        .background(Palette.canvas)
    }
}

#if DEBUG
#Preview("Readiness") {
    if case .ready(let glance) = PreviewData.glance, let line = glance.readiness {
        ReadinessDetailView(line: line, reason: glance.readinessReason, factors: glance.factors)
    }
}
#endif
