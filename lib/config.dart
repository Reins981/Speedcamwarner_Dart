import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Loads configuration values from `assets/config.json` and provides
/// convenient lookup helpers.  The JSON file consolidates options from the
/// original Python `set_configs()` methods so the Flutter port can adjust its
/// behaviour without code changes.
class AppConfig {
  static Map<String, dynamic> _values = {};

  /// Load the configuration from the bundled asset. Should be called once
  /// during application start before any configuration values are accessed.
  static Future<void> load() async {
    final jsonStr = await rootBundle.loadString('assets/config.json');
    _values = jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  /// Directly assign configuration [values]. Primarily intended for tests
  /// where loading from the bundled asset is either undesirable or
  /// impractical.  Existing values are replaced.
  static void loadFromMap(Map<String, dynamic> values) {
    _values = values;
  }

  static Future<Map<String, dynamic>> loadAssetConfig(String path) async {
    final jsonString = await rootBundle.loadString(path);
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    return data;
  }

  /// Retrieve a configuration value using dot separated [path] notation.
  /// Returns `null` if the key does not exist or if [T] does not match.
  static T? get<T>(String path) {
    final segments = path.split('.');
    dynamic current = _values;
    for (final segment in segments) {
      if (current is Map<String, dynamic> && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current as T?;
  }
}
