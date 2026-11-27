import Foundation

/// Reads the date-times of watch_link messages as epoch milliseconds. The
/// phone sends whole milliseconds, but any number of fractional digits is
/// accepted (the extra ones are cut) because the system formatter is only
/// sure of three.
public enum WatchTimestamp {
    public static func milliseconds(_ text: String) -> Int64? {
        var base = text.uppercased()
        var fractionMs: Int64 = 0
        if let dot = base.firstIndex(of: ".") {
            var end = base.index(after: dot)
            var digits = ""
            while end < base.endIndex, let ascii = base[end].asciiValue, ascii >= 48, ascii <= 57 {
                digits.append(base[end])
                end = base.index(after: end)
            }
            guard !digits.isEmpty else { return nil }
            let padded = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            fractionMs = Int64(padded) ?? 0
            base = String(base[..<dot]) + String(base[end...])
        }
        guard let date = ISO8601DateFormatter().date(from: base) else { return nil }
        return Int64(date.timeIntervalSince1970.rounded(.down)) * 1000 + fractionMs
    }

    public static func date(_ text: String) -> Date? {
        milliseconds(text).map { Date(timeIntervalSince1970: Double($0) / 1000) }
    }
}
