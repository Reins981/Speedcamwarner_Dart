import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'overspeed_checker.dart';

/// Plays a short beep sequence whenever the current speed exceeds the last
/// provided speed limit.
///
/// The [OverspeedChecker] publishes the difference between the current speed and
/// the configured speed limit. This helper listens to that notifier and emits
/// three short beeps when the difference becomes positive. Once the speed drops
/// back below the limit the warning is reset and can trigger again.
class OverspeedBeeper {
  final OverspeedChecker checker;
  late final VoidCallback _listener;

  bool _alerted = false;

  OverspeedBeeper({required this.checker}) {
    _listener = _handleChange;
    checker.difference.addListener(_listener);
  }

  void _handleChange() {
    final diff = checker.difference.value;
    if (diff != null && diff > 0) {
      if (!_alerted) {
        _alerted = true;
        _beepThreeTimes();
      }
    } else {
      // Reset once we are back under the limit.
      _alerted = false;
    }
  }

  Future<void> _beepThreeTimes() async {
    for (var i = 0; i < 3; i++) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {
        // Ignore any audio errors in headless environments.
      }
      // Wait a bit before playing the next beep.
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> dispose() async {
    checker.difference.removeListener(_listener);
  }
}

