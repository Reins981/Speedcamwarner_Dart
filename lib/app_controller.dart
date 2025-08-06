import 'package:flutter/foundation.dart';

import 'gps_thread.dart';
import 'location_manager.dart';
import 'rectangle_calculator.dart';

/// Central place that wires up background modules and manages their
/// lifecycles.  The original Python project spawned numerous threads; in
/// Dart we keep long lived objects and expose explicit [start] and [stop]
/// hooks so the Flutter UI can control them.
class AppController {
  AppController() {
    // Pipe GPS samples directly into the calculator.
    gps.stream.listen(calculator.addVectorSample);
  }

  /// Handles GPS sampling.
  final GpsThread gps = GpsThread();

  /// Provides real position updates using the device's sensors.
  final LocationManager locationManager = LocationManager();

  /// Performs rectangle calculations and camera lookups.
  final RectangleCalculatorThread calculator = RectangleCalculatorThread();

  /// Publishes the latest AR detection status so UI widgets can react.
  final ValueNotifier<String> arStatusNotifier =
      ValueNotifier<String>('Idle');

  bool _running = false;

  /// Start background services if not already running.
  Future<void> start() async {
    if (_running) return;
    await locationManager.start();
    gps.start(source: locationManager.stream);
    calculator.run();
    _running = true;
  }

  /// Stop all background services and clean up resources.
  Future<void> stop() async {
    if (!_running) return;
    await gps.stop();
    await locationManager.stop();
    await calculator.dispose();
    _running = false;
  }
}
