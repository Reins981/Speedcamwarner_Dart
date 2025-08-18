import 'package:flutter/foundation.dart';

/// Computes overspeed differences based on the current speed and a
/// configurable speed limit. The GPS thread feeds speed updates via
/// [updateSpeed] while the rectangle calculator supplies new limits via
/// [updateLimit]. The latest difference is published through [difference]
/// where `null` means the driver is within the allowed range.
class OverspeedChecker {
  final ValueNotifier<int?> difference = ValueNotifier<int?>(null);

  int _currentSpeed = 0;
  int? _maxSpeed;

  /// Convenience getter primarily used in tests.
  int? get lastDifference => difference.value;

  /// Update the current driving [speed] in km/h.
  void updateSpeed(int speed) {
    _currentSpeed = speed;
    _recalculate();
  }

  /// Update the maximum allowed speed. A `null` or `10000` value resets the
  /// checker and clears the last difference. String values like "50 mph" are
  /// parsed and converted to km/h.
  void updateLimit(dynamic maxSpeed) {
    if (maxSpeed == null || maxSpeed == 10000) {
      _maxSpeed = null;
      difference.value = null;
      return;
    }
    int? limit;
    if (maxSpeed is int) {
      limit = maxSpeed;
    } else if (maxSpeed is String) {
      final cleaned = maxSpeed.replaceAll(' mph', '');
      limit = int.tryParse(cleaned);
    }
    if (limit == null) {
      _maxSpeed = null;
      difference.value = null;
    } else {
      _maxSpeed = limit;
      _recalculate();
    }
  }

  void _recalculate() {
    if (_maxSpeed == null) {
      difference.value = null;
      return;
    }
    final diff = _currentSpeed - _maxSpeed!;
    difference.value = diff > 0 ? diff : null;
  }
}
