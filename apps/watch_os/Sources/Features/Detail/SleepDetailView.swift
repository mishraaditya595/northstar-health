import Charts
import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Time asleep, the phone's score, the stages and the last seven nights.
struct SleepDetailView: View {
    let detail: DetailModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sleep")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.sleep)
                Text(detail.value)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                if let caption = detail.caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(Palette.performance)
                }
                if let stages = detail.stages {
                    StagesBar(stages: stages)
                }
                Text("Last 7 nights")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondary)
                WeekChart(detail: detail, metric: .sleep, style: .bars)
                if let average = detail.weekAverage {
                    Text("7-night average \(GlanceState.sleepText(minutes: average))")
                        .font(.caption2)
                        .foregroundStyle(Palette.secondary)
                }
            }
            .padding(.horizontal, 8)
        }
        .background(Palette.canvas)
    }
}

private struct StagesBar: View {
    let stages: SleepStages

    private var parts: [(name: String, minutes: Int, color: Color)] {
        [
            ("Deep", stages.deep, Palette.sleep),
            ("Core", stages.core, Palette.sleep.opacity(0.55)),
            ("REM", stages.rem, Palette.steps),
            ("Awake", stages.awake, Palette.caution),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let total = Double(max(parts.reduce(0) { $0 + $1.minutes }, 1))
                HStack(spacing: 2) {
                    ForEach(parts, id: \.name) { part in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(part.color)
                            .frame(width: max(2, proxy.size.width * Double(part.minutes) / total))
                    }
                }
            }
            .frame(height: 10)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 2) {
                ForEach(parts, id: \.name) { part in
                    HStack(spacing: 4) {
                        Circle().fill(part.color).frame(width: 6, height: 6)
                        Text("\(part.name) \(GlanceState.sleepText(minutes: part.minutes))")
                            .font(.caption2)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Sleep stages: "
                + parts.map { "\($0.name) \(GlanceState.sleepText(minutes: $0.minutes))" }.joined(separator: ", "))
    }
}

#if DEBUG
#Preview("Sleep") {
    SleepDetailView(detail: PreviewData.detail(.sleep))
}
#endif
