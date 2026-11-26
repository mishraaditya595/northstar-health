import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Performance V2 dark tokens (docs/DESIGN_SYSTEM.md).
private enum Palette {
    static let canvas = Color(red: 0x0B / 255, green: 0x0F / 255, blue: 0x13 / 255)
    static let surface = Color(red: 0x17 / 255, green: 0x1E / 255, blue: 0x24 / 255)
    static let ink = Color(red: 0xF5 / 255, green: 0xF7 / 255, blue: 0xF6 / 255)
    static let secondary = Color(red: 0xA5 / 255, green: 0xB0 / 255, blue: 0xB8 / 255)
    static let performance = Color(red: 0xD6 / 255, green: 0xFF / 255, blue: 0x60 / 255)
    static let caution = Color(red: 0xFF / 255, green: 0xD1 / 255, blue: 0x8B / 255)
    static let destructive = Color(red: 0xFF / 255, green: 0x85 / 255, blue: 0x87 / 255)
}

/// The glance: phone-computed readiness and today's numbers, and the plan
/// names. Read-only: there is no Start button and nothing here claims a
/// workout is recorded.
struct HomeView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            switch model.glance {
            case .notPaired:
                Text("Open BeyondRep on your iPhone to sign in.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondary)
                    .padding()
            case .ready(let glance):
                GlanceContent(glance: glance)
            }
        }
        .background(Palette.canvas)
    }
}

private struct GlanceContent: View {
    let glance: Glance

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let readiness = glance.readiness {
                ReadinessRing(line: readiness)
            }
            Text(glance.caption)
                .font(.caption2)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(glance.tiles, id: \.label) { tile in
                    TileView(tile: tile)
                }
            }
            if let today = glance.today {
                Text("Today: \(today.name)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.performance)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !glance.plans.isEmpty {
                Text("Plans")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Palette.secondary)
                ForEach(glance.plans, id: \.id) { plan in
                    Text(plan.name)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 8)
    }
}

private struct ReadinessRing: View {
    let line: ReadinessLine

    private var color: Color {
        switch line.band {
        case "good": return Palette.performance
        case "fair": return Palette.caution
        default: return Palette.destructive
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Palette.surface, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(line.score, 0), 100)) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(line.score)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 52, height: 52)
            Text(line.headline)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness \(line.score) of 100, \(line.headline)")
    }
}

private struct TileView: View {
    let tile: GlanceTile

    private var hasValue: Bool { tile.value != GlanceState.missing }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.label)
                .font(.caption2)
                .foregroundStyle(Palette.secondary)
            Text(tile.value)
                .font(.headline.weight(.bold))
                .foregroundStyle(Palette.ink)
            if let unit = tile.unit {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// "Resting heart rate, 54 beats per minute", "Steps, no data".
    private var spoken: String {
        guard hasValue else { return "\(spokenLabel), no data" }
        switch tile.label {
        case "Resting HR": return "Resting heart rate, \(tile.value) beats per minute"
        case "HRV": return "Heart rate variability, \(tile.value) milliseconds"
        case "Sleep": return "Sleep, \(tile.value)" + (tile.unit.map { ", \($0)" } ?? "")
        default: return "\(tile.label), \(tile.value)"
        }
    }

    private var spokenLabel: String {
        switch tile.label {
        case "Resting HR": return "Resting heart rate"
        case "HRV": return "Heart rate variability"
        default: return tile.label
        }
    }
}

#Preview {
    HomeView(model: AppModel())
}
