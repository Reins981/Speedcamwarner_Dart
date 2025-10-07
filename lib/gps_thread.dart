import 'dart:async';
import 'dart:io';

import 'package:gpx/gpx.dart';

import 'logger.dart';
import 'rectangle_calculator.dart';
import 'voice_prompt_events.dart';
import 'config.dart';
import 'thread_base.dart';
import 'overspeed_checker.dart';

/// Simplified port of the GPS handling thread from the Python code base.  The
/// original application relied on OS threads and condition variables to push
/// GPS samples into the calculation pipeline.  In Dart we model this as a
/// [Stream] of [VectorData] objects.  Consumers may listen to [stream] or
/// forward the events to [RectangleCalculatorThread.addVectorSample].
class GpsThread extends Logger {
  GpsThread({
    this.voicePromptEvents,
    double? accuracyThreshold,
    StreamController<Timestamped<Map<String, dynamic>>>?
        speedCamEventController,
    this.overspeedChecker,
  })  : accuracyThreshold = (accuracyThreshold ??
                AppConfig.get<num>('gpsThread.gps_inaccuracy_treshold') ??
                4)
            .toDouble(),
        gpsTestData = AppConfig.get<bool>('gpsThread.gps_test_data') ?? false,
        maxGpsEntries =
            (AppConfig.get<num>('gpsThread.max_gps_entries') ?? 50000).toInt(),
        gpxFile = AppConfig.get<String>('gpsThread.gpx_file') ??
            'python/gpx/Weekend_Karntner_5SeenTour.gpx',
        gpsTreshold =
            (AppConfig.get<num>('gpsThread.gps_treshold') ?? 40).toDouble(),
        recording = AppConfig.get<bool>('gpsThread.recording') ?? false,
        _speedCamEventController = speedCamEventController,
        super('GpsThread');

  final VoicePromptEvents? voicePromptEvents;
  final double accuracyThreshold;
  final bool gpsTestData;
  final int maxGpsEntries;
  final String gpxFile;
  final double gpsTreshold;
  bool recording;
  final List<Wpt> _routeData = [];
  int topSpeed = 0;

  final OverspeedChecker? overspeedChecker;

  final StreamController<Timestamped<Map<String, dynamic>>>?
      _speedCamEventController;

  final StreamController<VectorData> _controller =
      StreamController<VectorData>.broadcast();
  // Stream distributing bearing sets for the deviation checker.
  final StreamController<dynamic> _bearingSetController =
      StreamController<dynamic>.broadcast();

  final StreamController<int> _topSpeedController =
      StreamController<int>.broadcast();

  Stream<int> get topSpeedStream => _topSpeedController.stream;

  StreamSubscription<VectorData>? _sourceSub;
  bool _running = false;
  String? _lastSignal;
  double? _lastBearing;
  final List<double> _currentBearings = <double>[];

  /// Indicates whether the GPS thread is currently running.
  bool get isRunning => _running;

  /// Stream of incoming [VectorData] samples.
  Stream<VectorData> get stream => _controller.stream;

  /// Stream of bearing sets that should be forwarded to the deviation checker
  /// thread. Each event is either a [List<double>] containing five bearing
  /// values or a numeric control value mirroring the behaviour of the Python
  /// ``average_angle_queue``.
  Stream<dynamic> get bearingSets => _bearingSetController.stream;

  /// Plain position updates which other components (e.g. the speed cam warner)
  /// may listen to. Uses the same underlying stream as [stream].
  Stream<VectorData> get positionUpdates => _controller.stream;

  /// Start emitting samples.  If a [source] stream is provided its events are
  /// forwarded to listeners.  Otherwise samples can be pushed manually via
  /// [addSample].
  void start({Stream<VectorData>? source}) {
    if (_running) return;
    _running = true;
    printLogLine(
        'GPS thread started testData=$gpsTestData maxEntries=$maxGpsEntries recording=$recording threshold=$gpsTreshold');
    if (voicePromptEvents != null && _lastSignal != 'GPS_ON') {
      voicePromptEvents!.emit('GPS_ON');
      _lastSignal = 'GPS_ON';
    }
    _sourceSub = source?.listen((event) {
      if (_running) {
        printLogLine(
            'Forwarding vector ${event.latitude}, ${event.longitude}, speed ${event.speed}');
        _handleSample(event);
      }
    });
  }

  /// Push a single [VectorData] sample into the GPS stream.
  void addSample(VectorData vector) {
    if (_running) {
      printLogLine(
          'Manually added sample ${vector.latitude}, ${vector.longitude}, speed ${vector.speed}');
      _handleSample(vector);
    }
  }

  /// Stop emitting samples but keep the stream open for a possible restart.
  Future<void> stop() async {
    _running = false;
    printLogLine('GPS thread stopping');
    await _sourceSub?.cancel();
    _sourceSub = null;
    if (voicePromptEvents != null && _lastSignal != 'GPS_OFF') {
      voicePromptEvents!.emit('GPS_OFF');
      _lastSignal = 'GPS_OFF';
    }
    voicePromptEvents?.emit('EXIT_APPLICATION');
  }

  /// Permanently dispose the underlying stream controller.
  Future<void> dispose() async {
    await _sourceSub?.cancel();
    await _controller.close();
    await _bearingSetController.close();
  }

  void startRecording() {
    recording = true;
    _routeData.clear();
    printLogLine('Route recording started');
  }

  Future<void> stopRecording([String path = 'gpx/route_data.gpx']) async {
    recording = false;
    await _saveRouteData(path);
    printLogLine('Route recording stopped');
  }

  Future<void> _saveRouteData(String path) async {
    if (_routeData.isEmpty) {
      printLogLine('No route data to save', logLevel: 'WARNING');
      return;
    }
    final gpx = Gpx();
    final trkseg = Trkseg(trkpts: List<Wpt>.from(_routeData));
    final trk = Trk(trksegs: [trkseg]);
    gpx.trks.add(trk);
    final file = File(path);
    await file.create(recursive: true);
    final xml = GpxWriter().asString(gpx, pretty: true);
    await file.writeAsString(xml);
    printLogLine('Route data saved to GPX file');
  }

  void _handleSample(VectorData vector) {
    if (vector.speed > 0) {
      final direction = _calculateDirection(vector.bearing);
      final enriched = VectorData(
        longitude: vector.longitude,
        latitude: vector.latitude,
        speed: vector.speed,
        bearing: vector.bearing,
        direction: direction ?? '',
        gpsStatus:
            vector.accuracy > accuracyThreshold ? 'WEAK' : vector.gpsStatus,
        accuracy: vector.accuracy,
      );

      if (enriched.speed.toInt() > topSpeed) {
        topSpeed = enriched.speed.toInt();
        _topSpeedController.add(topSpeed);
      }
      _controller.add(enriched);
      _speedCamEventController?.add(
        Timestamped<Map<String, dynamic>>({
          'bearing': enriched.bearing,
          'stable_ccp': null,
          'ccp': [enriched.longitude, enriched.latitude],
          'fix_cam': [false, 0.0, 0.0, false],
          'traffic_cam': [false, 0.0, 0.0, false],
          'distance_cam': [false, 0.0, 0.0, false],
          'mobile_cam': [false, 0.0, 0.0, false],
          'ccp_node': [null, null],
          'list_tree': [null, null],
        }),
      );
      _produceBearingSet(enriched.bearing);
      if (recording) {
        _routeData.add(Wpt(
          lat: enriched.latitude,
          lon: enriched.longitude,
          time: DateTime.now(),
          extensions: {'speed': enriched.speed},
        ));
      }
    }

    if (voicePromptEvents != null) {
      String signal;
      if (vector.gpsStatus != 'ONLINE') {
        signal = 'GPS_OFF';
      } else if (vector.accuracy > accuracyThreshold) {
        signal = 'GPS_LOW';
      } else {
        signal = 'GPS_ON';
      }
      if (signal != _lastSignal) {
        voicePromptEvents!.emit(signal);
        _lastSignal = signal;
      }
    }
  }

  String? _calculateDirection(double bearing) {
    String? direction;
    final b = double.tryParse('$bearing');
    if (b == null) return null;

    if (0 <= b && b <= 11) {
      direction = 'TOP-N';
      _lastBearing = b;
    } else if (11 < b && b < 22) {
      direction = 'N';
      _lastBearing = b;
    } else if (22 <= b && b < 45) {
      direction = 'NNO';
      _lastBearing = b;
    } else if (45 <= b && b < 67) {
      direction = 'NO';
      _lastBearing = b;
    } else if (67 <= b && b < 78) {
      direction = 'ONO';
      _lastBearing = b;
    } else if (78 <= b && b <= 101) {
      direction = 'TOP-O';
      _lastBearing = b;
    } else if (101 < b && b < 112) {
      direction = 'O';
      _lastBearing = b;
    } else if (112 <= b && b < 135) {
      direction = 'OSO';
      _lastBearing = b;
    } else if (135 <= b && b < 157) {
      direction = 'SO';
      _lastBearing = b;
    } else if (157 <= b && b < 168) {
      direction = 'SSO';
    } else if (168 <= b && b < 191) {
      direction = 'TOP-S';
      _lastBearing = b;
    } else if (191 <= b && b < 202) {
      direction = 'S';
      _lastBearing = b;
    } else if (202 <= b && b < 225) {
      direction = 'SSW';
      _lastBearing = b;
    } else if (225 <= b && b < 247) {
      direction = 'SW';
      _lastBearing = b;
    } else if (247 <= b && b < 258) {
      direction = 'WSW';
      _lastBearing = b;
    } else if (258 <= b && b < 281) {
      direction = 'TOP-W';
    } else if (281 <= b && b < 292) {
      direction = 'W';
      _lastBearing = b;
    } else if (292 <= b && b < 315) {
      direction = 'WNW';
      _lastBearing = b;
    } else if (315 <= b && b < 337) {
      direction = 'NW';
      _lastBearing = b;
    } else if (337 <= b && b < 348) {
      direction = 'NNW';
      _lastBearing = b;
    } else if (348 <= b && b < 355) {
      direction = 'N';
      _lastBearing = b;
    } else if (355 <= b && b <= 360) {
      direction = 'TOP-N';
      _lastBearing = b;
    } else {
      direction = _calculateBearingDeviation(b, _lastBearing);
    }
    return direction;
  }

  String _calculateBearingDeviation(double current, double? last) {
    if (last != null) {
      if (current >= last) {
        final deviation = ((current - last) / last) * 100;
        return deviation > 20 ? 'ONO' : 'NO';
      } else {
        final deviation = ((current - last).abs() / last) * 100;
        return deviation > 20 ? 'NO' : 'ONO';
      }
    }
    return 'NO';
  }

  void _produceBearingSet(double bearing) {
    if (bearing == 0.002 || bearing == 0.001 || bearing == 0.0) {
      _bearingSetController.add(bearing);
      return;
    }
    if (_currentBearings.length == 5) {
      _bearingSetController.add(List<double>.from(_currentBearings));
      _currentBearings.clear();
      return;
    }
    _currentBearings.add(bearing);
  }
}
