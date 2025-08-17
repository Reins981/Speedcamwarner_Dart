import 'package:flutter/foundation.dart';

import 'dart:async';
import 'package:path/path.dart' as p;
import 'gps_thread.dart';
import 'location_manager.dart';
import 'rectangle_calculator.dart';
import 'voice_prompt_events.dart';
import 'package:geolocator/geolocator.dart';
import 'poi_reader.dart';
import 'gps_producer.dart';
import 'speed_cam_warner.dart';
import 'voice_prompt_thread.dart';
import 'overspeed_thread.dart' as overspeed;
import 'config.dart';
import 'thread_base.dart';
import 'dialogflow_client.dart';
import 'dart:io';
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
    overspeedThread = overspeed.OverspeedThread(
      cond: overspeed.ThreadCondition(),
      isResumed: () => true,
    );
    unawaited(overspeedThread.run());

    calculator = RectangleCalculatorThread(
      voicePromptEvents: voicePromptEvents,
      interruptQueue: interruptQueue,
      overspeedThread: overspeedThread,
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

    final dialogflow = () {
      try {
        final relPath =
            p.join('service_account', 'osmwarner-01bcd4dc2dd3.json');
        final credentialsPath =
            Platform.environment['DIALOGFLOW_CREDENTIALS'] ??
                File(relPath).absolute.path;
        return DialogflowClient.fromServiceAccountFile(
          jsonPath: credentialsPath,
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
          (AppConfig.get<String>('accusticWarner.voice_prompt_source') ??
                  'dialogflow') ==
              'dialogflow',
    );
    unawaited(voiceThread.run());

    // Start the deviation checker by default so it can be paused during AR
    // sessions and restarted afterwards.
    startDeviationCheckerThread();
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

  /// Calculates overspeed warnings based on current and maximum speeds.
  late final overspeed.OverspeedThread overspeedThread;

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
    await overspeedThread.stop();
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
  void startDeviationCheckerThread() {
    if (_deviationRunning) return;
    _deviationCond = deviation.ThreadCondition();
    _deviationCondAr = deviation.ThreadCondition();
    deviationChecker = deviation.DeviationCheckerThread(
      cond: _deviationCond!,
      condAr: _deviationCondAr!,
      avBearingValue: averageBearingValue,
    );
    deviationChecker.start();
    _deviationRunning = true;
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
}

class _AlwaysResume {
  bool isResumed() => true;
}
