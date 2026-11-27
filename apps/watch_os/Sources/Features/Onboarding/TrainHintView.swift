import SwiftUI

/// Shown once: a user may not know Home and Train are two pages.
struct TrainHintView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "digitalcrown.horizontal.arrow.clockwise")
                .font(.title2)
                .foregroundStyle(Palette.performance)
                .accessibilityHidden(true)
            Text("Turn the crown for your workouts")
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button("Got it", action: onDismiss)
                .tint(Palette.performance)
        }
        .padding()
        .background(Palette.canvas)
    }
}

#if DEBUG
#Preview {
    TrainHintView {}
}
#endif
