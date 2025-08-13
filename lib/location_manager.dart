import 'dart:async';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:gpx/gpx.dart';

import 'gpx_loader.dart';
import 'logger.dart';
import 'rectangle_calculator.dart';

/// Port of the Python `LocationManager` which requested location updates on
/// Android and forwarded them to a queue.  In Dart we expose a stream of
/// [VectorData] instances constructed from [Position] updates provided by the
/// `geolocator` package.  Consumers can listen to [stream] to receive the
/// converted GPS samples.
class LocationManager extends Logger {
  LocationManager() : super('LocationManager');

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
  Future<void> start({
    Stream<Position>? positionStream,
    int minTime = 1000,
    double minDistance = 1,
    String? gpxFile,
  }) async {
    if (_running) return;
    _running = true;

    if (gpxFile != null) {
      printLogLine('Starting with GPX file $gpxFile');
      final samples = await _loadGpxSamples(gpxFile);
      printLogLine('Loaded ${samples.length} GPX samples');
      int index = 0;
      _gpxTimer = Timer.periodic(Duration(milliseconds: minTime), (
        Timer timer,
      ) {
        if (index < samples.length) {
          printLogLine('Emitting GPX sample ${index + 1}/${samples.length}');
          _controller.add(samples[index]);
          index++;
        } else {
          printLogLine('GPX playback finished');
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
        ),
      );
    }

    printLogLine('Listening to live position updates');
    _subscription = positionStreamLocal.listen(_onPosition);
  }

  Future<List<VectorData>> _loadGpxSamples(String gpxFile) async {
    printLogLine('Loading GPX data from $gpxFile');
    final gpxString = await loadGpx(gpxFile);
    final gpx = GpxReader().fromString(gpxString);
    final random = Random();
    final samples = <VectorData>[];

    for (final track in gpx.trks) {
      for (final segment in track.trksegs) {
        for (final point in segment.trkpts) {
          samples.add(
            VectorData(
              longitude: point.lon ?? 0.0,
              latitude: point.lat ?? 0.0,
              speed: (random.nextInt(26) + 10) * 3.6,
              bearing: (random.nextInt(51) + 200).toDouble(),
              accuracy: (random.nextInt(24) + 2).toDouble(),
              direction: '',
              gpsStatus: 1,
            ),
          );
        }
      }
    }
    printLogLine('GPX parsing produced ${samples.length} samples');
    return samples;
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
    printLogLine(
        'Received position update: ${position.latitude}, ${position.longitude}, speed ${(position.speed * 3.6).toStringAsFixed(2)} km/h');
    _controller.add(vector);
  }

  /// Stop listening to location updates but keep the stream open for restart.
  Future<void> stop() async {
    if (!_running) return;
    printLogLine('Stopping LocationManager');
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
