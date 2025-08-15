import 'package:flutter/foundation.dart';

import 'dart:async';

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
import 'overspeed_checker.dart';
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
    gps = GpsThread(voicePromptEvents: voicePromptEvents);
    overspeedChecker = OverspeedChecker();
    overspeedThread = overspeed.OverspeedThread(
      cond: overspeed.ThreadCondition(),
      isResumed: () => true,
      speedLayout: _OverspeedLayout(overspeedChecker),
    );
    unawaited(overspeedThread.run());

    calculator = RectangleCalculatorThread(
      voicePromptEvents: voicePromptEvents,
      interruptQueue: interruptQueue,
      overspeedChecker: overspeedChecker,
      overspeedThread: overspeedThread,
    );
    // Pipe GPS samples into the calculator and GPS producer and expose
    // direction updates to the UI and other threads. Position updates are
    // forwarded to the speed camera warner so it can react to every GPS
    // sample.
    gps.stream.listen((vector) {
      calculator.addVectorSample(vector);
      gpsProducer.update(vector);
      directionNotifier.value = vector.direction;
      camWarner.updatePosition(vector);
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
        final projectId = Platform.environment['DIALOGFLOW_PROJECT_ID'];
        final credentialsPath =
            Platform.environment['DIALOGFLOW_CREDENTIALS'] ??
                'service_account/dialogflow_credentials.json';
        if (projectId == null) {
          throw DialogflowException('DIALOGFLOW_PROJECT_ID not set');
        }
        return DialogflowClient.fromServiceAccountFile(
          projectId: projectId,
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
          AppConfig.get<bool>('accusticWarner.ai_voice_prompts') ?? false,
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
  final ValueNotifier<String> directionNotifier =
      ValueNotifier<String>('-');

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
    await gps.stop();
    await locationManager.stop();
    calculator.stop();
    poiReader.stopTimer();
    await voiceThread.stop();
    await overspeedThread.stop();
    stopDeviationCheckerThread();
    await osmThread.stop();
    deviationChecker.terminate();
    averageAngleQueue.clearAverageAngleData();
    _running = false;
  }

  /// Fully dispose all resources.  Subsequent calls to [start] will require a
  /// new [AppController] instance.
  Future<void> dispose() async {
    await stop();
    await gps.dispose();
    await locationManager.dispose();
    await calculator.dispose();
    poiReader.stopTimer();
    await voiceThread.stop();
    stopDeviationCheckerThread();
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

class _OverspeedLayout implements overspeed.SpeedLayout {
  _OverspeedLayout(this.checker);
  final OverspeedChecker checker;

  @override
  void resetOverspeed() {
    checker.difference.value = null;
  }

  @override
  void updateOverspeed(int value) {
    checker.difference.value = value;
  }
}

class _AlwaysResume {
  bool isResumed() => true;
}
