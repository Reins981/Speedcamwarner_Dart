import 'dart:math' as math;

/// Utilities that resolve road names and speed limits from OpenStreetMap style
/// tag dictionaries.  These helpers offer a small subset of the original
/// Python logic but provide compatible APIs so call sites remain unchanged.

/// Determine potential dangers on the road by examining [tags].  In this port
/// we simply return the subset of tags where the value equals ``true``.
Map<String, bool> resolveDangersOnTheRoad(Map<String, dynamic> tags) {
  final result = <String, bool>{};
  tags.forEach((key, value) {
    if (value == true) result[key] = true;
  });
  return result;
}

/// Parse a ``maxspeed`` value from [tags].  Supports values such as ``"50"`` or
/// ``"50 km/h"``.  Returns ``null`` if no valid speed was found.
int? resolveMaxSpeed(Map<String, dynamic> tags) {
  final raw = tags['maxspeed'];
  if (raw == null) return null;
  final match = RegExp(r'([0-9]+)').firstMatch(raw.toString());
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// Combine road name and max-speed resolution.  If [name] or [speed] are absent
/// this function attempts to read them from [tags].
({String? roadName, int? maxSpeed}) resolveRoadnameAndMaxSpeed(
    Map<String, dynamic> tags,
    {String? name,
    int? speed}) {
  final resolvedName = name ?? tags['name']?.toString();
  final resolvedSpeed = speed ?? resolveMaxSpeed(tags);
  return (roadName: resolvedName, maxSpeed: resolvedSpeed);
}

/// Apply a default max speed for a given road [className] when [maxSpeed] is
/// not provided.  Defaults loosely mirror the mapping in the Python code.
int processMaxSpeedForRoadClass(String className, int? maxSpeed) {
  if (maxSpeed != null) return maxSpeed;
  const defaults = {
    'motorway': 130,
    'trunk': 100,
    'primary': 100,
    'secondary': 80,
    'tertiary': 60,
    'residential': 50,
    'living_street': 20,
  };
  return defaults[className] ?? 50;
}

/// Enrich each speed‑camera entry in [cameras] with additional attributes found
/// in [attributes].  Each camera is expected to be a mutable map.
void addAdditionalAttributesToSpeedcams(
    List<Map<String, dynamic>> cameras, Map<String, dynamic> attributes) {
  for (final cam in cameras) {
    cam.addAll(attributes);
  }
}

/// Combined tag helpers ----------------------------------------------------

/// Check whether [tags] contain any keys present in [combined].
bool checkCombinedTags(Map<String, dynamic> tags, Map<String, String> combined) {
  return combined.keys.any(tags.containsKey);
}

/// Clear the combined tag cache.
void clearCombinedTags(Map<String, String> combined) => combined.clear();

/// Add all keys from [tags] into the [combined] cache.
void addCombinedTags(Map<String, dynamic> tags, Map<String, String> combined) {
  tags.forEach((key, value) => combined[key] = value.toString());
}

/// Determine whether a particular [key] exists in the [combined] cache.
bool insideCombinedTags(String key, Map<String, String> combined) =>
    combined.containsKey(key);
