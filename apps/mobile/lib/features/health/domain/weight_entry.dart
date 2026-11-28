const minWeightKg = 20.0;
const maxWeightKg = 400.0;

final _weightPattern = RegExp(r'^\d+(\.\d*)?$');

/// Kilograms rounded to 0.1 from what the user typed (one comma or point as
/// the separator, digits only); null when it is not a number or is outside
/// [minWeightKg]..[maxWeightKg] after rounding.
double? parseWeightKg(String input) {
  final text = input.trim().replaceFirst(',', '.');
  if (!_weightPattern.hasMatch(text)) return null;
  final value = double.parse(text);
  if (!value.isFinite) return null;
  final kg = (value * 10).round() / 10;
  return kg < minWeightKg || kg > maxWeightKg ? null : kg;
}
