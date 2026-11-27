import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// The glance: phone-computed readiness and today's numbers. Read-only:
/// nothing here claims a workout is recorded.
struct HomePage: View {
    let glance: GlanceState
    let syncLine: SyncLine
    @Binding var page: WatchPage

    var body: some View {
        ScrollView {
            switch glance {
            case .notPaired:
                Text("Open BeyondRep on your iPhone to sign in.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondary)
                    .padding()
            case .ready(let glance):
                GlanceContent(glance: glance, syncLine: syncLine)
            }
        }
        .background(Palette.canvas)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    page = .train
                } label: {
                    Image(systemName: "dumbbell.fill")
                }
                .tint(Palette.performance)
                .accessibilityLabel("Train")
            }
        }
    }
}

private struct GlanceContent: View {
    let glance: Glance
    let syncLine: SyncLine
    @Environment(\.dynamicTypeSize) private var typeSize

    /// At the largest text sizes two columns no longer fit.
    private var columns: [GridItem] {
        let count = typeSize >= .accessibility1 ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 6), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SyncStatusLine(line: syncLine)
            if let readiness = glance.readiness {
                NavigationLink(value: WatchRoute.readiness) {
                    ReadinessHero(line: readiness, reason: glance.readinessReason)
                }
                .buttonStyle(.plain)
            }
            Text(glance.caption)
                .font(.caption2)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(glance.tiles, id: \.label) { tile in
                    NavigationLink(value: WatchRoute.metric(tile.metric)) {
                        TileView(tile: tile)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 8)
    }
}

/// "● Synced 10:43" or "● Phone not nearby"; nothing when not paired. A tap
/// opens the Sync screen.
private struct SyncStatusLine: View {
    let line: SyncLine

    var body: some View {
        switch line {
        case .notPaired:
            EmptyView()
        case .synced(let time):
            link(color: Palette.performance, text: "Synced \(time)")
        case .phoneAway:
            link(color: Palette.caution, text: "Phone not nearby")
        }
    }

    private func link(color: Color, text: String) -> some View {
        NavigationLink(value: WatchRoute.sync) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityHint("Opens sync details")
    }
}

struct ReadinessHero: View {
    let line: ReadinessLine
    let reason: String?

    private var color: Color {
        switch line.band {
        case "good": return Palette.performance
        case "fair": return Palette.caution
        default: return Palette.destructive
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ReadinessRing(score: line.score, color: color, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.headline)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Readiness \(line.score) of 100, \(line.headline)" + (reason.map { ". \($0)" } ?? ""))
        .accessibilityHint("Opens readiness details")
    }
}

struct ReadinessRing: View {
    let score: Int
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Palette.surface, lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(score, 0), 100)) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
        .frame(width: size, height: size)
    }
}

/// One tile: label, big value, one coloured status line. Every tile has the
/// same shape; at the largest text sizes the height is free.
private struct TileView: View {
    let tile: GlanceTile
    @Environment(\.dynamicTypeSize) private var typeSize

    private var hasValue: Bool { tile.value != GlanceState.missing }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.label)
                .font(.caption2)
                .foregroundStyle(Palette.accent(tile.metric))
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(tile.value)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit = tile.unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(Palette.secondary)
                }
            }
            Text(tile.status ?? " ")
                .font(.caption2)
                .foregroundStyle(Palette.tone(tile.tone))
                .lineLimit(typeSize >= .accessibility1 ? nil : 1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .frame(height: typeSize >= .accessibility1 ? nil : 76)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Opens details")
    }

    /// "Resting heart rate 61 beats per minute, 2 below your usual", "Steps, no data".
    private var spoken: String {
        guard hasValue else { return "\(spokenLabel), no data" }
        let status = tile.status.map { ", " + Self.spokenStatus($0) } ?? ""
        switch tile.metric {
        case .restingHr: return "Resting heart rate \(tile.value) beats per minute\(status)"
        case .hrv: return "Heart rate variability \(tile.value) milliseconds\(status)"
        case .sleep: return "Sleep \(tile.value)\(status)"
        case .steps: return "Steps \(tile.value)\(status)"
        }
    }

    private var spokenLabel: String {
        switch tile.metric {
        case .restingHr: return "Resting heart rate"
        case .hrv: return "Heart rate variability"
        case .sleep: return "Sleep"
        case .steps: return "Steps"
        }
    }

    /// "−2 vs usual" is read as "2 below your usual".
    static func spokenStatus(_ status: String) -> String {
        if status.hasSuffix(" vs usual") {
            let number = status.dropLast(" vs usual".count)
            if number.hasPrefix("\u{2212}") { return "\(number.dropFirst()) below your usual" }
            if number.hasPrefix("+") { return "\(number.dropFirst()) above your usual" }
        }
        return status
    }
}

#if DEBUG
#Preview("Home") {
    NavigationStack {
        HomePage(glance: PreviewData.glance, syncLine: .synced("10:43"), page: .constant(.home))
    }
}

#Preview("Home, phone away") {
    NavigationStack {
        HomePage(glance: PreviewData.glance, syncLine: .phoneAway("10:43"), page: .constant(.home))
    }
}

#Preview("Home, not paired") {
    NavigationStack {
        HomePage(glance: .notPaired, syncLine: .notPaired, page: .constant(.home))
    }
}
#endif
