import 'dart:async';

import 'package:flutter/foundation.dart';

import 'gps_thread.dart';
import 'location_manager.dart';
import 'rectangle_calculator.dart';
import 'package:geolocator/geolocator.dart';
import 'overspeed_thread.dart';
import 'speed_cam_warner.dart';
import 'deviation_checker.dart';
import 'voice_prompt_thread.dart';
import 'voice_prompt_queue.dart';
import 'poi_reader.dart';
import 'thread_base.dart' as tb;
import 'osm_wrapper.dart';
import 'osm_thread.dart';

/// Central place that wires up background modules and manages their
/// lifecycles.  The original Python project spawned numerous threads; in
/// Dart we keep long lived objects and expose explicit [start] and [stop]
/// hooks so the Flutter UI can control them.
class AppController {
  AppController();

  /// Handles GPS sampling.
  final GpsThread gps = GpsThread();

  /// Provides real position updates using the device's sensors.
  final LocationManager locationManager = LocationManager();

  /// Performs rectangle calculations and camera lookups.
  final RectangleCalculatorThread calculator = RectangleCalculatorThread();

  /// Publishes the latest AR detection status so UI widgets can react.
  final ValueNotifier<String> arStatusNotifier =
      ValueNotifier<String>('Idle');

  /// Difference between current speed and the allowed maximum. `null` means
  /// the driver is within the legal limit.
  final ValueNotifier<int?> overspeedNotifier = ValueNotifier<int?>(null);

  bool _running = false;
  StreamSubscription<VectorData>? _gpsSub;
  StreamSubscription<VectorData>? _speedSub;
  OverspeedThread? _overspeed;
  VoidCallback? _maxSpeedListener;

  // Additional background modules and their communication primitives.
  final VoicePromptQueue voicePromptQueue = VoicePromptQueue();
  VoicePromptThread? _voiceThread;
  final tb.SpeedCamQueue<Map<String, dynamic>> speedCamQueue =
      tb.SpeedCamQueue<Map<String, dynamic>>();
  final tb.OverspeedQueue<Map<String, dynamic>> overspeedQueue =
      tb.OverspeedQueue<Map<String, dynamic>>();
  final tb.MapQueue<dynamic> mapQueue = tb.MapQueue<dynamic>();
  final Maps osmWrapper = Maps();
  final tb.ThreadCondition cvSpeedcam = tb.ThreadCondition(false);
  final tb.ThreadCondition cvOverspeed = tb.ThreadCondition(false);
  final tb.ThreadCondition cvMap = tb.ThreadCondition(false);
  final tb.ThreadCondition cvMapCloud = tb.ThreadCondition(false);
  final tb.ThreadCondition cvMapDb = tb.ThreadCondition(false);
  SpeedCamWarner? _speedCamWarner;
  DeviationCheckerThread? _deviationChecker;
  POIReader? _poiReader;
  OsmThread? _osmThread;

  bool get overspeedThreadRunning => _overspeed?.isRunning ?? false;

  /// Start background services if not already running.
  ///
  /// When [gpxFile] is provided the GPS module will replay coordinates from
  /// that GPX track instead of querying the device's sensors. Tests may supply
  /// a custom [positionStream] to avoid interacting with the real platform
  /// services.
  Future<void> start({String? gpxFile, Stream<Position>? positionStream}) async {
    if (_running) return;
    await locationManager.start(
        gpxFile: gpxFile, positionStream: positionStream);
    gps.start(source: locationManager.stream);
    _gpsSub = gps.stream.listen(calculator.addVectorSample);
    calculator.run();

    // Start overspeed checker which consumes current speed and max speed
    // updates from the calculator.
    final layout = _NotifierSpeedLayout(overspeedNotifier);
    _overspeed = OverspeedThread(
      cond: ThreadCondition(),
      isResumed: () => _running,
      speedLayout: layout,
    );
    unawaited(_overspeed!.run());
    _speedSub = gps.stream.listen((v) {
      _overspeed?.addCurrentSpeed(v.speed.round());
    });
    _maxSpeedListener = () {
      final max = calculator.maxspeed;
      if (max != null) {
        _overspeed?.addOverspeedEntry({'maxspeed': max});
      }
    };
    calculator.maxspeedNotifier.addListener(_maxSpeedListener!);
    _maxSpeedListener!();

    // Voice prompts for acoustic feedback.
    _voiceThread = VoicePromptThread(
      voicePromptQueue: voicePromptQueue,
      dialogflowClient: _DummyDialogflowClient(),
      isResumed: () => _running,
    );
    unawaited(_voiceThread!.run());

    // Deviation checker monitors bearing stability.
    _deviationChecker = DeviationCheckerThread(
      cond: ThreadCondition(),
      condAr: ThreadCondition(),
      avBearingValue: ValueNotifier<String>('0'),
    );
    _deviationChecker!.start();

    // OSM thread placeholder handling map updates.
    _osmThread = OsmThread(cond: tb.ThreadCondition(false));
    unawaited(_osmThread!.run());

    // Speed camera warner and POI reader for camera alerts.
    final resume = _ResumeAdapter(() => _running);
    _speedCamWarner = SpeedCamWarner(
      mainApp: _MainAppStub(),
      resume: resume,
      cvSpeedcam: cvSpeedcam,
      voicePromptQueue: voicePromptQueue,
      speedcamQueue: speedCamQueue,
      cvOverspeed: cvOverspeed,
      overspeedQueue: overspeedQueue,
      osmWrapper: osmWrapper,
      calculator: calculator,
      cond: tb.ThreadCondition(false),
    );
    unawaited(_speedCamWarner!.run());

    _poiReader = POIReader(
      cvSpeedcam,
      speedCamQueue,
      gps,
      calculator,
      osmWrapper,
      mapQueue,
      cvMap,
      cvMapCloud,
      cvMapDb,
      null,
    );
    _running = true;
  }

  /// Stop all background services and clean up resources.
  Future<void> stop() async {
    if (!_running) return;
    await gps.stop();
    await locationManager.stop();
    await _gpsSub?.cancel();
    _gpsSub = null;
    await _speedSub?.cancel();
    _speedSub = null;
    if (_maxSpeedListener != null) {
      calculator.maxspeedNotifier.removeListener(_maxSpeedListener!);
      _maxSpeedListener = null;
    }
    await _overspeed?.stop();
    _overspeed = null;
    await _voiceThread?.stop();
    _voiceThread = null;
    await _speedCamWarner?.stop();
    _speedCamWarner = null;
    _deviationChecker?.stop();
    _deviationChecker = null;
    _poiReader?.stop();
    _poiReader = null;
    await _osmThread?.stop();
    _osmThread = null;
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

/// Simple adapter that forwards overspeed updates from [OverspeedThread] to a
/// [ValueNotifier].
class _NotifierSpeedLayout implements SpeedLayout {
  final ValueNotifier<int?> notifier;
  _NotifierSpeedLayout(this.notifier);

  @override
  void resetOverspeed() => notifier.value = null;

  @override
  void updateOverspeed(int value) => notifier.value = value;
}

/// Simple wrapper exposing an `isResumed` callback to legacy threads.
class _ResumeAdapter {
  final bool Function() _check;
  _ResumeAdapter(this._check);
  bool isResumed() => _check();
}

/// Minimal stub emulating properties accessed by legacy threads.
class _MainAppStub {
  bool runInBackGround = false;
  final _DummyEvent mainEvent = _DummyEvent();
}

class _DummyEvent {
  Future<void> wait() async {}
}

class _DummyDialogflowClient {
  Future<String> detectIntent(String text) async => text;
}
