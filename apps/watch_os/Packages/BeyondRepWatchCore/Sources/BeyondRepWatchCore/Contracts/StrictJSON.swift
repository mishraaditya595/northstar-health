import Foundation

/// A contract violation. `code` is one of `unsupported_version`, `unknown_type`,
/// `unknown_key`, `missing_field`, `invalid_value` (the same codes as Dart).
public struct ContractError: Error, Equatable {
    public let code: String
    public init(_ code: String) { self.code = code }
}

/// An object whose keys were checked against a required and an optional set.
/// Codable alone ignores unknown keys, which the schemas forbid, so the codecs
/// read through this type.
struct StrictObject {
    let dict: [String: Any]

    init(_ raw: Any?, required: Set<String>, optional: Set<String> = []) throws {
        guard let dict = raw as? [String: Any] else { throw ContractError("invalid_value") }
        for key in dict.keys where !required.contains(key) && !optional.contains(key) {
            throw ContractError("unknown_key")
        }
        for key in required where dict[key] == nil {
            throw ContractError("missing_field")
        }
        self.dict = dict
    }

    func has(_ key: String) -> Bool { dict[key] != nil }

    static func isBool(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// True only when the pattern matches the whole string. ICU's `$` also
    /// matches before a trailing newline, which the schemas do not allow.
    private static func matches(_ value: String, _ pattern: String) -> Bool {
        guard let range = value.range(of: pattern, options: .regularExpression) else { return false }
        return range == value.startIndex..<value.endIndex
    }

    func string(_ key: String, min: Int = 1, max: Int? = nil, pattern: String? = nil) throws -> String {
        guard let value = dict[key] as? String, !(dict[key] is NSNumber) else {
            throw ContractError("invalid_value")
        }
        let length = value.unicodeScalars.count  // JSON Schema counts code points
        if length < min || (max != nil && length > max!) { throw ContractError("invalid_value") }
        if let pattern, !StrictObject.matches(value, pattern) { throw ContractError("invalid_value") }
        return value
    }

    func optionalString(_ key: String, min: Int = 1, max: Int? = nil) throws -> String? {
        try has(key) ? string(key, min: min, max: max) : nil
    }

    func uuid(_ key: String) throws -> String {
        try string(key, pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
    }

    func dateTime(_ key: String) throws -> String {
        let value = try string(
            key, pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?([Zz]|[+-][0-9]{2}:[0-9]{2})$")
        // ISO8601DateFormatter accepts 2026-02-30, so check each part (same as Dart).
        let d = Array(value.utf8).map { Int($0) - 48 }
        func num(_ range: Range<Int>) -> Int { range.reduce(0) { $0 * 10 + d[$1] } }
        let year = num(0..<4), month = num(5..<7), day = num(8..<10)
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        var valid = (1...12).contains(month) && day >= 1 && day <= days[month - 1]
            && num(11..<13) <= 23 && num(14..<16) <= 59 && num(17..<19) <= 59
        if let last = value.last, last != "Z", last != "z" {
            let n = d.count
            valid = valid && num((n - 5)..<(n - 3)) <= 23 && num((n - 2)..<n) <= 59
        }
        guard valid else { throw ContractError("invalid_value") }
        return value
    }

    func accountKey() throws -> String {
        try string("account_key", pattern: "^[0-9a-f]{64}$")
    }

    func localDate(_ key: String) throws -> String {
        try string(key, pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
    }

    func oneOf(_ key: String, _ allowed: Set<String>) throws -> String {
        guard let value = dict[key] as? String, allowed.contains(value) else {
            throw ContractError("invalid_value")
        }
        return value
    }

    func int(_ key: String, min: Int = 0, max: Int? = nil) throws -> Int {
        guard let number = dict[key] as? NSNumber, !StrictObject.isBool(number) else {
            throw ContractError("invalid_value")
        }
        let double = number.doubleValue
        guard double == double.rounded(), abs(double) < 9e15 else { throw ContractError("invalid_value") }
        let value = number.intValue
        if value < min || (max != nil && value > max!) { throw ContractError("invalid_value") }
        return value
    }

    func optionalInt(_ key: String, min: Int = 0, max: Int? = nil) throws -> Int? {
        try has(key) ? int(key, min: min, max: max) : nil
    }

    func bool(_ key: String) throws -> Bool {
        guard let number = dict[key] as? NSNumber, StrictObject.isBool(number) else {
            throw ContractError("invalid_value")
        }
        return number.boolValue
    }

    /// A number from 1 to 10 in half steps.
    func rpe(_ key: String) throws -> Double {
        guard let number = dict[key] as? NSNumber, !StrictObject.isBool(number) else {
            throw ContractError("invalid_value")
        }
        let value = number.doubleValue
        guard value >= 1, value <= 10, (value * 2) == (value * 2).rounded() else {
            throw ContractError("invalid_value")
        }
        return value
    }

    func optionalRpe(_ key: String) throws -> Double? {
        try has(key) ? rpe(key) : nil
    }

    func object(_ key: String, required: Set<String>, optional: Set<String> = []) throws -> StrictObject {
        try StrictObject(dict[key], required: required, optional: optional)
    }

    func array(_ key: String, max: Int? = nil) throws -> [Any] {
        guard let value = dict[key] as? [Any] else { throw ContractError("invalid_value") }
        if let max, value.count > max { throw ContractError("invalid_value") }
        return value
    }

    /// Parses `data` as a JSON object; anything else is `invalid_value`.
    static func parse(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data), let dict = object as? [String: Any] else {
            throw ContractError("invalid_value")
        }
        return dict
    }

    static func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
