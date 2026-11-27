import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Performance V2 dark tokens (docs/DESIGN_SYSTEM.md) and the three metric
/// colours from the agreed watch mockup.
enum Palette {
    static let canvas = Color(red: 0x0B / 255, green: 0x0F / 255, blue: 0x13 / 255)
    static let surface = Color(red: 0x17 / 255, green: 0x1E / 255, blue: 0x24 / 255)
    static let ink = Color(red: 0xF5 / 255, green: 0xF7 / 255, blue: 0xF6 / 255)
    static let secondary = Color(red: 0xA5 / 255, green: 0xB0 / 255, blue: 0xB8 / 255)
    static let performance = Color(red: 0xD6 / 255, green: 0xFF / 255, blue: 0x60 / 255)
    static let caution = Color(red: 0xFF / 255, green: 0xD1 / 255, blue: 0x8B / 255)
    static let destructive = Color(red: 0xFF / 255, green: 0x85 / 255, blue: 0x87 / 255)

    static let sleep = Color(red: 0xC1 / 255, green: 0xA9 / 255, blue: 0xFF / 255)
    static let heart = Color(red: 0xFF / 255, green: 0x85 / 255, blue: 0x87 / 255)
    static let steps = Color(red: 0x7F / 255, green: 0xD8 / 255, blue: 0xFF / 255)

    /// The colour a status line is drawn in.
    static func tone(_ tone: Tone) -> Color {
        switch tone {
        case .good: return performance
        case .neutral: return secondary
        case .caution: return caution
        }
    }

    /// The accent of a metric's tile and detail screen.
    static func accent(_ metric: Metric) -> Color {
        switch metric {
        case .sleep: return sleep
        case .restingHr, .hrv: return heart
        case .steps: return steps
        }
    }
}
