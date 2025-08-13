import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'gps_test_data_generator.dart';
import 'rectangle_calculator.dart';

/// Port of the Python `LocationManager` which requested location updates on
/// Android and forwarded them to a queue.  In Dart we expose a stream of
/// [VectorData] instances constructed from [Position] updates provided by the
/// `geolocator` package.  Consumers can listen to [stream] to receive the
/// converted GPS samples.
class LocationManager {
  final StreamController<VectorData> _controller =
      StreamController<VectorData>.broadcast();
  StreamSubscription<Position>? _subscription;
  Timer? _gpxTimer;
  bool _running = false;

  /// Whether the manager is currently publishing location updates.
  bool get isRunning => _running;

  /// Stream of [VectorData] samples derived from GPS updates.
  Stream<VectorData> get stream => _controller.stream;

  /// Start listening to location updates.
  ///
  /// When [positionStream] is supplied it will be used as the source of
  /// [Position] events.  Otherwise a stream from [Geolocator.getPositionStream]
  /// will be created.  The [minTime] and [minDistance] arguments mirror the
  /// behaviour of the original Python implementation where the underlying
  /// Android `LocationManager` was configured with a minimum update interval and
  /// distance.
  Future<void> start(
      {Stream<Position>? positionStream,
      int minTime = 1000,
      double minDistance = 1,
      String? gpxFile}) async {
    if (_running) return;
    _running = true;
    if (gpxFile != null) {
      final generator = GpsTestDataGenerator(gpxFile: gpxFile);
      final iterator = generator.iterator;
      _gpxTimer = Timer.periodic(Duration(milliseconds: minTime), (timer) {
        if (iterator.moveNext()) {
          final gps = iterator.current['data']['gps'];
          final vector = VectorData(
            longitude: (gps['longitude'] as num).toDouble(),
            latitude: (gps['latitude'] as num).toDouble(),
            // speed in GPX/test data is m/s -> convert to km/h
            speed: (gps['speed'] as num).toDouble() * 3.6,
            bearing: (gps['bearing'] as num).toDouble(),
            accuracy: (gps['accuracy'] as num).toDouble(),
            direction: '',
            gpsStatus: 1,
          );
          _controller.add(vector);
        } else {
          timer.cancel();
        }
      });
      return;
    }

    Stream<Position> positionStreamLocal;

    if (positionStream != null) {
      positionStreamLocal = positionStream;
    } else {
      // Request permissions when using the real geolocator stream.
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      positionStreamLocal = Geolocator.getPositionStream(
          locationSettings: LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: minDistance.round(),
      ));
    }

    _subscription = positionStreamLocal.listen(_onPosition);
  }

  void _onPosition(Position position) {
    final vector = VectorData(
      longitude: position.longitude,
      latitude: position.latitude,
      // Geolocator reports speed in m/s; convert to km/h for VectorData.
      speed: position.speed * 3.6,
      bearing: position.heading,
      accuracy: position.accuracy,
      direction: '',
      gpsStatus: 1,
    );
    _controller.add(vector);
  }

  /// Stop listening to location updates but keep the stream open for restart.
  Future<void> stop() async {
    if (!_running) return;
    await _subscription?.cancel();
    _subscription = null;
    _gpxTimer?.cancel();
    _gpxTimer = null;
    _running = false;
  }

  /// Permanently close the stream controller and cancel any listeners.
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}

