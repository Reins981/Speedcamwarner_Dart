/// Enumeration of road classes that are filtered from lookups.
///
/// The original Python implementation defined a long list of road
/// classes named with letters (A, B, C …).  Only class `J` was used in
/// practice and mapped to the numeric identifier `10000`.  The
/// [FilteredRoadClass] enum mirrors this behaviour.  A convenience
/// [hasValue] method is provided for quick membership checks similar to
/// the `Enum.has_value` helper in Python.
enum FilteredRoadClass {
  J(10000);

  const FilteredRoadClass(this.value);
  final int value;

  /// Return `true` when [value] matches one of the defined road classes.
  static bool hasValue(int value) {
    for (final cls in FilteredRoadClass.values) {
      if (cls.value == value) return true;
    }
    return false;
  }
}
