import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

struct SummaryView: View {
    @ObservedObject var model: AppModel
    let summary: WorkoutSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Done")
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(Palette.performance)
                Text(summary.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                stat("Time", SetPage.clock(summary.elapsed))
                stat("Sets", "\(summary.sets)")
                if let heartRate = summary.averageHeartRate {
                    stat("Heart rate", "\(heartRate) avg")
                }
                Text(model.summaryStatus)
                    .font(.caption2)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Done") { model.dismissSummary() }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 6)
        }
        .background(Palette.canvas)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.caption2).foregroundStyle(Palette.secondary)
            Spacer()
            Text(value)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
