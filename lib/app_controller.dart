import 'package:flutter/foundation.dart';

import 'dart:async';

import 'gps_thread.dart';
import 'location_manager.dart';
import 'rectangle_calculator.dart';
import 'voice_prompt_queue.dart';
import 'package:geolocator/geolocator.dart';
import 'poi_reader.dart';
import 'gps_producer.dart';
import 'speed_cam_warner.dart';
import 'voice_prompt_thread.dart';
import 'overspeed_thread.dart' as overspeed;
import 'overspeed_checker.dart';
import 'config.dart';
import 'thread_base.dart';
import 'osm_wrapper.dart';
import 'osm_thread.dart';
import 'deviation_checker.dart' as deviation;

/// Central place that wires up background modules and manages their
/// lifecycles.  The original Python project spawned numerous threads; in
/// Dart we keep long lived objects and expose explicit [start] and [stop]
/// hooks so the Flutter UI can control them.
class AppController {
  AppController()
      : voicePromptQueue = VoicePromptQueue(),
        locationManager = LocationManager() {
    gps = GpsThread(voicePromptQueue: voicePromptQueue);
    overspeedChecker = OverspeedChecker();
    overspeedThread = overspeed.OverspeedThread(
      cond: overspeed.ThreadCondition(),
      isResumed: () => true,
      speedLayout: _OverspeedLayout(overspeedChecker),
    );
    unawaited(overspeedThread.run());

    calculator = RectangleCalculatorThread(
      voicePromptQueue: voicePromptQueue,
      speedCamQueue: speedCamQueue,
      overspeedChecker: overspeedChecker,
      overspeedThread: overspeedThread,
    );
    // Pipe GPS samples into the calculator and GPS producer.
    gps.stream.listen((vector) {
      calculator.addVectorSample(vector);
      gpsProducer.update(vector);
      _bearingBuffer.add(vector.bearing);
      if (_bearingBuffer.length == 5) {
        final data = List<double>.from(_bearingBuffer);
        averageAngleQueue.produce(data);
        deviationChecker.addAverageAngleData(data);
        _bearingBuffer.clear();
      }
    });

    osmWrapper = Maps();
    osmWrapper.setCalculatorThread(calculator);
    osmThread = OsmThread(
      osmWrapper: osmWrapper,
      mapQueue: mapQueue,
    );
    unawaited(osmThread.run());

    poiReader = POIReader(
      speedCamQueue,
      gpsProducer,
      calculator,
      mapQueue,
      null,
    );
    camWarner = SpeedCamWarner(
      resume: _AlwaysResume(),
      voicePromptQueue: voicePromptQueue,
      speedcamQueue: speedCamQueue,
      osmWrapper: osmWrapper,
      calculator: calculator,
    );
    unawaited(camWarner.run());

    voiceThread = VoicePromptThread(
      voicePromptQueue: voicePromptQueue,
      dialogflowClient: _DummyDialogflowClient(),
      aiVoicePrompts:
          AppConfig.get<bool>('accusticWarner.ai_voice_prompts') ?? false,
    );
    unawaited(voiceThread.run());

    deviationChecker = deviation.DeviationCheckerThread(
      cond: _deviationCond,
      condAr: _deviationCondAr,
      avBearingValue: averageBearingValue,
    );
  }

  /// Handles GPS sampling.
  late final GpsThread gps;

  /// Provides real position updates using the device's sensors.
  final LocationManager locationManager;

  /// Shared queue for delivering voice prompt entries.
  final VoicePromptQueue voicePromptQueue;

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
  late final deviation.DeviationCheckerThread deviationChecker;

  /// Shared queue holding the last bearings for the deviation checker.
  final AverageAngleQueue<List<double>> averageAngleQueue =
      AverageAngleQueue<List<double>>();

  final deviation.ThreadCondition _deviationCond = deviation.ThreadCondition();
  final deviation.ThreadCondition _deviationCondAr = deviation.ThreadCondition();

  final ValueNotifier<String> averageBearingValue =
      ValueNotifier<String>('---.-°');

  final List<double> _bearingBuffer = <double>[];

  /// Supplies direction and coordinates for POI queries.
  final GpsProducer gpsProducer = GpsProducer();

  /// Queue delivering speed camera updates to interested consumers.
  final SpeedCamQueue<Map<String, dynamic>> speedCamQueue =
      SpeedCamQueue<Map<String, dynamic>>();

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
    camWarner.cond.setTerminateState(true);
    voiceThread.stop();
    await overspeedThread.stop();
    await osmThread.stop();
    deviationChecker.terminate();
    averageAngleQueue.clearAverageAngleData();
    _bearingBuffer.clear();
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
    camWarner.cond.setTerminateState(true);
    voiceThread.stop();
    deviationChecker.terminate();
    averageAngleQueue.clearAverageAngleData();
    _bearingBuffer.clear();
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

class _DummyDialogflowClient {
  Future<String> detectIntent(String text) async => '';
}
