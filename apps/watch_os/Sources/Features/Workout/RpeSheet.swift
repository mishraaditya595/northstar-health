import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Asked after each logged set. It closes itself after 5 s with no choice.
struct RpeSheet: View {
    let onChoose: (Double) -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("How hard was it?")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text("RPE, optional")
                .font(.caption2)
                .foregroundStyle(Palette.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach([6, 7, 8, 9, 10], id: \.self) { value in
                    Button("\(value)") { onChoose(Double(value)) }
                        .frame(minHeight: 44)
                        .accessibilityLabel("RPE \(value)")
                }
                Button("Skip", action: onSkip)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 6)
        .background(Palette.canvas)
        .task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled { onSkip() }
        }
    }
}

#if DEBUG
#Preview("RPE") {
    RpeSheet(onChoose: { _ in }, onSkip: {})
}
#endif
