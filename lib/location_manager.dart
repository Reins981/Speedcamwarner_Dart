import 'dart:async';

import 'package:geolocator/geolocator.dart';

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
      double minDistance = 1}) async {
    Stream<Position> stream;

    if (positionStream != null) {
      stream = positionStream;
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

      stream = Geolocator.getPositionStream(
          locationSettings: LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: minDistance.round(),
        timeLimit: Duration(milliseconds: minTime),
      ));
    }

    _subscription = stream.listen(_onPosition);
  }

  void _onPosition(Position position) {
    final vector = VectorData(
      longitude: position.longitude,
      latitude: position.latitude,
      speed: position.speed,
      bearing: position.heading,
      accuracy: position.accuracy,
      direction: '',
      gpsStatus: 1,
    );
    _controller.add(vector);
  }

  /// Stop listening to location updates and close the stream.
  Future<void> stop() async {
    await _subscription?.cancel();
    await _controller.close();
  }
}

