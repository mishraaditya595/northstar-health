import Charts
import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Resting heart rate, HRV and steps: today, the phone's usual and the last
/// seven days.
struct TrendDetailView: View {
    let detail: DetailModel
    let metric: Metric
    let style: WeekChart.Style

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(detail.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.accent(metric))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(detail.value)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                    if let unit = detail.unit, detail.value != GlanceState.missing {
                        Text(unit)
                            .font(.caption2)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                if let caption = detail.caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(Palette.secondary)
                }
                Text("Last 7 days")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondary)
                WeekChart(detail: detail, metric: metric, style: style)
                if let average = detail.weekAverage {
                    Text("7-day average \(average)" + (detail.unit.map { " \($0)" } ?? ""))
                        .font(.caption2)
                        .foregroundStyle(Palette.secondary)
                }
            }
            .padding(.horizontal, 8)
        }
        .background(Palette.canvas)
    }
}

/// Seven days ending today. Bars for steps and sleep (today in full colour),
/// a line with a dashed "usual" rule for resting heart rate and HRV. A day
/// with no value has no mark; it is never drawn as 0.
struct WeekChart: View {
    enum Style { case bars, line }

    let detail: DetailModel
    let metric: Metric
    let style: Style

    private var present: [DayPoint] { detail.week.filter { $0.value != nil } }

    /// Sleep is charted in hours, the rest in their own unit.
    private func y(_ point: DayPoint) -> Double {
        let value = Double(point.value ?? 0)
        return metric == .sleep ? value / 60 : value
    }

    /// Zero or one rule, so the chart needs no optional content.
    private var usualRules: [Double] {
        style == .line ? detail.usual.map { [Double($0)] } ?? [] : []
    }

    var body: some View {
        let tint = Palette.accent(metric)
        Chart {
            ForEach(present, id: \.date) { point in
                if style == .bars {
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value("Value", y(point)))
                        .foregroundStyle(point.isToday ? tint : tint.opacity(0.45))
                } else {
                    LineMark(x: .value("Day", point.date, unit: .day), y: .value("Value", y(point)))
                        .foregroundStyle(tint)
                    PointMark(x: .value("Day", point.date, unit: .day), y: .value("Value", y(point)))
                        .foregroundStyle(tint)
                }
            }
            ForEach(usualRules, id: \.self) { usual in
                RuleMark(y: .value("Usual", usual))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .chartYScale(domain: .automatic(includesZero: style == .bars))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .frame(height: 90)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// "Last 7 days: Mon 40, Tue 44, Wed no data, ..." in words.
    private var spoken: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let days = detail.week.map { point -> String in
            let name = formatter.string(from: point.date)
            guard let value = point.value else { return "\(name), no data" }
            if metric == .sleep { return "\(name), \(GlanceState.sleepText(minutes: value))" }
            return "\(name), \(value)"
        }
        var sentence = "\(detail.title), last 7 days. " + days.joined(separator: ". ")
        if let usual = detail.usual { sentence += ". Your usual is \(usual)" }
        return sentence
    }
}

#if DEBUG
#Preview("Resting HR") {
    TrendDetailView(detail: PreviewData.detail(.restingHr), metric: .restingHr, style: .line)
}

#Preview("HRV") {
    TrendDetailView(detail: PreviewData.detail(.hrv), metric: .hrv, style: .line)
}

#Preview("Steps") {
    TrendDetailView(detail: PreviewData.detail(.steps), metric: .steps, style: .bars)
}
#endif
