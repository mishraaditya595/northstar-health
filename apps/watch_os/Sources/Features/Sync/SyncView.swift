import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// What "synced" means on the watch: the time it last stored data from the
/// iPhone. The watch never claims more than that.
struct SyncView: View {
    let line: SyncLine
    var waiting = WaitingWorkouts(waiting: 0, waitingOtherAccount: 0)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch line {
            case .synced(let time):
                heading("Synced \(time)", color: Palette.performance)
                detail("Your iPhone sent data.")
            case .phoneAway(let time):
                heading("Phone not nearby", color: Palette.caution)
                detail("Showing data from \(time). It updates when your iPhone is nearby.")
            case .notPaired:
                heading("Open BeyondRep on your iPhone", color: Palette.secondary)
                detail("Sign in there to see your data here.")
            }
            ForEach(waiting.lines, id: \.self) { text in
                heading(text, color: Palette.caution)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.canvas)
    }

    private func heading(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
#Preview("Sync, all good") {
    SyncView(line: .synced("10:43"))
}

#Preview("Sync, phone away") {
    SyncView(line: .phoneAway("10:43"))
}

#Preview("Sync, workout waiting") {
    SyncView(line: .phoneAway("10:43"), waiting: WaitingWorkouts(waiting: 1, waitingOtherAccount: 0))
}

#Preview("Sync, not set up") {
    SyncView(line: .notPaired)
}
#endif
