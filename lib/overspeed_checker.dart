import 'package:flutter/foundation.dart';

class OverspeedChecker {
  int? _lastMaxSpeed;

  /// Notifies listeners when the driver exceeds the allowed speed. `null`
  /// indicates that the vehicle is within the permitted range.
  final ValueNotifier<int?> difference = ValueNotifier<int?>(null);

  void process(int? currentSpeed, Map<String, dynamic> overspeedEntry) {
    if (currentSpeed == null) {
      print("Current speed is null.");
      return;
    }

    for (var entry in overspeedEntry.entries) {
      var maxSpeed = entry.value;
      print("Received Max Speed: $maxSpeed");

      if (maxSpeed is String && maxSpeed.contains("mph")) {
        maxSpeed = int.parse(maxSpeed.replaceAll(" mph", ""));
      }

      if (maxSpeed is int) {
        _lastMaxSpeed = maxSpeed;
        _calculate(currentSpeed, maxSpeed);
      }
    }

    if (overspeedEntry.isEmpty && _lastMaxSpeed != null) {
      print("Recalculating overspeed entry according to last max speed.");
      _calculate(currentSpeed, _lastMaxSpeed!);
    }
  }

  void _calculate(int currentSpeed, int maxSpeed) {
    if (currentSpeed > maxSpeed) {
      print(
          "Driver is too fast: expected speed $maxSpeed, actual speed $currentSpeed");
      _processEntry(currentSpeed - maxSpeed);
    } else {
      _processEntry(10000);
    }
  }

  void _processEntry(int value) {
    if (value == 10000) {
      difference.value = null;
      print("Resetting overspeed warning.");
    } else {
      difference.value = value;
      print("Overspeed by $value units.");
    }
  }
}
