// Copyright (c) 2025
//
// This file is a Dart port of the essential logic contained inside
// `CalculatorThreads.py` from the original Kivy/Android application.  It has
// been re‑implemented to operate in a standalone, Flutter/Dart environment.
//
// The goal of this file is to expose a reusable class that performs
// rectangular lookahead calculations for a moving vehicle.  It consumes
// ``VectorData`` objects representing GPS samples and produces bounding
// rectangles and predictive speed camera events.  The logic encapsulates
// coordinate conversions (between latitude/longitude and map tiles), simple
// geometric calculations, a lightweight concurrency model, and stubs for
// external interactions such as uploading new cameras to Google Drive or
// calling a predictive model.  By modelling the essential behaviour this
// implementation allows downstream code to remain agnostic of the original
// Python threading model.

import 'dart:async';
import 'dart:math';

/// Data class representing a single GPS/vector sample.  It contains the
/// current longitude/latitude, current speed (in km/h), a bearing angle
/// (clockwise from north) in degrees, a human readable direction, a GPS
/// status flag and a positional accuracy estimate.  These fields mirror the
/// tuple produced by ``get_vector_sections`` in the original Python code.
class VectorData {
  final double longitude;
  final double latitude;
  final double speed;
  final double bearing;
  final String direction;
  final int gpsStatus;
  final double accuracy;

  VectorData({
    required this.longitude,
    required this.latitude,
    required this.speed,
    required this.bearing,
    required this.direction,
    required this.gpsStatus,
    required this.accuracy,
  });
}

/// Data class representing a geographic rectangle.  Coordinates are stored
/// using latitude and longitude degrees.  ``minLat``/``maxLat`` refer to the
/// southern/northern boundaries and ``minLon``/``maxLon`` refer to the
/// western/eastern boundaries.
class GeoRect {
  final double minLat;
  final double minLon;
  final double maxLat;
  final double maxLon;

  const GeoRect({
    required this.minLat,
    required this.minLon,
    required this.maxLat,
    required this.maxLon,
  });

  @override
  String toString() {
    return 'GeoRect(minLat: $minLat, minLon: $minLon, maxLat: $maxLat, maxLon: $maxLon)';
  }
}

/// Data class representing a speed camera event.  The fields describe the
/// camera’s position, whether it is one of the predefined categories and a
/// human readable name (e.g. a road name).  This mirrors the dictionaries
/// produced by ``process_speed_cam_lookup_ahead_results`` and
/// ``process_predictive_cameras`` in the Python implementation.
class SpeedCameraEvent {
  final double latitude;
  final double longitude;
  final bool fixed;
  final bool traffic;
  final bool mobile;
  final bool predictive;
  final String name;

  SpeedCameraEvent({
    required this.latitude,
    required this.longitude,
    this.fixed = false,
    this.traffic = false,
    this.mobile = false,
    this.predictive = false,
    this.name = '',
  });

  @override
  String toString() {
    final List<String> flags = [];
    if (fixed) flags.add('fixed');
    if (traffic) flags.add('traffic');
    if (mobile) flags.add('mobile');
    if (predictive) flags.add('predictive');
    final flagStr = flags.isEmpty ? 'none' : flags.join(',');
    return 'Camera(lat: $latitude, lon: $longitude, flags: $flagStr, name: $name)';
  }
}

/// Stub representing a trained predictive model.  In the original Python
/// application a ``joblib`` model is loaded from disk and passed into
/// ``predict_speed_camera``.  In a Dart/Flutter environment you would likely
/// use a TensorFlow Lite model or call a remote inference service.  For the
/// purposes of this port the model is treated as an opaque object and the
/// prediction logic is encapsulated in a standalone function.
class PredictiveModel {
  PredictiveModel();
}

/// Predict whether a speed camera lies ahead of the vehicle.  This function
/// mimics ``predict_speed_camera`` from the Python code.  A real
/// implementation could load a TensorFlow Lite model (e.g. via the
/// ``tflite_flutter`` package) and feed in the numeric features.  Here we
/// provide a deterministic but illustrative stub: if the vehicle’s latitude
/// component truncated to three decimals is an even number we return a
/// synthetic camera offset by a small distance; otherwise ``null``.  The
/// returned position should be understood as approximate and used for
/// demonstration only.
Future<SpeedCameraEvent?> predictSpeedCamera({
  required PredictiveModel model,
  required double latitude,
  required double longitude,
  required String timeOfDay,
  required String dayOfWeek,
}) async {
  // This stub simply checks whether the sum of the integer parts of the
  // latitude and longitude is even and, if so, returns a camera roughly
  // 200 metres ahead in the direction of travel.  In a production system
  // replace this with your own model inference logic.
  final latInt = latitude.floor();
  final lonInt = longitude.floor();
  final even = ((latInt + lonInt) % 2) == 0;
  if (!even) return null;
  // Convert 200 m into degrees (approximation).  One degree of latitude is
  // roughly 111 km; adjust longitude by cos(lat).
  const cameraDistanceKm = 0.2; // 200 metres
  final deltaLat = cameraDistanceKm / 111.0;
  final deltaLon = cameraDistanceKm / (111.0 * cos(latitude * pi / 180.0));
  return SpeedCameraEvent(
    latitude: latitude + deltaLat,
    longitude: longitude + deltaLon,
    predictive: true,
    name: 'Predictive Camera',
  );
}

/// Stub that records a newly detected camera to persistent storage (e.g. a
/// JSON file) and optionally uploads the file to Google Drive.  In the
/// original code these responsibilities are delegated to the ``ServiceAccount``
/// module.  Here we emit a log message and return success.  Replace this
/// function with your own logic if you need to persist cameras to a back‑end
/// service.
Future<bool> uploadCameraToDrive({
  required String name,
  required double latitude,
  required double longitude,
}) async {
  // TODO: integrate with your own storage service.  For now just log.
  // In production you might use the ``googleapis`` package to push data to
  // Google Drive or Firestore.
  print('Uploading camera "$name" at ($latitude,$longitude) to Drive');
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return true;
}

/// The core class that mirrors the behaviour of ``RectangleCalculatorThread`` in
/// the Python project.  It listens for incoming GPS samples on a stream,
/// computes bounding rectangles and (optionally) predictive speed cameras and
/// emits events to registered listeners.  Termination is controlled via the
/// [dispose] method.
class RectangleCalculatorThread {
  /// Controller through which callers push new vector samples.  Each sample
  /// triggers a call to [processVector] from within the run loop.
  final StreamController<VectorData> _vectorStreamController =
      StreamController<VectorData>();

  /// Controller used to broadcast new rectangle boundaries.  Downstream
  /// subscribers should listen to this stream to redraw maps or update UI.
  final StreamController<GeoRect> _rectangleStreamController =
      StreamController<GeoRect>.broadcast();

  /// Controller used to broadcast detected speed camera events.  Multiple
  /// listeners may subscribe and react (e.g. warn the user or annotate a map).
  final StreamController<SpeedCameraEvent> _cameraStreamController =
      StreamController<SpeedCameraEvent>.broadcast();

  /// The predictive model used by [predictSpeedCamera].
  final PredictiveModel _predictiveModel;

  /// Whether the run loop should continue executing.  Set to ``false`` to
  /// stop processing samples.
  bool _running = true;

  /// The current zoom level used when converting between tiles and
  /// latitude/longitude.  You may expose this as a public field if your map
  /// layer needs to remain in sync with the calculator.
  int zoom = 17;

  RectangleCalculatorThread({PredictiveModel? model})
      : _predictiveModel = model ?? PredictiveModel() {
    _start();
  }

  /// Subscribe to rectangles produced by this calculator.  Each event
  /// represents a new bounding rectangle computed from the most recent GPS
  /// sample.  The rectangles emitted include both the current rectangle and
  /// the lookahead rectangle depending on the vehicle’s speed and direction.
  Stream<GeoRect> get rectangles => _rectangleStreamController.stream;

  /// Subscribe to speed camera notifications.  These may come from either
  /// predictive analytics (machine learning) or from some external data source.
  Stream<SpeedCameraEvent> get cameras => _cameraStreamController.stream;

  /// Feed a new sample into the calculator.  The [VectorData] is queued and
  /// processed in order.  This method does not block; processing occurs
  /// asynchronously on a background loop.
  void addVectorSample(VectorData vector) {
    if (!_running) return;
    _vectorStreamController.add(vector);
  }

  /// Terminate the run loop, closing all open streams.  Once called no further
  /// samples will be processed.  This is analogous to setting
  /// ``self.cond.terminate`` in the Python implementation and subsequently
  /// exiting the ``run`` method.
  Future<void> dispose() async {
    _running = false;
    await _vectorStreamController.close();
    await _rectangleStreamController.close();
    await _cameraStreamController.close();
  }

  /// Kick off the asynchronous processing loop.  In Dart we rely on
  /// asynchronous streams rather than OS threads.  This method listens for
  /// incoming vector samples and processes them sequentially.  If
  /// [_running] becomes false the loop exits gracefully.
  void _start() {
    // ignore: unawaited_futures
    _vectorStreamController.stream.listen((vector) async {
      if (!_running) return;
      try {
        await _processVector(vector);
      } catch (e, stack) {
        // Catch and log unexpected exceptions; avoid killing the stream.
        print('RectangleCalculatorThread error: $e\n$stack');
      }
    });
  }

  /// Process a single vector sample.  This routine extracts the relevant
  /// coordinate and speed information, computes an appropriate bounding
  /// rectangle and publishes it.  It also invokes the predictive model to
  /// determine whether a speed camera might exist ahead on the current route.
  Future<void> _processVector(VectorData vector) async {
    final double longitude = vector.longitude;
    final double latitude = vector.latitude;
    final double speedKmH = vector.speed;
    final double bearing = vector.bearing;

    // Compute the size of the rectangle based on the current speed.
    // In the original code ``calculate_rectangle_radius`` uses the diagonal
    // distance of a tile: here we define a simple linear relation where the
    // lookahead distance grows with speed.  Vehicles above 110 km/h
    // translate into a larger lookahead rectangle.
    final double lookAheadKm = _computeLookAheadDistance(speedKmH);
    final GeoRect rect = _computeBoundingRect(latitude, longitude, lookAheadKm);
    _rectangleStreamController.add(rect);

    // Predictive camera detection.  Evaluate the model with the current
    // coordinates and time.  This call is asynchronous to permit future
    // integration with remote services.
    final now = DateTime.now();
    final timeOfDay = _formatTimeOfDay(now);
    final dayOfWeek = _formatDayOfWeek(now);
    final SpeedCameraEvent? predicted = await predictSpeedCamera(
      model: _predictiveModel,
      latitude: latitude,
      longitude: longitude,
      timeOfDay: timeOfDay,
      dayOfWeek: dayOfWeek,
    );
    if (predicted != null) {
      // If a camera was predicted ahead, publish it on the camera stream and
      // optionally record it to persistent storage.
      _cameraStreamController.add(predicted);
      await uploadCameraToDrive(
        name: predicted.name,
        latitude: predicted.latitude,
        longitude: predicted.longitude,
      );
    }
  }

  /// Compute a lookahead distance in kilometres based upon the current speed.
  /// This function loosely mirrors the behaviour of ``speed_influence_on_rect_boundary``
  /// and related configuration in the original code.  At low speeds the
  /// rectangle covers roughly three kilometres ahead; as the speed increases
  /// the distance scales linearly.  You may adjust the coefficients to suit
  /// your application’s needs.
  double _computeLookAheadDistance(double speedKmH) {
    if (speedKmH <= 0) return 3.0;
    // Baseline 3 km plus 0.05 km per km/h above 50 km/h.  A cap of 10 km is
    // applied to prevent excessive lookahead ranges.
    final extra = max(0.0, speedKmH - 50.0) * 0.05;
    return min(3.0 + extra, 10.0);
  }

  /// Given a centre point and a lookahead distance in kilometres, compute a
  /// bounding rectangle.  The rectangle is aligned to the cardinal directions
  /// (north, south, east, west).  The calculation assumes a spherical Earth
  /// with radius 6371 km and converts the linear distances into degrees.
  GeoRect _computeBoundingRect(
      double latitude, double longitude, double lookAheadKm) {
    const double earthRadiusKm = 6371.0;
    final double latRadians = latitude * pi / 180.0;

    // Convert distance (km) into degrees latitude/longitude.  One degree
    // latitude spans approximately 111 km.  Longitude scales with cos(lat).
    final double deltaLat = (lookAheadKm / earthRadiusKm) * (180.0 / pi);
    final double deltaLon = (lookAheadKm / earthRadiusKm) * (180.0 / pi) /
        cos(latRadians);

    final double minLat = latitude - deltaLat;
    final double maxLat = latitude + deltaLat;
    final double minLon = longitude - deltaLon;
    final double maxLon = longitude + deltaLon;
    return GeoRect(minLat: minLat, minLon: minLon, maxLat: maxLat, maxLon: maxLon);
  }

  /// Convert a longitude/latitude pair into tile coordinates.  This is
  /// equivalent to the ``longlat2tile`` function in the Python code.  The
  /// returned values are fractional; integer parts correspond to tile indices
  /// and fractional parts to pixel offsets within those tiles.  See
  /// https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames for details.
  Point<double> longLatToTile(double latDeg, double lonDeg, int zoom) {
    final double latRad = latDeg * pi / 180.0;
    final double n = pow(2.0, zoom).toDouble();
    final double xTile = (lonDeg + 180.0) / 360.0 * n;
    final double yTile =
        (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * n;
    return Point<double>(xTile, yTile);
  }

  /// Convert tile coordinates back into a longitude/latitude pair.  This
  /// corresponds to the ``tile2longlat`` function in the Python code.  The
  /// integer parts of ``xTile`` and ``yTile`` identify the tile index;
  /// fractional parts specify an offset from the tile origin.
  Point<double> tileToLongLat(double xTile, double yTile, int zoom) {
    final double n = pow(2.0, zoom).toDouble();
    final double lonDeg = xTile / n * 360.0 - 180.0;
    final double latRad = atan(sinh(pi * (1.0 - 2.0 * yTile / n)));
    final double latDeg = latRad * 180.0 / pi;
    return Point<double>(lonDeg, latDeg);
  }

  /// Format a [DateTime] into HH:MM format.  This helper mirrors the
  /// ``strftime("%H:%M")`` call in the Python code.
  String _formatTimeOfDay(DateTime dt) {
    final String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(dt.hour)}:${twoDigits(dt.minute)}';
  }

  /// Format a [DateTime] into a weekday string.  This helper mirrors the
  /// ``strftime("%A")`` call in the Python code.  Dart’s [DateTime]
  /// enumerates weekdays from 1 (Monday) to 7 (Sunday).
  String _formatDayOfWeek(DateTime dt) {
    const List<String> names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return names[(dt.weekday - 1) % 7];
  }
}