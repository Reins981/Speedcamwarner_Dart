import 'package:flutter/foundation.dart';
import 'dart:async';
import 'gps_thread.dart';
import 'location_manager.dart';
import 'rectangle_calculator.dart';
import 'dart:math' as math;
import 'voice_prompt_events.dart';
import 'package:geolocator/geolocator.dart';
import 'poi_reader.dart';
import 'gps_producer.dart';
import 'speed_cam_warner.dart';
import 'voice_prompt_thread.dart';
import 'overspeed_checker.dart';
import 'config.dart';
import 'thread_base.dart';
import 'dialogflow_client.dart';
import 'osm_wrapper.dart';
import 'osm_thread.dart';
import 'deviation_checker.dart' as deviation;

/// Central place that wires up background modules and manages their
/// lifecycles.  The original Python project spawned numerous threads; in
/// Dart we keep long lived objects and expose explicit [start] and [stop]
/// hooks so the Flutter UI can control them.
class AppController {
  AppController()
      : voicePromptEvents = VoicePromptEvents(),
        locationManager = LocationManager() {
    overspeedChecker = OverspeedChecker();

    // Start the deviation checker by default so it can be paused during AR
    // sessions and restarted afterwards.
    deviationChecker = startDeviationCheckerThread();

    calculator = RectangleCalculatorThread(
      voicePromptEvents: voicePromptEvents,
      overspeedChecker: overspeedChecker,
      deviationCheckerThread: deviationChecker,
    );
    gps = GpsThread(
      voicePromptEvents: voicePromptEvents,
      speedCamEventController: calculator.speedCamEventController,
    );
    // Pipe GPS samples into the calculator and GPS producer and expose
    // direction updates to the UI and other threads. Position updates are
    // forwarded to the shared speed camera event controller so the
    // speed cam warner can react to every GPS sample.
    gps.stream.listen((vector) {
      calculator.addVectorSample(vector);
      gpsProducer.update(vector);
      directionNotifier.value = vector.direction;
    });

    // Forward bearing sets to the deviation checker.
    gps.bearingSets.listen((data) {
      averageAngleQueue.produce(data);
      deviationChecker.addAverageAngleData(data);
    });

    osmWrapper = Maps();
    osmWrapper.setConfigs();
    osmWrapper.setCalculatorThread(calculator);
    osmThread = OsmThread(
      osmWrapper: osmWrapper,
      mapQueue: mapQueue,
    );
    unawaited(osmThread.run());

    poiReader = POIReader(
      gpsProducer,
      calculator,
      mapQueue,
      voicePromptEvents,
      null,
    );
    camWarner = SpeedCamWarner(
      resume: _AlwaysResume(),
      voicePromptEvents: voicePromptEvents,
      osmWrapper: osmWrapper,
      calculator: calculator,
    );
    unawaited(camWarner.run());

    final dialogflow = () async {
      try {
        return DialogflowClient.fromServiceAccountFile(
          jsonPath: "assets/service_account/osmwarner-01bcd4dc2dd3.json",
        );
      } catch (e) {
        // ignore: avoid_print
        print('Dialogflow initialisation failed: $e');
        return FallbackDialogflowClient();
      }
    }();

    voiceThread = VoicePromptThread(
      voicePromptEvents: voicePromptEvents,
      dialogflowClient: dialogflow,
      aiVoicePrompts:
          (AppConfig.get<dynamic>('accusticWarner.voice_prompt_source') ??
                  'dialogflow') ==
              'dialogflow',
    );
    unawaited(voiceThread.run());
  }

  /// Handles GPS sampling.
  late final GpsThread gps;

  /// Provides real position updates using the device's sensors.
  final LocationManager locationManager;

  /// Shared event bus for delivering voice prompt entries.
  final VoicePromptEvents voicePromptEvents;

  /// Performs rectangle calculations and camera lookups.
  late final RectangleCalculatorThread calculator;

  /// Handles camera approach warnings and UI updates.
  late final SpeedCamWarner camWarner;

  /// Plays alert sounds for spoken and acoustic warnings.
  late final VoicePromptThread voiceThread;

  /// Publishes the current overspeed difference to the UI.
  late final OverspeedChecker overspeedChecker;

  /// Calculates deviation of the current course based on recent bearings.
  late deviation.DeviationCheckerThread deviationChecker;

  /// Shared queue holding the last bearings for the deviation checker.
  final AverageAngleQueue<List<double>> averageAngleQueue =
      AverageAngleQueue<List<double>>();

  /// Coordinates thread termination for the deviation checker.
  deviation.ThreadCondition? _deviationCond;
  deviation.ThreadCondition? _deviationCondAr;

  /// Publishes the current average bearing to the UI.
  final ValueNotifier<String> averageBearingValue =
      ValueNotifier<String>('---.-°');

  /// Publishes the current driving direction to the dashboard.
  final ValueNotifier<String> directionNotifier = ValueNotifier<String>('-');

  /// Supplies direction and coordinates for POI queries.
  final GpsProducer gpsProducer = GpsProducer();

  /// Stream distributing POI lookup results to listeners such as the map.
  final StreamController<List<List<dynamic>>> _poiController =
      StreamController<List<List<dynamic>>>.broadcast();

  /// Public stream of POI coordinate lists.
  Stream<List<List<dynamic>>> get poiStream => _poiController.stream;

  // Interrupt queue for handling real-time interruptions.
  final InterruptQueue<String>? interruptQueue = InterruptQueue<String>();

  /// Queue distributing map updates.
  final MapQueue<dynamic> mapQueue = MapQueue<dynamic>();

  /// Wrapper around OpenStreetMap related interactions.
  late final Maps osmWrapper;

  /// Thread consuming map update events.
  late final OsmThread osmThread;

  /// Loads POIs from the database and cloud.
  late final POIReader poiReader;

  /// Publishes the latest AR detection status so UI widgets can react.
  final ValueNotifier<String> arStatusNotifier = ValueNotifier<String>('Idle');

  /// Tracks whether the deviation checker is currently active.
  bool _deviationRunning = false;

  /// Tracks whether a route to a POI is being monitored.
  bool _routeMonitoring = false;
  Future<void>? _routeMonitorTask;

  bool _running = false;

  /// Start background services if not already running.
  ///
  /// When [gpxFile] is provided the GPS module will replay coordinates from
  /// that GPX track instead of querying the device's sensors. Tests may supply
  /// a custom [positionStream] to avoid interacting with the real platform
  /// services.
  Future<void> start({
    String? gpxFile,
    Stream<Position>? positionStream,
  }) async {
    if (_running) return;
    await locationManager.start(
      gpxFile: gpxFile,
      positionStream: positionStream,
    );
    gps.start(source: locationManager.stream);
    calculator.run();
    deviationChecker.start();
    _running = true;
  }

  /// Stop all background services and clean up resources.
  Future<void> stop() async {
    if (!_running) return;
    voicePromptEvents.emit('STOP_APPLICATION');
    await gps.stop();
    await locationManager.stop();
    calculator.stop();
    poiReader.stopTimer();
    await voiceThread.stop();
    stopDeviationCheckerThread();
    stopRouteMonitoring();
    await osmThread.stop();
    deviationChecker.terminate();
    averageAngleQueue.clearAverageAngleData();
    _running = false;
  }

  /// Fully dispose all resources.  Subsequent calls to [start] will require a
  /// new [AppController] instance.
  Future<void> dispose() async {
    await stop();
    voicePromptEvents.emit('EXIT_APPLICATION');
    await gps.dispose();
    await locationManager.dispose();
    await calculator.dispose();
    poiReader.stopTimer();
    await voiceThread.stop();
    stopDeviationCheckerThread();
    await _poiController.close();
  }

  /// Start monitoring the distance to [poi] and emit `POI_REACHED` once the
  /// device is within 50 meters.
  Future<void> prepareRoute(List<double> poi) async {
    if (_routeMonitoring) return;
    _routeMonitoring = true;
    _routeMonitorTask = _monitorRoute(poi);
  }

  Future<void> _monitorRoute(List<double> poi) async {
    while (_routeMonitoring) {
      await Future.delayed(const Duration(seconds: 2));
      final coords = gpsProducer.get_lon_lat();
      final distance = camWarner.checkDistanceBetweenTwoPoints(poi, coords);
      if (distance <= 50) {
        voicePromptEvents.emit('POI_REACHED');
        _routeMonitoring = false;
        break;
      }
    }
  }

  /// Stop monitoring the current route if active.
  void stopRouteMonitoring() {
    if (_routeMonitoring) {
      _routeMonitoring = false;
      voicePromptEvents.emit('ROUTE_STOPPED');
    }
  }

  /// Emit a `NO_ROUTE` voice prompt when a route could not be calculated.
  void notifyNoRoute() {
    voicePromptEvents.emit('NO_ROUTE');
  }

  /// Begin recording GPS samples to a GPX file.
  void startRecording() {
    gps.startRecording();
  }

  /// Stop recording and persist the collected route data.
  Future<void> stopRecording() => gps.stopRecording();

  /// Replay a previously recorded route from [path].
  Future<void> loadRoute([String path = 'gpx/route_data.gpx']) async {
    await locationManager.stop();
    await gps.stop();
    await locationManager.start(gpxFile: path);
    gps.start(source: locationManager.stream);
  }

  /// Start the [DeviationCheckerThread] if it isn't already running.
  deviation.DeviationCheckerThread startDeviationCheckerThread() {
    if (_deviationRunning) return deviationChecker;
    _deviationCond = deviation.ThreadCondition();
    _deviationCondAr = deviation.ThreadCondition();
    deviationChecker = deviation.DeviationCheckerThread(
      cond: _deviationCond!,
      condAr: _deviationCondAr!,
      avBearingValue: averageBearingValue,
    );
    deviationChecker.start();
    _deviationRunning = true;

    return deviationChecker;
  }

  /// Stop the [DeviationCheckerThread] if currently active.
  void stopDeviationCheckerThread() {
    if (!_deviationRunning) return;
    _deviationCondAr?.terminate = true;
    deviationChecker.addAverageAngleData('TERMINATE');
    _deviationRunning = false;
    deviationChecker.terminate();
    averageAngleQueue.clearAverageAngleData();
  }

  /// Trigger a POI lookup around the current position for the given [type].
  Future<void> lookupPois(String type) async {
    final coords = gpsProducer.get_lon_lat();
    final lon = coords[0];
    final lat = coords[1];
    if ((lon == 0 && lat == 0) || lon.isNaN || lat.isNaN) {
      voicePromptEvents.emit('POI_FAILED');
      return;
    }

    final tiles = calculator.longlat2tile(lat, lon, calculator.zoom);
    final xtile = tiles[0];
    final ytile = tiles[1];

    final poiDistance =
        (AppConfig.get<num>('main.poi_distance') ?? 50).toDouble();
    final kmPerTile = (40075.016686 * math.cos(lat * math.pi / 180.0)) /
        math.pow(2, calculator.zoom);
    final tileDistance = poiDistance / kmPerTile;

    final pts = calculator.calculatePoints2Angle(
      xtile,
      ytile,
      tileDistance,
      calculator.currentRectAngle * math.pi / 180.0,
    );
    final poly = calculator.createGeoJsonTilePolygonAngle(
      calculator.zoom,
      pts[0],
      pts[2],
      pts[1],
      pts[3],
    );
    final lonMin = math.min(poly[0].x, poly[2].x);
    final lonMax = math.max(poly[0].x, poly[2].x);
    final latMin = math.min(poly[0].y, poly[2].y);
    final latMax = math.max(poly[0].y, poly[2].y);
    final area = GeoRect(
      minLat: latMin,
      minLon: lonMin,
      maxLat: latMax,
      maxLon: lonMax,
    );

    final result = await calculator.triggerOsmLookup(area, lookupType: type);
    if (result.success && result.elements != null) {
      final pois = <List<dynamic>>[];
      for (final el in result.elements!) {
        final latPoi = (el['lat'] as num?)?.toDouble();
        final lonPoi = (el['lon'] as num?)?.toDouble();
        if (latPoi != null && lonPoi != null) {
          String amenity = '';
          String address = '';
          String postCode = '';
          String street = '';
          String name = '';
          String phone = '';
          if (el['tags'] != null) {
            final tags = el['tags'] as Map;
            if (tags['amenity'] != null) {
              amenity = tags['amenity'].toString();
            }
            if (tags['addr:city'] != null) {
              address = tags['addr:city'].toString();
            }
            if (tags['addr:postcode'] != null) {
              postCode = tags['addr:postcode'].toString();
            }
            if (tags['addr:street'] != null) {
              street = tags['addr:street'].toString();
            }
            if (tags['name'] != null) {
              name = tags['name'].toString();
            }
            if (tags['phone'] != null) {
              phone = tags['phone'].toString();
            }
          }
          pois.add([
            latPoi,
            lonPoi,
            amenity,
            address,
            postCode,
            street,
            name,
            phone
          ]);
        }
      }
      _poiController.add(pois);
      calculator.updatePoiCount(pois.length);
      if (pois.isNotEmpty) {
        voicePromptEvents.emit('POI_SUCCESS');
      } else {
        voicePromptEvents.emit('POI_FAILED');
      }
    } else {
      _poiController.add([]);
      calculator.updatePoiCount(0);
      voicePromptEvents.emit('POI_FAILED');
    }
  }
}

class _AlwaysResume {
  bool isResumed() => true;
}
