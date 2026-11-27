import Foundation

/// The numbers behind the set screen: crown steps and ranges, and the
/// conversion between the weight the person sees (kg or lb, the binding unit)
/// and the grams a set stores. Grams use 1000 per kg and 453.59237 per lb,
/// rounded, the same as the phone's `load_units.dart`.
public enum SetInput {
    public enum Field: Equatable {
        case weight, reps, seconds
    }

    private static func gramsPerUnit(_ unit: String) -> Double { unit == "lb" ? 453.59237 : 1000 }

    public static func step(_ field: Field, unit: String) -> Double {
        switch field {
        case .weight: return unit == "lb" ? 5 : 2.5
        case .reps: return 1
        case .seconds: return 5
        }
    }

    public static func range(_ field: Field, unit: String) -> ClosedRange<Double> {
        switch field {
        case .weight: return unit == "lb" ? 0...1100 : 0...500
        case .reps: return 1...100
        case .seconds: return 5...3600
        }
    }

    public static func clamp(_ value: Double, _ field: Field, unit: String) -> Double {
        let bounds = range(field, unit: unit)
        return min(bounds.upperBound, max(bounds.lowerBound, value))
    }

    /// Grams for a displayed weight; nil (no load) for 0 or less.
    public static func grams(displayWeight: Double, unit: String) -> Int? {
        guard displayWeight > 0 else { return nil }
        return Int((displayWeight * gramsPerUnit(unit)).rounded())
    }

    /// The displayed weight for stored grams, snapped to the crown step.
    public static func displayWeight(grams: Int?, unit: String) -> Double {
        guard let grams, grams > 0 else { return 0 }
        let step = SetInput.step(.weight, unit: unit)
        let raw = Double(grams) / gramsPerUnit(unit)
        return clamp((raw / step).rounded() * step, .weight, unit: unit)
    }

    /// The value of `field` in `values`, in display units.
    public static func value(of field: Field, in values: SetValues) -> Double {
        switch field {
        case .weight: return displayWeight(grams: values.loadGrams, unit: values.inputUnit)
        case .reps: return Double(values.reps ?? 10)
        case .seconds: return Double(values.durationSeconds ?? 30)
        }
    }

    /// `values` with `field` set to `value` (display units, clamped).
    public static func applying(_ value: Double, to field: Field, values: SetValues) -> SetValues {
        var out = values
        let clamped = clamp(value, field, unit: values.inputUnit)
        switch field {
        case .weight: out.loadGrams = grams(displayWeight: clamped, unit: values.inputUnit)
        case .reps: out.reps = Int(clamped.rounded())
        case .seconds: out.durationSeconds = Int(clamped.rounded())
        }
        return out
    }
}
