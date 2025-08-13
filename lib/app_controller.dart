import 'package:flutter/foundation.dart';

import 'gps_thread.dart';
import 'location_manager.dart';
import 'rectangle_calculator.dart';
import 'package:geolocator/geolocator.dart';

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
  ///
  /// When [gpxFile] is provided the GPS module will replay coordinates from
  /// that GPX track instead of querying the device's sensors. Tests may supply
  /// a custom [positionStream] to avoid interacting with the real platform
  /// services.
  Future<void> start({String? gpxFile, Stream<Position>? positionStream}) async {
    if (_running) return;
    await locationManager.start(gpxFile: gpxFile, positionStream: positionStream);
    gps.start(source: locationManager.stream);
    calculator.run();
    _running = true;
  }

  /// Stop all background services and clean up resources.
  Future<void> stop() async {
    if (!_running) return;
    await gps.stop();
    await locationManager.stop();
    calculator.stop();
    _running = false;
  }

  /// Fully dispose all resources.  Subsequent calls to [start] will require a
  /// new [AppController] instance.
  Future<void> dispose() async {
    await stop();
    await gps.dispose();
    await locationManager.dispose();
    await calculator.dispose();
  }
}
