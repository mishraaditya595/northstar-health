enum LoadUnit { kg, lb, unknown }

/// Frozen storage decoder: unrecognized values stay unrecognized, not kg.
LoadUnit loadUnitFromStorage(String value) => switch (value) {
  'kg' => LoadUnit.kg,
  'lb' => LoadUnit.lb,
  _ => LoadUnit.unknown,
};

/// Use integer grams for calculations, preserving the original UI unit.
class LoadUnits {
  static const gramsPerPound = 453.59237;

  static int toGrams(double load, LoadUnit unit) {
    if (unit == LoadUnit.unknown) throw ArgumentError.value(unit, 'unit');
    if (!load.isFinite || load < 0 || load > 100000) {
      throw ArgumentError.value(load, 'load', 'Invalid load');
    }
    return (load * (unit == LoadUnit.kg ? 1000 : gramsPerPound)).round();
  }

  static double fromGrams(int grams, LoadUnit unit) {
    if (unit == LoadUnit.unknown) throw ArgumentError.value(unit, 'unit');
    if (grams < 0) throw ArgumentError.value(grams, 'grams');
    return grams / (unit == LoadUnit.kg ? 1000 : gramsPerPound);
  }
}
