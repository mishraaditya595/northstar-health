import SwiftUI

/// A non-recording UI scaffold. HealthKit permissions and session management
/// must be introduced with tested native background ownership and persistence.
struct WorkoutHomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("NORTHSTAR")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.5)
                    .foregroundStyle(.green)

                Text("Train on your terms.")
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                Text("Watch workout tracking is coming soon.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Label("No workout is being recorded", systemImage: "watch.analogdisplay")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Preview only. No workout recording is active.")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    WorkoutHomeView()
}
