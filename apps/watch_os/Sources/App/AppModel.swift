import Foundation
import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Owns the watch journal and the glance the Home screen shows. All journal
/// access happens on the main actor, which is the one serial owner the
/// journal requires.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var glance: GlanceState = .notPaired

    private let journal: WatchJournal?
    private let inbox: PhoneInbox?
    private var midnightTask: Task<Void, Never>?

    init() {
        let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let journal = support.flatMap { try? WatchJournal(url: $0.appendingPathComponent("beyondrep-watch.sqlite")) }
        self.journal = journal
        self.inbox = journal.map { PhoneInbox(journal: $0) }
        refresh()
        scheduleMidnightRefresh()
    }

    deinit {
        midnightTask?.cancel()
    }

    func receive(applicationContext: [String: Any]) {
        try? inbox?.receive(applicationContext: applicationContext)
        refresh()
    }

    func receive(userInfo: [String: Any]) {
        try? inbox?.receive(userInfo: userInfo)
        refresh()
    }

    /// Recomputes the glance; also called when the app becomes active.
    func refresh() {
        guard let journal else { return }
        if let next = try? GlanceState.make(
            journal: journal, now: Date(), timeZone: .current, locale: .current)
        {
            glance = next
        }
    }

    /// Health values are for one local date, so the glance is recomputed when
    /// the date changes even if the app stays open.
    private func scheduleMidnightRefresh() {
        midnightTask?.cancel()
        midnightTask = Task { [weak self] in
            while !Task.isCancelled {
                let calendar = Calendar.current
                guard let midnight = calendar.nextDate(
                    after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 1),
                    matchingPolicy: .nextTime)
                else { return }
                let seconds = max(1, midnight.timeIntervalSinceNow)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if Task.isCancelled { return }
                self?.refresh()
            }
        }
    }
}
