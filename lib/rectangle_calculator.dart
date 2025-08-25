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
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:math' show Point;
import 'package:path/path.dart' as p;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:workspace/deviation_checker.dart';
import 'filtered_road_classes.dart';
import 'most_probable_way.dart';
import 'rect.dart' show Rect;
import 'rect.dart' as rect_utils hide Rect;
import 'overspeed_checker.dart';
import 'thread_pool.dart';
import 'road_resolver.dart';
import 'point.dart';
import 'linked_list_generator.dart';
import 'tree_generator.dart';
import 'voice_prompt_events.dart';
import 'thread_base.dart';
import 'package:http/http.dart' as http;
import 'logger.dart';
import 'service_account.dart';
import 'config.dart';

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
  final dynamic gpsStatus;
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

  /// Maximum distance (in degrees) used by [pointsCloseToBorderLatLon] when
  /// checking if a lat/lon pair lies close to the rectangle boundary.
  final double maxCloseToBorderLatLon = 0.001; // ~111 m
  final double maxCloseToBorderLatLonLookAhead = 0.0007; // ~77 m

  LatLon topLeftLatLon() => LatLon(lat: maxLat, lon: minLon);
  LatLon topRightLatLon() => LatLon(lat: maxLat, lon: maxLon);
  LatLon bottomLeftLatLon() => LatLon(lat: minLat, lon: minLon);
  LatLon bottomRightLatLon() => LatLon(lat: minLat, lon: maxLon);

  @override
  String toString() {
    return 'GeoRect(minLat: $minLat, minLon: $minLon, maxLat: $maxLat, maxLon: $maxLon)';
  }

  /// Check if a geographic point lies inside [rect].
  bool geoPointInRect(double lat, double lon) {
    return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;
  }

  bool pointsCloseToBorderLatLon(
    double lat,
    double lon, {
    bool lookAhead = false,
    String lookAheadMode = 'Speed Camera lookahead',
  }) {
    // Get corners in lat/lon
    final rect = [
      topLeftLatLon(),
      topRightLatLon(),
      bottomLeftLatLon(),
      bottomRightLatLon()
    ];

    final double maxVal =
        lookAhead ? maxCloseToBorderLatLonLookAhead : maxCloseToBorderLatLon;

    double pt1Lat = rect[0].lat;
    double pt1Lon = rect[0].lon;

    for (var i = 1; i <= rect.length; i++) {
      final pt2Lat = rect[i % rect.length].lat;
      final pt2Lon = rect[i % rect.length].lon;

      if ((lat - math.min(pt1Lat, pt2Lat)).abs() <= maxVal ||
          (lat - math.max(pt1Lat, pt2Lat)).abs() <= maxVal ||
          (lon - math.min(pt1Lon, pt2Lon)).abs() <= maxVal ||
          (lon - math.max(pt1Lon, pt2Lon)).abs() <= maxVal) {
        return true;
      }

      pt1Lat = pt2Lat;
      pt1Lon = pt2Lon;
    }

    return false;
  }
}

class LatLon {
  final double lat;
  final double lon;
  LatLon({required this.lat, required this.lon});
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
  final bool distance;
  final bool mobile;
  final bool predictive;
  String name;
  final int? maxspeed;

  SpeedCameraEvent({
    required this.latitude,
    required this.longitude,
    this.fixed = false,
    this.traffic = false,
    this.distance = false,
    this.mobile = false,
    this.predictive = false,
    this.name = '',
    this.maxspeed,
  });

  @override
  String toString() {
    final List<String> flags = [];
    if (fixed) flags.add('fixed');
    if (traffic) flags.add('traffic');
    if (distance) flags.add('distance');
    if (mobile) flags.add('mobile');
    if (predictive) flags.add('predictive');
    final flagStr = flags.isEmpty ? 'none' : flags.join(',');
    return 'Camera(lat: $latitude, lon: $longitude, flags: $flagStr, name: $name)';
  }
}

/// Result object returned by [triggerOsmLookup].  Mirrors the tuple used in the
/// Python implementation where ``success`` indicates if the request succeeded,
/// ``status`` contains an optional error state, ``elements`` carries the raw
/// OSM elements array and ``error`` holds a human readable message.  ``rect``
/// echoes the queried bounding box so callers can correlate responses.
class OsmLookupResult {
  final bool success;
  final String status;
  final List<dynamic>? elements;
  final String? error;
  final GeoRect rect;

  const OsmLookupResult(
    this.success,
    this.status,
    this.elements,
    this.error,
    this.rect,
  );
}

/// Stub representing a trained predictive model.  In the original Python
/// application a ``joblib`` model is loaded from disk and passed into
/// ``predict_speed_camera``.  In a Dart/Flutter environment you would likely
/// use a TensorFlow Lite model or call a remote inference service.  For the
/// purposes of this port the model is treated as an opaque object and the
/// prediction logic is encapsulated in a standalone function.
class PredictiveModel {
  /// Path to the helper Python script that performs inference using the
  /// trained scikit-learn model.  By default the script bundled in the
  /// repository under `python/ai` is used.
  final String scriptPath;

  PredictiveModel({String? scriptPath})
      : scriptPath = scriptPath ??
            p.join(Directory.current.path, 'python', 'ai', 'predict_camera.py');
}

/// Predict whether a speed camera lies ahead of the vehicle by delegating the
/// work to the Python implementation of the predictive model.  The Python
/// helper script loads the ``speed_camera_model.pkl`` file from the
/// ``python/ai`` directory and returns the predicted latitude/longitude as a
/// JSON array.
Future<SpeedCameraEvent?> predictSpeedCamera({
  required PredictiveModel model,
  required double latitude,
  required double longitude,
  required String timeOfDay,
  required String dayOfWeek,
}) async {
  try {
    final result = await Process.run(
      'python',
      [
        model.scriptPath,
        latitude.toString(),
        longitude.toString(),
        timeOfDay,
        dayOfWeek,
      ],
    );
    if (result.exitCode != 0) return null;
    final output = result.stdout.toString().trim();
    final coords = jsonDecode(output);
    if (coords is List && coords.length >= 2) {
      return SpeedCameraEvent(
        latitude: (coords[0] as num).toDouble(),
        longitude: (coords[1] as num).toDouble(),
        predictive: true,
      );
    }
  } catch (e) {
    // Swallow errors and fall through to returning null so that a failure in
    // the external model does not crash the application.
    print('Error occurred while predicting speed camera: $e');
  }
  return null;
}

/// Record a newly detected camera to persistent storage (a JSON file) and
/// optionally upload that file to Google Drive.  In the original application
/// these responsibilities are delegated to the ``ServiceAccount`` module.  The
/// implementation here forwards the request to that module and returns whether
/// the upload succeeded.
Future<(bool, String?)> uploadCameraToDrive({
  required String name,
  required String roadName,
  required double latitude,
  required double longitude,
}) async {
  await ServiceAccount.init();
  final (added, status) = await ServiceAccount.addCameraToJson(
    name,
    roadName,
    latitude,
    longitude,
  );
  if (!added) {
    return (false, status);
  }
  try {
    final client = await ServiceAccount.buildDriveFromCredentials();
    if (client == null) {
      return (false, 'NO_AUTH_CLIENT');
    }
    final res = await ServiceAccount.uploadFileToGoogleDrive(
      ServiceAccount.fileId,
      ServiceAccount.folderId,
      client,
    );
    if (res == 'success') {
      return (true, null);
    } else {
      return (false, res);
    }
  } catch (e) {
    return (false, e.toString());
  }
}

/// The core class that mirrors the behaviour of ``RectangleCalculatorThread`` in
/// the Python project.  It listens for incoming GPS samples on a stream,
/// computes bounding rectangles and (optionally) predictive speed cameras and
/// emits events to registered listeners.  Termination is controlled via the
/// [dispose] method.
class RectangleCalculatorThread {
  final Logger logger = Logger('RectangleCalculatorThread');

  /// Controller through which callers push new vector samples.  Each sample
  /// triggers a call to [processVector] from within the run loop.
  final StreamController<VectorData> _vectorStreamController =
      StreamController<VectorData>();

  /// Controller used to broadcast new rectangle boundaries.  Downstream
  /// subscribers should listen to this stream to redraw maps or update UI.
  final StreamController<GeoRect?> _rectangleStreamController =
      StreamController<GeoRect?>.broadcast();

  /// The most recently computed rectangle in tile coordinate space.  Stored
  /// as a [Rect] object for geometric helper methods such as
  /// [Rect.pointInRect].
  Rect? lastRect;
  Rect? lastRectConstruction;

  /// Geographic representation of [lastRect].
  GeoRect? lastGeoRect;
  GeoRect? lastGeoRectConstruction;

  /// flag to calculate a new rect with will be used as last rect
  var calculateNewRect = true;
  var calculateNewRectConstruction = true;

  /// Controller used to broadcast detected speed camera events.  Multiple
  /// listeners may subscribe and react (e.g. warn the user or annotate a map).
  final StreamController<SpeedCameraEvent> _cameraStreamController =
      StreamController<SpeedCameraEvent>.broadcast();

  /// Stream of legacy speed camera updates in the original map format.
  /// Replaces the old [SpeedCamQueue] mechanism and includes a timestamp for
  /// staleness checks.
  final StreamController<Timestamped<Map<String, dynamic>>>
      _speedCamEventController =
      StreamController<Timestamped<Map<String, dynamic>>>.broadcast();

  /// Controller used to broadcast newly discovered construction areas.
  final StreamController<GeoRect?> _constructionStreamController =
      StreamController<GeoRect?>.broadcast();

  /// The predictive model used by [predictSpeedCamera].
  final PredictiveModel _predictiveModel;

  /// Event bus used to emit voice prompts for camera events and system messages.
  final VoicePromptEvents voicePromptEvents;

  /// Helper that tracks the most probable road based on recent updates.
  final MostProbableWay mostProbableWay;

  /// Whether the run loop should continue executing.  Set to ``false`` to
  /// stop processing samples.
  bool _running = true;
  bool get isRunning => _running;

  /// Guard to ensure the processing loop is only attached once.  The
  /// constructor calls [_start] and some external code may invoke [run]
  /// for API parity.  Without this flag the stream would be listened to
  /// multiple times which throws a ``Bad state: Stream has already been
  /// listened to`` exception.
  bool _loopStarted = false;

  /// Queue that serializes vector processing so a new update waits for the
  /// previous one to finish. This avoids overlapping lookahead work.
  Future<void> _processingQueue = Future.value();

  /// Tracks whether a vector is currently being processed.
  bool _isProcessing = false;

  /// The current zoom level used when converting between tiles and
  /// latitude/longitude.  You may expose this as a public field if your map
  /// layer needs to remain in sync with the calculator.
  int zoom = 17;

  /// Utility responsible for calculating overspeed warnings.
  final OverspeedChecker overspeedChecker;

  final DeviationCheckerThread deviationCheckerThread;

  /// Last road name resolved by [processRoadName].
  String? lastRoadName;

  /// Whether combined tags were found for the last processed road name.
  bool foundCombinedTags = false;

  /// Last max speed value considered by [processMaxSpeed].
  dynamic lastMaxSpeed;

  /// Current tile and geographic position. These values are updated whenever a
  /// new vector sample is processed.
  double xtile = 0.0;
  double ytile = 0.0;
  double longitude = 0.0;
  double latitude = 0.0;

  /// Last observed movement direction.
  String direction = '';

  /// References to the current and previous rectangles as used by the Python
  /// implementation for extrapolation checks.
  Rect matchingRect = Rect(pointList: [0, 0, 0, 0]);
  Rect? previousRect;

  /// Mapping of rectangle identifiers to their generators. Each entry mirrors
  /// ``RECT_ATTRIBUTES`` in the original code and stores
  /// ``[rect, linkedListGenerator, treeGenerator]``.
  final Map<String, List<dynamic>> rectAttributes = {};

  /// ---------------------------------------------------------------------
  /// Caching and state management helpers

  final List<SpeedCameraEvent> _cameraCache = [];
  final Set<String> _cameraCacheKeys = {};
  final Map<String, dynamic> _tileCache = {};
  final Map<String, dynamic> _speedCache = {};
  final Map<String, dynamic> _directionCache = {};
  final Map<String, dynamic> _bearingCache = {};
  final Map<String, String> _combinedTags = {};

  final ThreadPool _threadPool = ThreadPool();
  final DateTime _applicationStartTime = DateTime.now();

  // Retry configuration for OSM lookups. Attempts are limited and use
  // exponential backoff starting from [osmRetryBaseDelay]. The HTTP request
  // itself can take a while on the Overpass API, therefore the timeout is
  // configurable via [osmRequestTimeout].
  int osmRetryMaxAttempts = 3;
  Duration osmRetryBaseDelay = const Duration(seconds: 1);
  Duration osmRequestTimeout = const Duration(seconds: 30);

  // UI related state mirrors the callbacks of the original project.  In this
  // port the values are exposed via [ValueNotifier] so widgets can listen for
  // changes and update accordingly.
  final ValueNotifier<int?> maxspeedNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<String> roadNameNotifier = ValueNotifier<String>('');
  final ValueNotifier<double?> camRadiusNotifier = ValueNotifier<double?>(null);
  final ValueNotifier<String?> infoPageNotifier = ValueNotifier<String?>(null);

  /// Tracks the number of construction areas discovered so far.
  final ValueNotifier<int> constructionAreaCountNotifier = ValueNotifier<int>(
    0,
  );
  final ValueNotifier<bool> onlineStatusNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> gpsStatusNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> maxspeedStatusNotifier = ValueNotifier<String?>(
    null,
  );
  final ValueNotifier<double> currentSpeedNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<String?> speedCamNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<int?> colorNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<double?> speedCamDistanceNotifier =
      ValueNotifier<double?>(null);
  final ValueNotifier<String?> camTextNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<String?> cameraRoadNotifier = ValueNotifier<String?>(
    null,
  );
  final ValueNotifier<LatLng> positionNotifier = ValueNotifier<LatLng>(
    const LatLng(0, 0),
  );

  /// Tracks the number of POIs returned by the last lookup.
  final ValueNotifier<int> poiCountNotifier = ValueNotifier<int>(0);

  /// If ``true`` points of interest (POIs) are ignored when resolving road
  /// names and max speed values.
  bool dismissPois = true;

  /// Track whether corresponding voice prompts have already been issued to
  /// avoid repeating the same message for consecutive map elements.
  bool _hazardVoice = false;
  bool _waterVoice = false;
  bool _accessControlVoice = false;

  /// Configuration flags mirroring the Python implementation.
  bool disableRoadLookup = false;
  bool alternativeRoadLookup = true;

  /// Number of distance cameras encountered in the current data set.
  int numberDistanceCams = 0;

  /// Distance in kilometres used for look‑ahead camera searches. Updated
  /// dynamically based on the current speed.
  double speedCamLookAheadDistance = 0.0;

  /// Maximum distance in kilometres for speed camera look‑ahead.
  double maxSpeedCamLookAheadDistance = 300.0;

  /// Size of the rectangle used by the legacy POI reader. The original
  /// implementation exposed a full lookup table keyed by driving direction.
  /// Only a single constant value is required for the Dart port, therefore we
  /// keep a simple scalar here.
  double rectangle_periphery_poi_reader = 20.0;

  /// Counters tracking how many cameras of each type are currently known. They
  /// mirror similarly named attributes in the Python implementation and are
  /// mutated by [SpeedCamWarner].
  int fix_cams = 0;
  int traffic_cams = 0;
  int distance_cams = 0;
  int mobile_cams = 0;

  // Variable storing the state of the ccp
  String? ccpStable;

  /// Distance in kilometres used for construction area look‑ahead. Updated
  /// dynamically based on the current speed.
  double constructionAreaLookaheadDistance = 0.0;

  /// Maximum distance in kilometres for construction area look‑ahead.
  double maxConstructionAreaLookaheadDistance = 10.0;

  /// Minimum interval between network lookups to avoid excessive
  /// requests for speed cameras only.
  double dosAttackPreventionIntervalDownloads = 5.0;

  /// Minimum interval between construction area lookups. This is kept separate
  /// from [dosAttackPreventionIntervalDownloads] to reduce the frequency of
  /// construction related requests which are less time critical than speed
  /// camera updates.
  double constructionAreaLookupInterval = 60.0;

  /// Disable construction lookups during application start up for this many
  /// seconds.
  double constructionAreaStartupTriggerMax = 30.0;

  /// Track the last execution time of look‑ahead routines.
  final Map<String, DateTime> _lastLookaheadExecution = {};

  /// Whether look‑ahead mode for cameras is active.
  bool camerasLookAheadMode = true;

  // Additional configuration options loaded from AppConfig.
  Duration maxDownloadTime = const Duration(seconds: 20);
  Duration osmTimeout = const Duration(seconds: 20);
  Duration osmTimeoutMotorway = const Duration(seconds: 30);
  double initialRectDistance = 3.0;
  double speedInfluenceOnRectBoundary = 110.0;
  double currentRectAngle = 90.0;
  double fallbackRectAngle = 123.0;
  int maxCrossRoads = 3;
  bool useOnlyOneExtrapolatedRect = false;
  bool considerBackupRects = true;
  bool enableOrderedRectsExtrapolated = true;
  int maxNumberExtrapolatedRects = 6;
  Map<String, dynamic> maxspeedCountries = {};
  Map<String, dynamic> roadClassesToSpeedConfig = {};

  /// Flag indicating that a camera related operation is currently running.
  bool camInProgress = false;

  /// Cached CCP coordinates and tiles used by [processLookaheadItems] when
  /// ``previousCcp`` is true.
  double longitudeCached = 0.0;
  double latitudeCached = 0.0;
  double? xtileCached;
  double? ytileCached;

  /// Rectangles representing the last look‑ahead search areas.
  Rect? rectSpeedCamLookahead;
  Rect? rectConstructionAreasLookahead;
  GeoRect? rectSpeedCamLookaheadGeo;
  GeoRect? rectConstructionAreasLookaheadGeo;

  /// Default speed limits per road class (km/h).
  static const Map<String, int> roadClassesToSpeed = {
    'trunk': 100,
    'primary': 100,
    'unclassified': 70,
    'secondary': 50,
    'tertiary': 50,
    'service': 50,
    'track': 30,
    'residential': 30,
    'bus_guideway': 30,
    'escape': 30,
    'bridleway': 30,
    'living_street': 20,
    'path': 20,
    'cycleway': 20,
    'pedestrian': 10,
    'footway': 10,
    'road': 10,
    'urban': 50,
  };

  /// Functional road class values mirroring the Python implementation.
  static const Map<String, int> functionalRoadClasses = {
    'motorway': 0,
    '_link': 0,
    'trunk': 1,
    'primary': 2,
    'unclassified': 3,
    'secondary': 4,
    'tertiary': 5,
    'service': 6,
    'residential': 7,
    'living_street': 8,
    'track': 9,
    'bridleway': 10,
    'cycleway': 11,
    'pedestrian': 12,
    'footway': 13,
    'path': 14,
    'bus_guideway': 15,
    'escape': 16,
    'road': 17,
  };

  /// Reverse lookup for functional road classes.
  static const Map<int, String> functionalRoadClassesReverse = {
    0: 'motorway',
    1: 'trunk',
    2: 'primary',
    3: 'unclassified',
    4: 'secondary',
    5: 'tertiary',
    6: 'service',
    7: 'residential',
    8: 'living_street',
    9: 'track',
    10: 'bridleway',
    11: 'cycleway',
    12: 'pedestrian',
    13: 'footway',
    14: 'path',
    15: 'bus_guideway',
    16: 'escape',
    17: 'road',
  };

  RectangleCalculatorThread({
    PredictiveModel? model,
    VoicePromptEvents? voicePromptEvents,
    required this.overspeedChecker,
    required this.deviationCheckerThread,
  })  : _predictiveModel = model ?? PredictiveModel(),
        voicePromptEvents = voicePromptEvents ?? VoicePromptEvents(),
        mostProbableWay = MostProbableWay() {
    _loadConfigs();
    _start();
  }

  /// Update run‑time configuration values.  The map [configs] is merged into an
  /// internal map so repeated calls may override previous values.  Only a small
  /// subset of options is recognised but the method mirrors the Python
  /// interface for compatibility.
  final Map<String, dynamic> _configs = {};

  void setConfigs(Map<String, dynamic> configs) {
    _configs.addAll(configs);
  }

  void _loadConfigs() {
    maxDownloadTime = Duration(
      seconds:
          (AppConfig.get<num>('calculator.max_download_time') ?? 20).toInt(),
    );
    osmTimeout = Duration(
      seconds: (AppConfig.get<num>('calculator.osm_timeout') ?? 20).toInt(),
    );
    osmTimeoutMotorway = Duration(
      seconds:
          (AppConfig.get<num>('calculator.osm_timeout_motorway') ?? 30).toInt(),
    );
    osmRequestTimeout = osmTimeout;
    maxSpeedCamLookAheadDistance =
        (AppConfig.get<num>('calculator.speed_cam_look_ahead_distance_max') ??
                maxSpeedCamLookAheadDistance)
            .toDouble();
    maxConstructionAreaLookaheadDistance = (AppConfig.get<num>(
              'calculator.construction_area_lookahead_distance_max',
            ) ??
            maxConstructionAreaLookaheadDistance)
        .toDouble();
    dosAttackPreventionIntervalDownloads = (AppConfig.get<num>(
              'calculator.dos_attack_prevention_interval_downloads',
            ) ??
            dosAttackPreventionIntervalDownloads)
        .toDouble();
    constructionAreaLookupInterval = (AppConfig.get<num>(
              'calculator.construction_area_lookup_interval',
            ) ??
            constructionAreaLookupInterval)
        .toDouble();
    constructionAreaStartupTriggerMax = (AppConfig.get<num>(
              'calculator.construction_area_startup_trigger_max',
            ) ??
            constructionAreaStartupTriggerMax)
        .toDouble();
    initialRectDistance =
        (AppConfig.get<num>('calculator.initial_rect_distance') ??
                initialRectDistance)
            .toDouble();
    speedInfluenceOnRectBoundary =
        (AppConfig.get<num>('calculator.speed_influence_on_rect_boundary') ??
                speedInfluenceOnRectBoundary)
            .toDouble();
    currentRectAngle = (AppConfig.get<num>('calculator.current_rect_angle') ??
            currentRectAngle)
        .toDouble();
    fallbackRectAngle = (AppConfig.get<num>('calculator.fallback_rect_angle') ??
            fallbackRectAngle)
        .toDouble();
    zoom = (AppConfig.get<num>('calculator.zoom') ?? zoom).toInt();
    maxCrossRoads =
        (AppConfig.get<num>('calculator.max_cross_roads') ?? maxCrossRoads)
            .toInt();
    disableRoadLookup = AppConfig.get<bool>('calculator.disable_road_lookup') ??
        disableRoadLookup;
    camerasLookAheadMode =
        AppConfig.get<bool>('calculator.cameras_look_ahead_mode') ??
            camerasLookAheadMode;
    alternativeRoadLookup =
        AppConfig.get<bool>('calculator.alternative_road_lookup') ??
            alternativeRoadLookup;
    useOnlyOneExtrapolatedRect =
        AppConfig.get<bool>('calculator.use_only_one_extrapolated_rect') ??
            useOnlyOneExtrapolatedRect;
    considerBackupRects =
        AppConfig.get<bool>('calculator.consider_backup_rects') ??
            considerBackupRects;
    dismissPois = AppConfig.get<bool>('calculator.dismiss_pois') ?? dismissPois;
    enableOrderedRectsExtrapolated =
        AppConfig.get<bool>('calculator.enable_ordered_rects_extrapolated') ??
            enableOrderedRectsExtrapolated;
    maxNumberExtrapolatedRects =
        (AppConfig.get<num>('calculator.max_number_extrapolated_rects') ??
                maxNumberExtrapolatedRects)
            .toInt();
    maxspeedCountries =
        AppConfig.get<Map<String, dynamic>>('calculator.maxspeed_countries') ??
            maxspeedCountries;
    roadClassesToSpeedConfig = AppConfig.get<Map<String, dynamic>>(
          'calculator.road_classes_to_speed',
        ) ??
        roadClassesToSpeedConfig;

    printConfigValues();
  }

  /// print all config values
  void printConfigValues() {
    logger.printLogLine('Max Speed: $maxspeed');
    logger.printLogLine('OSM Timeout: $osmTimeout');
    logger.printLogLine(
        'Construction Area Lookahead Distance: $maxConstructionAreaLookaheadDistance');
    // Add more print statements for other config values as needed
    logger.printLogLine(
        'Max Speed Cam Lookahead Distance: $maxSpeedCamLookAheadDistance');
    logger.printLogLine('Fallback Rect Angle: $fallbackRectAngle');
    logger.printLogLine('Zoom: $zoom');
    logger.printLogLine('Max Cross Roads: $maxCrossRoads');
    logger.printLogLine('Disable Road Lookup: $disableRoadLookup');
    logger.printLogLine('Cameras Look Ahead Mode: $camerasLookAheadMode');
    logger.printLogLine('Alternative Road Lookup: $alternativeRoadLookup');
    logger.printLogLine(
        'Use Only One Extrapolated Rect: $useOnlyOneExtrapolatedRect');
    logger.printLogLine('Consider Backup Rects: $considerBackupRects');
    logger.printLogLine('Dismiss POIs: $dismissPois');
    logger.printLogLine(
        'Enable Ordered Rects Extrapolated: $enableOrderedRectsExtrapolated');
    logger.printLogLine('Consider Backup Rects: $considerBackupRects');
    logger.printLogLine('Dismiss POIs: $dismissPois');
    logger.printLogLine(
        'Construction Area Startup Trigger Max: $constructionAreaStartupTriggerMax');
  }

  /// Expose a convenience method to push a new sample and trigger processing in
  /// a single call.  In the Python code this was handled via ``trigger`` and a
  /// condition variable.
  void triggerCalculation(VectorData data) => addVectorSample(data);

  /// Remove any cached state allowing the calculator to start fresh.
  void deleteOldInstances() {
    cleanupMapContent();
    _configs.clear();
  }

  /// Subscribe to rectangles produced by this calculator.  Each event
  /// represents a new bounding rectangle computed from the most recent GPS
  /// sample.  The rectangles emitted include both the current rectangle and
  /// the lookahead rectangle depending on the vehicle’s speed and direction.
  Stream<GeoRect?> get rectangles => _rectangleStreamController.stream;

  /// Subscribe to speed camera notifications.  These may come from either
  /// predictive analytics (machine learning) or from some external data source.
  Stream<SpeedCameraEvent> get cameras => _cameraStreamController.stream;

  /// Current list of known speed cameras.
  List<SpeedCameraEvent> get speedCameras => List.unmodifiable(_cameraCache);

  /// Stream of legacy speed camera map updates mirroring the old queue items.
  Stream<Timestamped<Map<String, dynamic>>> get speedCamEvents =>
      _speedCamEventController.stream;

  /// Controller backing [speedCamEvents]. Exposed so that other components,
  /// such as [GpsThread], can publish updates into the shared stream.
  StreamController<Timestamped<Map<String, dynamic>>>
      get speedCamEventController => _speedCamEventController;

  /// Stream of construction areas discovered during look‑ahead queries.
  Stream<GeoRect?> get constructions => _constructionStreamController.stream;

  /// Connect a stream of [VectorData] samples (e.g. from [GpsThread]) directly
  /// to this calculator.  Each incoming vector is forwarded to
  /// [addVectorSample].
  void bindVectorStream(Stream<VectorData> stream) {
    stream.listen(addVectorSample);
  }

  /// Helper that exposes [FilteredRoadClass.hasValue] for callers that need to
  /// check whether a particular functional road class should be ignored.
  bool isFilteredRoadClass(int value) => FilteredRoadClass.hasValue(value);

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
    await _speedCamEventController.close();
    await _constructionStreamController.close();
  }

  /// Kick off the asynchronous processing loop.  New vector samples are
  /// consumed immediately while heavy processing occurs sequentially so that
  /// operations do not overlap.  Subsequent samples are queued until the
  /// previous one completes.
  void _start() {
    if (_loopStarted) return;
    _loopStarted = true;
    _vectorStreamController.stream.listen((vector) {
      if (!_running) return;
      final alreadyProcessing = _isProcessing;
      _isProcessing = true;
      _processingQueue = _processingQueue.then((_) async {
        try {
          if (_running) {
            await _processVector(vector);
          }
        } catch (e, stack) {
          // Catch and log unexpected exceptions; avoid killing the stream.
          logger.printLogLine('RectangleCalculatorThread error: $e\n$stack');
        } finally {
          _isProcessing = false;
        }
      });
      if (alreadyProcessing) {
        logger.printLogLine(
            'Queueing vector while previous processing is still running');
      }
    });
  }

  /// Process a single vector sample.  This routine extracts the relevant
  /// coordinate and speed information, computes an appropriate bounding
  /// rectangle and publishes it.  It also invokes the predictive model to
  /// determine whether a speed camera might exist ahead on the current route.
  Future<void> _processVector(VectorData vector) async {
    final status = vector.gpsStatus;
    if (status is String) {
      if (status == 'OFFLINE') {
        await processOffline();
        updateGpsStatus(false);
        updateOnlineStatus(false);
        return;
      } else if (status != 'CALCULATE') {
        updateGpsStatus(false);
        updateOnlineStatus(false);
        return;
      }
    }
    updateGpsStatus(true);

    logger.printLogLine(
      'Processing vector lon:${vector.longitude}, lat:${vector.latitude}, speed:${vector.speed}, bearing:${vector.bearing}',
    );
    longitude = vector.longitude;
    latitude = vector.latitude;
    direction = vector.direction;
    final double speedKmH = vector.speed;
    final double bearing = vector.bearing;

    // Cache vector data similar to the Python implementation.
    _speedCache['last'] = speedKmH;
    _directionCache['last'] = direction;
    _bearingCache['last'] = bearing;

    currentSpeedNotifier.value = speedKmH;
    positionNotifier.value = LatLng(latitude, longitude);
    final tile = longLatToTile(latitude, longitude, zoom);
    xtile = tile.x;
    ytile = tile.y;
    _tileCache['xtile'] = xtile;
    _tileCache['ytile'] = ytile;

    // Compute look-ahead distances based on the current speed.  Separate
    // maxima are used for cameras and construction areas.
    final double camLookAheadKm = _computeLookAheadDistance(
      speedKmH,
      maxSpeedCamLookAheadDistance,
    );
    speedCamLookAheadDistance = camLookAheadKm;
    final double constructionLookAheadKm = _computeLookAheadDistance(
      speedKmH,
      maxConstructionAreaLookaheadDistance,
    );
    constructionAreaLookaheadDistance = constructionLookAheadKm;
    if (calculateNewRect) {
      final GeoRect? rect = _computeBoundingRect_simple(
        latitude,
        longitude,
        camLookAheadKm,
        'camera',
      );
      currentRectAngle = bearing;
      _rectangleStreamController
        ..add(null)
        ..add(rect);
    } else {
      logger.printLogLine('No new camera rectangle to add');
    }
    if (calculateNewRectConstruction) {
      final GeoRect? rect = _computeBoundingRect_simple(
        latitude,
        longitude,
        constructionLookAheadKm,
        'construction',
      );
      currentRectAngle = bearing;

      ///_constructionStreamController.add(rect);
    } else {
      logger.printLogLine('No new construction area rectangle to add');
    }

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
      logger.printLogLine(
        'Predictive camera detected at ${predicted.latitude}, ${predicted.longitude}',
      );
      final roadName = await getRoadNameViaNominatim(latitude, longitude);
      predicted.name = roadName ?? '';
      // If a camera was predicted ahead, publish it on the camera stream and
      // optionally record it to persistent storage.
      _cameraStreamController.add(predicted);

      logger.printLogLine('Emitting camera event: $predicted');
      _speedCamEventController.add(
        Timestamped<Map<String, dynamic>>({
          'bearing': 0.0,
          'stable_ccp': ccpStable,
          'ccp': ['IGNORE', 'IGNORE'],
          'fix_cam': [false, 0.0, 0.0, true],
          'traffic_cam': [false, 0.0, 0.0, true],
          'distance_cam': [false, 0.0, 0.0, true],
          'mobile_cam': [true, predicted.longitude, predicted.latitude, true],
          'ccp_node': ['IGNORE', 'IGNORE'],
          'list_tree': [null, null],
          'name': predicted.name,
          'maxspeed': null,
          'direction': '',
          'predictive': true,
        }),
      );
      await uploadCameraToDriveMethod(
        roadNameNotifier.value,
        predicted.latitude,
        predicted.longitude,
        camType: predicted.name,
      );
    }

    if (camerasLookAheadMode) {
      logger.printLogLine('Triggering camera lookahead');
      await processLookaheadItems(_applicationStartTime);
    }

    // Inform the overspeed checker about the latest speed limit so it can
    // warn the driver when necessary. The GPS thread provides the current
    // speed updates directly.
    final dynamic lms = lastMaxSpeed;
    final int? limit = (lms is int) ? lms : null;
    overspeedChecker.updateLimit(limit);

    // Handle possible look-ahead interrupts.
    if (camerasLookAheadMode) {
      logger.printLogLine('Process look-ahead interrupts');
      await processLookAheadInterrupts();
    }
    await processInterrupts();
  }

  /// Compute a lookahead distance in kilometres based on [speedKmH].  The
  /// distance grows linearly with speed and is clamped to [maxDistanceKm].  A
  /// baseline of three kilometres ensures a reasonable search radius even at
  /// low speeds.
  double _computeLookAheadDistance(double speedKmH, double maxDistanceKm) {
    const double base = 3.0;
    final double dynamicDistance = base + speedKmH * (2 / 60); // ~2 min ahead
    return math.min(math.max(dynamicDistance, base), maxDistanceKm);
  }

  /// Given a centre point and a lookahead distance in kilometres, compute a
  /// bounding rectangle.  The rectangle is aligned to the cardinal directions
  /// (north, south, east, west).  The calculation assumes a spherical Earth
  /// with radius 6371 km and converts the linear distances into degrees.
  GeoRect? _computeBoundingRect_simple(
    double latitude,
    double longitude,
    double lookAheadKm,
    var rectType,
  ) {
    const double earthRadiusKm = 6371.0;
    final double latRadians = latitude * math.pi / 180.0;

    // Convert distance (km) into degrees latitude/longitude.  One degree
    // latitude spans approximately 111 km.  Longitude scales with cos(lat).
    final double deltaLat = (lookAheadKm / earthRadiusKm) * (180.0 / math.pi);
    final double deltaLon = (lookAheadKm / earthRadiusKm) *
        (180.0 / math.pi) /
        math.cos(latRadians);

    final double minLat = latitude - deltaLat;
    final double maxLat = latitude + deltaLat;
    final double minLon = longitude - deltaLon;
    final double maxLon = longitude + deltaLon;
    // Store a Rect representation in tile coordinates for geometric queries
    // such as [Rect.pointInRect] or [Rect.pointsCloseToBorder].
    final minTile = longLatToTile(minLat, minLon, zoom);
    final maxTile = longLatToTile(maxLat, maxLon, zoom);
    GeoRect geoRect;
    Rect rect;
    GeoRect? finalRect;
    if (rectType == 'camera') {
      rect = Rect(
        pt1: Point(minTile.x, minTile.y),
        pt2: Point(maxTile.x, maxTile.y),
      );
      geoRect = GeoRect(
        minLat: minLat,
        minLon: minLon,
        maxLat: maxLat,
        maxLon: maxLon,
      );
      lastGeoRect = geoRect;
      lastRect = rect;
      finalRect = lastGeoRect;
    } else {
      rect = Rect(
        pt1: Point(minTile.x, minTile.y),
        pt2: Point(maxTile.x, maxTile.y),
      );
      geoRect = GeoRect(
        minLat: minLat,
        minLon: minLon,
        maxLat: maxLat,
        maxLon: maxLon,
      );
      lastGeoRectConstruction = geoRect;
      lastRectConstruction = rect;
      finalRect = lastGeoRectConstruction;
    }
    return finalRect;
  }

  GeoRect? _computeBoundingRect_advanced(
      double ccpLat, double ccpLon, double xtile, double ytile, String type) {
    // Convert lookahead distance in kilometres to tile units at the current
    // latitude/zoom.  Each slippy map tile spans ``40075.016686 / 2^zoom`` km at
    // the equator and shrinks by ``cos(lat)`` towards the poles.
    double lookaheadDistance;
    if (type == "camera") {
      lookaheadDistance = speedCamLookAheadDistance;
    } else {
      lookaheadDistance = constructionAreaLookaheadDistance;
    }
    final double kmPerTile =
        (40075.016686 * math.cos(ccpLat * math.pi / 180.0)) / math.pow(2, zoom);
    final double tileDistance = lookaheadDistance / kmPerTile;
    final pts = calculatePoints2Angle(
      xtile,
      ytile,
      tileDistance,
      currentRectAngle * math.pi / 180.0,
    );
    final poly = createGeoJsonTilePolygonAngle(
      zoom,
      pts[0],
      pts[2],
      pts[1],
      pts[3],
    );
    double minLat = poly[0].y;
    double maxLat = poly[0].y;
    double minLon = poly[0].x;
    double maxLon = poly[0].x;
    for (final p in poly) {
      if (p.y < minLat) minLat = p.y;
      if (p.y > maxLat) maxLat = p.y;
      if (p.x < minLon) minLon = p.x;
      if (p.x > maxLon) maxLon = p.x;
    }
    final geoRect = GeoRect(
      minLat: minLat,
      minLon: minLon,
      maxLat: maxLat,
      maxLon: maxLon,
    );

    final rect = Rect(
      pt1: Point(pts[0], pts[0]),
      pt2: Point(pts[2], pts[2]),
    );

    GeoRect? finalRect;
    if (type == "camera") {
      lastRect = rect;
      lastGeoRect = geoRect;
      finalRect = lastGeoRect;
    } else {
      lastRectConstruction = rect;
      lastGeoRectConstruction = geoRect;
      finalRect = lastGeoRectConstruction;
    }

    return finalRect;
  }

  /// Convert a longitude/latitude pair into tile coordinates.  This is
  /// equivalent to the ``longlat2tile`` function in the Python code.  The
  /// returned values are fractional; integer parts correspond to tile indices
  /// and fractional parts to pixel offsets within those tiles.  See
  /// https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames for details.
  math.Point<double> longLatToTile(double latDeg, double lonDeg, int zoom) {
    final double latRad = latDeg * math.pi / 180.0;
    final double n = math.pow(2.0, zoom).toDouble();
    final double xTile = (lonDeg + 180.0) / 360.0 * n;
    final double yTile =
        (1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
            2.0 *
            n;
    return math.Point<double>(xTile, yTile);
  }

  /// Convert tile coordinates back into a longitude/latitude pair.  This
  /// corresponds to the ``tile2longlat`` function in the Python code.  The
  /// integer parts of ``xTile`` and ``yTile`` identify the tile index;
  /// fractional parts specify an offset from the tile origin.
  math.Point<double> tileToLongLat(double xTile, double yTile, int zoom) {
    final double n = math.pow(2.0, zoom).toDouble();
    final double lonDeg = xTile / n * 360.0 - 180.0;
    // ``dart:math`` in some environments lacks a `sinh` implementation.
    // Provide a small helper so the conversion works without relying on it.
    double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2.0;
    final double latRad = math.atan(_sinh(math.pi * (1.0 - 2.0 * yTile / n)));
    final double latDeg = latRad * 180.0 / math.pi;
    return math.Point<double>(lonDeg, latDeg);
  }

  /// Legacy wrappers providing backwards compatibility with the original
  /// function names used throughout the project.  The original Python code
  /// exposed ``longlat2tile``/``tile2longlat``; some callers still reference
  /// these identifiers.  Keep small convenience wrappers to avoid touching the
  /// call sites.
  List<double> longlat2tile(double latDeg, double lonDeg, int zoom) {
    final pt = longLatToTile(latDeg, lonDeg, zoom);
    return [pt.x, pt.y];
  }

  List<double> tile2longlat(double xTile, double yTile, int zoom) {
    final pt = tileToLongLat(xTile, yTile, zoom);
    return [pt.x, pt.y];
  }

  /// Construct a [Rect] from two corner points expressed in tile coordinates.
  Rect calculate_rectangle_border(List<double> pt1, List<double> pt2) {
    return Rect(pt1: Point(pt1[0], pt1[1]), pt2: Point(pt2[0], pt2[1]));
  }

  /// Calculate the radius (half of the diagonal) of a rectangle with the given
  /// [height] and [width].
  double calculate_rectangle_radius(double height, double width) {
    return math.sqrt(math.pow(height, 2) + math.pow(width, 2)) / 2.0;
  }

  /// Update the current camera radius and notify listeners.
  void update_cam_radius(double radius) {
    camRadiusNotifier.value = radius;
  }

  /// Format a [DateTime] into HH:MM format.  This helper mirrors the
  /// ``strftime("%H:%M")`` call in the Python code.
  String _formatTimeOfDay(DateTime dt) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
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
      'Sunday',
    ];
    return names[(dt.weekday - 1) % 7];
  }

  // ---------------------------------------------------------------------------
  // Additional helper methods ported from the Python implementation
  // ---------------------------------------------------------------------------

  /// Wrapper around [_start] to mirror the Python ``run`` method.  The
  /// constructor already launches the processing loop, but this method is kept
  /// for API parity.
  void run() {
    _running = true;
    _start();
  }

  /// Stop processing vector samples but keep streams open so the calculator can
  /// be restarted later.
  void stop() {
    _running = false;
  }

  /// Replace the current list of known speed cameras and emit them in batches
  /// to avoid blocking the UI. Duplicate cameras are discarded based on their
  /// coordinates.  Each camera is forwarded to the legacy speed cam warner
  /// queue so the original thread can react to newly discovered cameras.
  Future<void> updateSpeedCams(
    List<SpeedCameraEvent> speedCams, {
    int batchSize = 10,
  }) async {
    final cams = removeDuplicateCameras(speedCams);
    final newCams = <SpeedCameraEvent>[];
    for (final cam in cams) {
      final key = '${cam.latitude},${cam.longitude}';
      if (_cameraCacheKeys.add(key)) {
        _cameraCache.add(cam);
        newCams.add(cam);
      }
    }
    for (var i = 0; i < newCams.length; i += batchSize) {
      final batch = newCams.sublist(i, math.min(i + batchSize, newCams.length));
      logger.printLogLine('Emitting camera batch of ${batch.length} items');
      for (final cam in batch) {
        _cameraStreamController.add(cam);
        logger.printLogLine('Emitting camera event: $cam');
        _speedCamEventController.add(
          Timestamped<Map<String, dynamic>>({
            'bearing': 0.0,
            'stable_ccp': ccpStable,
            'ccp': ['IGNORE', 'IGNORE'],
            'fix_cam': [cam.fixed, cam.longitude, cam.latitude, true],
            'traffic_cam': [cam.traffic, cam.longitude, cam.latitude, true],
            'distance_cam': [cam.distance, cam.longitude, cam.latitude, true],
            'mobile_cam': [cam.mobile, cam.longitude, cam.latitude, true],
            'ccp_node': ['IGNORE', 'IGNORE'],
            'list_tree': [null, null],
            'name': cam.name,
            'maxspeed': cam.maxspeed,
            'direction': '',
          }),
        );
      }
      if (i + batchSize < newCams.length) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  /// Cache used to avoid adding duplicate construction areas.
  final Set<String> _constructionCache = {};

  /// List of construction areas discovered so far.
  List<GeoRect> constructionAreas = [];

  /// Replace the current list of construction areas and emit them in batches
  /// similar to [updateSpeedCams].
  Future<void> updateConstructionAreas(
    List<GeoRect> areas, {
    int batchSize = 10,
  }) async {
    final newAreas = <GeoRect>[];
    for (final area in areas) {
      final key = '${area.minLat},${area.minLon},${area.maxLat},${area.maxLon}';
      if (_constructionCache.add(key)) {
        newAreas.add(area);
      }
    }
    if (newAreas.isEmpty) return;

    logger.printLogLine('Adding ${newAreas.length} new construction areas');
    constructionAreas.addAll(newAreas);
    constructionAreaCountNotifier.value = constructionAreas.length;

    for (var i = 0; i < newAreas.length; i += batchSize) {
      final batch = newAreas.sublist(
        i,
        math.min(i + batchSize, newAreas.length),
      );
      logger.printLogLine(
        'Emitting construction area batch of ${batch.length} items',
      );
      for (final area in batch) {
        _constructionStreamController.add(area);
      }
      if (i + batchSize < newAreas.length) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  /// Reset transient state and clear construction areas.
  void cleanup() {
    lastRect = null;
    lastGeoRect = null;
    constructionAreas = [];
  }

  /// Track whether a camera upload is currently running.
  bool _cameraUploadInProgress = false;

  void cameraInProgress(bool state) {
    _cameraUploadInProgress = state;
  }

  bool get cameraUploadInProgress => _cameraUploadInProgress;

  /// Placeholder kept for API compatibility; does nothing in the Dart port.
  void updateMapQueue() {}

  /// Calculate half the diagonal length of a rectangle defined by [width] and
  /// [height].
  double calculateRectangleRadius(double width, double height) {
    return math.sqrt(width * width + height * height) / 2.0;
  }

  /// Euclidean distance of a point in tile space.
  double tile2hypotenuse(double xtile, double ytile) {
    return math.sqrt(xtile * xtile + ytile * ytile);
  }

  /// Convert tile coordinates to polar coordinates returning ``distance`` and
  /// ``angle`` (degrees).
  math.Point<double> tile2polar(double xtile, double ytile) {
    final double distance = tile2hypotenuse(xtile, ytile);
    final double angle = math.atan2(ytile, xtile) * 180.0 / math.pi;
    return math.Point<double>(distance, angle);
  }

  /// Calculate opposite tile bounds when looking ahead from a given
  /// ``(xtile, ytile)`` position by [distance] tiles at the specified [angle]
  /// (in radians).  The behaviour mirrors the intricate branch logic of the
  /// original Python ``calculatepoints2angle`` helper.
  List<double> calculatePoints2Angle(
    double xtile,
    double ytile,
    double distance,
    double angle,
  ) {
    final double xCos = math.cos(angle) * distance;
    final double ySin = math.sin(angle) * distance;

    double xtileMin;
    double xtileMax;
    double ytileMin;
    double ytileMax;

    if ((angle > 90 && angle <= 120) || (angle > 130 && angle <= 135)) {
      xtileMin = xtile - xCos;
      xtileMax = xtile + xCos;
      ytileMin = ytile + ySin;
      ytileMax = ytile - ySin;
    } else if (angle > 120 && angle <= 122) {
      xtileMin = xtile - xCos;
      xtileMax = xtile + xCos;
      ytileMin = ytile - ySin;
      ytileMax = ytile + ySin;
    } else if (angle > 122 && angle <= 130) {
      xtileMin = xtile + xCos;
      xtileMax = xtile - xCos;
      ytileMin = ytile - ySin;
      ytileMax = ytile + ySin;
    } else {
      xtileMin = xtile + xCos;
      xtileMax = xtile - xCos;
      ytileMin = ytile + ySin;
      ytileMax = ytile - ySin;
    }
    return [xtileMin, xtileMax, ytileMin, ytileMax];
  }

  /// Shift the left boundary of a rectangle westwards.
  double decreaseXtileLeft(double xtile, {int factor = 1}) {
    return xtile - factor.toDouble();
  }

  /// Shift the right boundary of a rectangle eastwards.
  double increaseXtileRight(double xtile, {int factor = 1}) {
    return xtile + factor.toDouble();
  }

  /// Rotate two tile points around the origin by [angle] radians.  The function
  /// mirrors the behaviour of ``rotatepoints2angle`` from the Python code and
  /// returns the rotated coordinates ``[xtileMin, xtileMax, ytileMin, ytileMax]``.
  List<double> rotatePoints2Angle(
    double xtileMin,
    double xtileMax,
    double ytileMin,
    double ytileMax,
    double angle,
  ) {
    final double cosA = math.cos(-angle);
    final double sinA = math.sin(-angle);

    final double nXMin = cosA * xtileMin - sinA * ytileMin;
    final double nYMin = sinA * xtileMin + cosA * ytileMin;

    final double nXMax = cosA * xtileMax - sinA * ytileMax;
    final double nYMax = sinA * xtileMax + cosA * ytileMax;

    return [nXMin, nXMax, nYMin, nYMax];
  }

  /// In Python the vector was represented as a tuple.  Here the [VectorData]
  /// object already holds the required sections so the method returns it
  /// unchanged.
  VectorData getVectorSections(VectorData vector) => vector;

  /// Build a [Rect] from two opposite corner points.
  Rect calculateRectangleBorder(
    math.Point<double> pt1,
    math.Point<double> pt2,
  ) {
    final minX = math.min(pt1.x, pt2.x);
    final maxX = math.max(pt1.x, pt2.x);
    final minY = math.min(pt1.y, pt2.y);
    final maxY = math.max(pt1.y, pt2.y);
    return Rect(pointList: [minX, minY, maxX, maxY]);
  }

  /// Create a GeoJSON polygon from tile bounds.
  List<math.Point<double>> createGeoJsonTilePolygonAngle(
    int zoom,
    double xtileMin,
    double ytileMin,
    double xtileMax,
    double ytileMax,
  ) {
    final p1 = tileToLongLat(xtileMin.abs(), ytileMin.abs(), zoom);
    final p2 = tileToLongLat(xtileMax.abs(), ytileMax.abs(), zoom);
    return [
      p1,
      math.Point<double>(p2.x, p1.y),
      p2,
      math.Point<double>(p1.x, p2.y),
      p1,
    ];
  }

  /// Create a GeoJSON polygon from unrotated tile bounds.
  ///
  /// The original Python implementation returned the bounding box as four
  /// separate values `(LON_MIN, LAT_MIN, LON_MAX, LAT_MAX)`.  Several parts of
  /// the Dart port – in particular [POIReader] – still expect this structure.
  /// Returning the four coordinates keeps those call sites simple while the
  /// higher level rectangle calculations continue to operate on tile based
  /// geometry.  If consumers require the full polygon they can reconstruct it
  /// easily from the returned bounds.
  List<double> createGeoJsonTilePolygon(
    String direction,
    int zoom,
    double xtile,
    double ytile,
    double size,
  ) {
    final double xtileMax = xtile + size;
    final double ytileMax = ytile + size;
    final p1 = tileToLongLat(xtile, ytile, zoom);
    final p2 = tileToLongLat(xtileMax, ytileMax, zoom);
    final lonMin = p1.x;
    final latMin = p2.y;
    final lonMax = p2.x;
    final latMax = p1.y;
    return [lonMin, latMin, lonMax, latMax];
  }

  /// Determine the functional road class value from an OSM highway tag.
  int? getRoadClassValue(String roadClass) {
    for (final entry in functionalRoadClasses.entries) {
      if (roadClass.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// Return the default speed for an OSM road class. Empty string if none.
  String getRoadClassSpeed(String roadClass) {
    for (final entry in roadClassesToSpeed.entries) {
      if (roadClass.contains(entry.key)) {
        return entry.value.toString();
      }
    }
    if (roadClass.contains('_link')) return 'RAMP';
    if (roadClass.contains('urban')) {
      return roadClassesToSpeed['urban']!.toString();
    }
    return '';
  }

  /// Provide a reverse textual representation for a functional road class.
  String getRoadClassTxt(int? roadClass) =>
      functionalRoadClassesReverse[roadClass] ?? 'None';

  /// Check if at least four subsequent position updates resulted in the same
  /// road class.
  static bool isRoadClassStable(List<int> roadCandidates, int roadClassValue) {
    int counter = 0;
    for (var i = 0; i < roadCandidates.length - 1; i++) {
      if (roadCandidates[i] == roadCandidates[i + 1] &&
          roadCandidates[i] == roadClassValue) {
        counter += 1;
      }
    }
    return counter == 2;
  }

  /// Handle a newly resolved road name.  Returns ``true`` if the name was
  /// accepted and stored.
  bool processRoadName({
    required bool foundRoadName,
    required String roadName,
    required bool foundCombinedTags,
    required String roadClass,
    bool poi = false,
    bool facility = false,
  }) {
    if (foundRoadName) {
      logger.printLogLine('Found road name: $roadName');
      final currentFr = getRoadClassValue(roadClass);
      if (currentFr != null && isFilteredRoadClass(currentFr)) {
        logger.printLogLine('Filtered road class: $currentFr');
        return false;
      }
      if (poi && dismissPois) return false;
      if (facility) {
        roadName = 'facility: $roadName';
      }
      lastRoadName = roadName;
      this.foundCombinedTags = foundCombinedTags;
      updateRoadname(roadName, foundCombinedTags);
      return true;
    } else {
      if (lastRoadName != null) {
        updateRoadname(lastRoadName, this.foundCombinedTags);
        return true;
      }
      return false;
    }
  }

  /// Process a max speed entry. The resulting value is stored in
  /// [lastMaxSpeed] so the [overspeedChecker] can warn the driver on the next
  /// position update. Returns a status string mirroring the Python logic.
  String processMaxSpeed(
    dynamic maxspeed,
    bool foundMaxspeed, {
    String? roadName,
    bool motorway = false,
    bool resetMaxspeed = false,
    bool ramp = false,
    int? currentSpeed,
  }) {
    if (resetMaxspeed && !dismissPois) {
      logger.printLogLine('Resetting Overspeed to 10000');
      lastMaxSpeed = null;
      return 'MAX_SPEED_IS_POI';
    }

    if (foundMaxspeed || (maxspeed.toString().isNotEmpty)) {
      var result = prepareDataForSpeedCheck(maxspeed, motorway: motorway);
      maxspeed = result['maxspeed'];
      final bool overspeedReset = result['overspeedReset'];
      if (ramp) {
        logger.printLogLine('Final Maxspeed value is RAMP');
        lastMaxSpeed = null;
      } else {
        final overspeed = overspeedReset ? 10000 : maxspeed;
        logger.printLogLine('Final Maxspeed value is $overspeed');
        lastMaxSpeed = overspeedReset ? null : maxspeed;
      }
      return 'MAX_SPEED_FOUND';
    } else {
      if (lastMaxSpeed != null && lastRoadName == roadName) {
        logger.printLogLine('Using last max speed $lastMaxSpeed');
        return 'LAST_MAX_SPEED_USED';
      }
      lastMaxSpeed = null;
      return 'MAX_SPEED_NOT_FOUND';
    }
  }

  /// Prepare a max speed value for overspeed checking. Returns a map with the
  /// possibly converted speed and a flag whether the overspeed warning should
  /// be reset.
  Map<String, dynamic> prepareDataForSpeedCheck(
    dynamic maxspeed, {
    bool motorway = false,
  }) {
    bool overspeedReset = false;
    try {
      maxspeed = int.parse(maxspeed.toString());
    } catch (_) {
      final String s = maxspeed.toString();
      if (s.contains('AT:motorway')) {
        maxspeed = 130;
      } else if (s.contains('DE:motorway')) {
        overspeedReset = true;
      } else if (motorway) {
        maxspeed = 130;
      } else if (s.contains('mph')) {
        // leave mph values as-is
      } else {
        overspeedReset = true;
      }
    }
    return {'maxspeed': maxspeed, 'overspeedReset': overspeedReset};
  }

  /// Public entry point similar to the Python ``process`` method.  Setting
  /// [updateCcpOnly] skips the predictive camera lookup.
  Future<void> process(VectorData vector, {bool updateCcpOnly = false}) async {
    if (updateCcpOnly) {
      final rect = _computeBoundingRect_simple(
        vector.latitude,
        vector.longitude,
        _computeLookAheadDistance(0, maxSpeedCamLookAheadDistance),
        'camera',
      );
      _rectangleStreamController
        ..add(null)
        ..add(rect);
    } else {
      await _processVector(vector);
    }
  }

  // ---------------------------------------------------------------------------
  // Remaining Python ports

  /// Handle offline scenarios by resetting UI hints. Mirrors the lightweight
  /// Python implementation which clears the road name and, if no maxspeed was
  /// previously shown, displays a placeholder value.
  Future<void> processOffline() async {
    if (lastMaxSpeed == '' || lastMaxSpeed == null) {
      updateMaxspeed('');
    }

    // Extrapolate the current position based on cached values.  When the GPS
    // goes offline we keep emitting position updates by projecting the last
    // known coordinates forward using the cached speed and bearing.
    final double speed = (_speedCache['last'] as double?) ?? 0.0; // km/h
    final double bearing = (_bearingCache['last'] as double?) ?? 0.0;

    // Use cached coordinates if available, otherwise fall back to the last
    // known "online" position.
    double startLon = longitudeCached != 0.0 ? longitudeCached : longitude;
    double startLat = latitudeCached != 0.0 ? latitudeCached : latitude;

    if (speed > 0) {
      final double distance = speed / 3.6; // metres travelled in ~1 second
      final Point newPos = calculateExtrapolatedPosition(
        Point(startLon, startLat),
        bearing,
        distance,
      );
      longitudeCached = newPos.x;
      latitudeCached = newPos.y;
    } else {
      longitudeCached = startLon;
      latitudeCached = startLat;
    }

    // Notify listeners, such as the speed camera warner thread, about the
    // updated extrapolated position.  In the original Python implementation
    // this data was propagated via ``speed_cam_queue``; here we emit an event
    // through the [positionNotifier] so consumers always receive the latest
    // coordinates even while offline.
    positionNotifier.value = LatLng(latitudeCached, longitudeCached);

    _speedCamEventController.add(
      Timestamped<Map<String, dynamic>>({
        'bearing': bearing,
        'stable_ccp': ccpStable,
        'ccp': [longitudeCached, latitudeCached],
        'fix_cam': [false, 0.0, 0.0, false],
        'traffic_cam': [false, 0.0, 0.0, false],
        'distance_cam': [false, 0.0, 0.0, false],
        'mobile_cam': [false, 0.0, 0.0, false],
        'ccp_node': [null, null],
        'list_tree': [null, null],
      }),
    );
  }

  /// Perform a nominative road name lookup and update UI state accordingly.
  Future<void> processLookAheadInterrupts() async {
    final roadName = await getRoadNameViaNominatim(latitude, longitude);
    if (roadName != null) {
      if (!roadName.startsWith('ERROR:')) {
        processRoadName(
          foundRoadName: true,
          roadName: roadName,
          foundCombinedTags: false,
          roadClass: 'unclassified',
        );
      }
    }
    final online = await internetAvailable();
    updateOnlineStatus(online);
    if (!camInProgress && online) {
      updateMaxspeed('');
      lastMaxSpeed = '';
    } else {
      lastMaxSpeed = 'KEEP';
    }
  }

  /// Simplified interrupt handler. Returns ``'look_ahead'`` when look‑ahead
  /// mode is active, otherwise ``0``.  The rich rectangle update logic from the
  /// Python version has not been ported.
  Future<dynamic> processInterrupts() async {
    // Wait for the next state emitted by the deviation checker and cache it
    // locally.  The Python version consumed values from a queue; listening to
    // the stream mirrors that behaviour.
    ccpStable = await deviationCheckerThread.stream.first;
  }

  Future<(bool, String?)> uploadCameraToDriveMethod(
    String roadName,
    double latitude,
    double longitude, {
    String camType = 'Manual Camera',
  }) async {
    final (success, status) = await uploadCameraToDrive(
      name: camType,
      roadName: roadName,
      latitude: latitude,
      longitude: longitude,
    );
    if (success) {
      voicePromptEvents.emit('ADDED_POLICE');
    } else {
      const knownErrors = {
        'RATE_LIMIT_EXCEEDED',
        'CAM_FILE_NOT_FOUND',
        'DUPLICATE_COORDINATES',
      };
      voicePromptEvents.emit(
        knownErrors.contains(status) ? status! : 'ADDING_POLICE_FAILED',
      );
    }
    return (success, status);
  }

  /// Trigger asynchronous look‑ahead downloads for speed cameras and
  /// construction areas.  ``previousCcp`` reuses cached coordinates from the
  /// last stable CCP.
  Future<void> processLookaheadItems(DateTime applicationStartTime) async {
    logger.printLogLine('processLookaheadItems');
    double xtile;
    double ytile;
    double ccpLon;
    double ccpLat;

    final p = longLatToTile(latitude, longitude, zoom);
    xtile = p.x;
    ytile = p.y;
    xtileCached = xtile;
    ytileCached = ytile;
    longitudeCached = longitude;
    latitudeCached = latitude;
    ccpLon = longitude;
    ccpLat = latitude;

    logger.printLogLine(
      'Lookahead for tiles ($xtile,$ytile) at ($ccpLat,$ccpLon)',
    );

    // Process predictive cameras
    await processPredictiveCameras(ccpLon, ccpLat);

    final lookups = [
      {
        'rect': rectSpeedCamLookahead,
        'geoRect': rectSpeedCamLookaheadGeo,
        'func': RectangleCalculatorThread.startThreadPoolSpeedCamera,
        'msg': 'Speed Camera lookahead',
        'trigger': speedCamLookupAhead,
        'type': 'camera',
      },
      {
        'rect': rectConstructionAreasLookahead,
        'geoRect': rectConstructionAreasLookaheadGeo,
        'func': RectangleCalculatorThread.startThreadPoolConstructionAreas,
        'msg': 'Construction area lookahead',
        'trigger': constructionsLookupAhead,
        'type': 'construction',
      },
    ];

    for (final item in lookups) {
      final Rect? rect = item['rect'] as Rect?;
      final String msg = item['msg'] as String;
      final String rectType = item['type'] as String;
      final func = item['func'] as Future<void> Function(
        Future<void> Function(GeoRect),
        int,
        GeoRect,
      );
      final trigger = item['trigger'] as Future<void> Function(GeoRect);

      if (rect != null) {
        final GeoRect? geoRect = item['geoRect'] as GeoRect?;
        if (geoRect != null) {
          final inside = geoRect.geoPointInRect(latitude, longitude);
          final close = geoRect.pointsCloseToBorderLatLon(
            latitude,
            longitude,
            lookAhead: true,
            lookAheadMode: msg,
          );
          if (inside && !close) {
            logger.printLogLine('Skipping $msg - inside existing lookahead');
            if (rectType == 'camera') calculateNewRect = false;
            if (rectType == 'construction') {
              calculateNewRectConstruction = false;
            }
            continue;
          }
          if (rectType == 'camera') calculateNewRect = true;
          if (rectType == 'construction') calculateNewRectConstruction = true;
        }
      } else {
        calculateNewRect = false;
        calculateNewRectConstruction = false;
      }

      final now = DateTime.now();
      final last = _lastLookaheadExecution[msg];
      final rateLimit = msg == 'Construction area lookahead'
          ? constructionAreaLookupInterval
          : dosAttackPreventionIntervalDownloads;
      if (last != null) {
        final elapsed = now.difference(last).inMilliseconds / 1000;
        if (elapsed < rateLimit) {
          final wait = (rateLimit - elapsed).toStringAsFixed(1);
          logger.printLogLine(
              'Skipping ' + msg + ' - rate limited (wait ' + wait + 's)');
          continue;
        }
      }

      if (msg == 'Construction area lookahead') {
        final elapsed =
            DateTime.now().difference(applicationStartTime).inSeconds;
        if (elapsed <= constructionAreaStartupTriggerMax) {
          logger.printLogLine('Skipping $msg during startup grace period');
          continue;
        }
      }

      // First we have to clean up the old camera cache
      cleanupMapContent();

      logger.printLogLine('Executing $msg lookup');
      if (msg == 'Speed Camera lookahead') {
        rectSpeedCamLookahead = lastRect;
        rectSpeedCamLookaheadGeo = lastGeoRect;
        await func(trigger, 1, lastGeoRect!);
      } else if (msg == 'Construction area lookahead') {
        rectConstructionAreasLookahead = lastRectConstruction;
        rectConstructionAreasLookaheadGeo = lastGeoRectConstruction;
        await func(trigger, 1, lastGeoRectConstruction!);
      }
      logger.printLogLine('$msg lookup finished');
      _lastLookaheadExecution[msg] = DateTime.now();
    }
  }

  /// Process construction area lookup results and append them to the internal
  /// list. Resolves way nodes to coordinates and updates map and info page.
  Future<void> processConstructionAreasLookupAheadResults(dynamic data,
      String lookupType, GeoRect rect, http.Client? client) async {
    if (data is! List) return;
    final newAreas = <GeoRect>[];
    final processedNodeIds = <int>{};

    // Helper to add a node if coordinates are known.
    void addNode(double? lat, double? lon, int nodeId) {
      if (lat == null || lon == null) {
        logger.printLogLine(
          'Failed to resolve node id $nodeId',
          logLevel: 'WARNING',
        );
        return;
      }
      if (!processedNodeIds.add(nodeId)) return;
      final rect = GeoRect(minLat: lat, minLon: lon, maxLat: lat, maxLon: lon);
      logger.printLogLine('Adding construction area at ($lat, $lon)');
      newAreas.add(rect);
    }

    for (final element in data) {
      if (element is! Map<String, dynamic>) continue;
      final type = element['type'];
      if (type == 'way') {
        final nodes = element['nodes'] as List? ?? [];
        for (final n in nodes) {
          var resultNode = data.firstWhere(
            (e) => e['type'] == 'node' && (e['id'] as int) == n,
            orElse: () => null,
          );
          double? lat;
          double? lon;
          if (resultNode != null) {
            logger.printLogLine('Found node $n in lookup results');
            lat = (resultNode['lat'] as num?)?.toDouble();
            lon = (resultNode['lon'] as num?)?.toDouble();
            addNode(lat, lon, n);
          } else {
            logger.printLogLine('Node $n not found in lookup results');
            final result = await triggerOsmLookup(
              rect,
              lookupType: lookupType,
              nodeId: n,
              client: client,
            );
            if (result.success && result.elements != null) {
              logger.printLogLine(
                'Node $n found in separate lookup results',
              );
              final firstEl = result.elements!.first;
              final lat = (firstEl['lat'] as num?)?.toDouble();
              final lon = (firstEl['lon'] as num?)?.toDouble();
              addNode(lat, lon, n);
            }
          }

          if (newAreas.isNotEmpty) {
            final total = constructionAreas.length + newAreas.length;
            await updateConstructionAreas(newAreas);
            updateMapQueue();
            updateInfoPage('CONSTRUCTION_AREAS:$total');
            logger.printLogLine('Total construction areas: $total');
            newAreas.clear();
          }
        }
      }
    }
  }

  Future<SpeedCameraEvent?> processPredictiveCameras(
    double longitude,
    double latitude,
  ) async =>
      predictSpeedCamera(
        model: _predictiveModel,
        latitude: latitude,
        longitude: longitude,
        timeOfDay: _formatTimeOfDay(DateTime.now()),
        dayOfWeek: _formatDayOfWeek(DateTime.now()),
      );

  Future<void> speedCamLookupAhead(
    GeoRect rect, {
    http.Client? client,
  }) async {
    logger.printLogLine('speedCamLookupAhead bounds: $rect');
    for (final type in ['camera_ahead', 'distance_cam']) {
      logger.printLogLine('speedCamLookupAhead requesting $type');
      final result = await triggerOsmLookup(
        rect,
        lookupType: type,
        client: client,
      );
      logger.printLogLine(
        'speedCamLookupAhead result for $type success=${result.success} elements=${result.elements?.length ?? 0}',
      );
      if (result.success && result.elements != null) {
        await processSpeedCamLookupAheadResults(
          result.elements!,
          type,
        );
      }
    }
  }

  Future<void> constructionsLookupAhead(
    GeoRect rect, {
    http.Client? client,
  }) async {
    logger.printLogLine('constructionsLookupAhead bounds: $rect');
    logger.printLogLine(
      'constructionsLookupAhead requesting construction_ahead',
    );
    final result = await triggerOsmLookup(
      rect,
      lookupType: 'construction_ahead',
      client: client,
    );
    logger.printLogLine(
      'constructionsLookupAhead result success=${result.success} elements=${result.elements?.length ?? 0}',
    );
    if (result.success && result.elements != null) {
      await processConstructionAreasLookupAheadResults(
        result.elements!,
        'node',
        rect,
        client,
      );
    }
  }

  Future<void> processSpeedCamLookupAheadResults(
    dynamic data,
    String lookupType,
  ) async {
    if (data is! List) return;

    final List<SpeedCameraEvent> cams = [];
    try {
      for (final element in data) {
        try {
          if (element is! Map<String, dynamic>) continue;
          final tags = element['tags'] as Map<String, dynamic>? ?? {};
          var lat = (element['lat'] as num?)?.toDouble();
          var lon = (element['lon'] as num?)?.toDouble();
          if ((lat == null || lon == null) && element['center'] is Map) {
            final center = element['center'] as Map<String, dynamic>;
            lat = (center['lat'] as num?)?.toDouble();
            lon = (center['lon'] as num?)?.toDouble();
          }
          if ((lat == null || lon == null) &&
              element['geometry'] is List &&
              (element['geometry'] as List).isNotEmpty) {
            final first = (element['geometry'] as List).first;
            if (first is Map<String, dynamic>) {
              lat = (first['lat'] as num?)?.toDouble();
              lon = (first['lon'] as num?)?.toDouble();
            }
          }
          // ``maxspeed`` tags in OSM may be stored as strings (e.g. "50" or
          // "50 km/h") which previously caused a runtime type cast error when
          // casting directly to ``num``.  Use ``resolveMaxSpeed`` to safely parse the
          // numeric portion instead.
          final maxspeed = resolveMaxSpeed(tags);
          if (lat == null || lon == null) {
            logger.printLogLine(
              'Skipping speed camera element without coordinates: ${element['id']}',
              logLevel: 'DEBUG',
            );
            continue;
          }

          String? roadName;
          try {
            roadName = await getRoadNameViaNominatim(lat, lon);
          } catch (e, stack) {
            logger.printLogLine(
              'getRoadNameViaNominatim failed: $e',
              logLevel: 'ERROR',
            );
            logger.printLogLine(stack.toString(), logLevel: 'DEBUG');
          }
          if (lookupType == 'distance_cam') {
            updateNumberOfDistanceCameras(tags);
            final role = tags['role'];
            if (role == 'device') {
              logger.printLogLine('Adding device speed camera: $tags');
              final cam = SpeedCameraEvent(
                latitude: lat,
                longitude: lon,
                distance: true,
                name: tags['name']?.toString() ?? roadName ?? '',
                maxspeed: maxspeed,
              );
              _cameraCache.add(cam);
              cams.add(cam);
              distance_cams += 1;
            }
            continue;
          }

          final camTypeTag = tags['camera:type']?.toString();
          if (camTypeTag == 'mobile' || tags['mobile'] == 'yes') {
            logger.printLogLine('Adding mobile speed camera: $tags');
            final cam = SpeedCameraEvent(
              latitude: lat,
              longitude: lon,
              mobile: true,
              name: tags['name']?.toString() ?? roadName ?? '',
              maxspeed: maxspeed,
            );
            _cameraCache.add(cam);
            cams.add(cam);
            mobile_cams += 1;
            continue;
          }

          final highwayVal = tags['highway']?.toString();
          final speedCamVal = tags['speed_camera']?.toString();
          if (highwayVal == 'speed_camera' && speedCamVal == null) {
            logger.printLogLine('Adding fixed speed camera: $tags');
            final cam = SpeedCameraEvent(
              latitude: lat,
              longitude: lon,
              fixed: true,
              name: tags['name']?.toString() ?? roadName ?? '',
              maxspeed: maxspeed,
            );
            _cameraCache.add(cam);
            cams.add(cam);
            fix_cams += 1;
            continue;
          }

          if (speedCamVal == 'traffic_signals') {
            logger.printLogLine('Adding traffic speed camera: $tags');
            final cam = SpeedCameraEvent(
              latitude: lat,
              longitude: lon,
              traffic: true,
              name: tags['name']?.toString() ?? roadName ?? '',
              maxspeed: maxspeed,
            );
            _cameraCache.add(cam);
            cams.add(cam);
            traffic_cams += 1;
          }
        } catch (e, stack) {
          logger.printLogLine(
            'Error processing speed camera element: $e',
            logLevel: 'ERROR',
          );
          logger.printLogLine(stack.toString(), logLevel: 'DEBUG');
        }
      }
    } catch (e, stack) {
      logger.printLogLine(
        'Error processing $lookupType lookup: $e',
        logLevel: 'ERROR',
      );
      logger.printLogLine(stack.toString(), logLevel: 'DEBUG');
    }

    logger.printLogLine(
      'Processed ${cams.length} cameras from $lookupType lookup',
    );
    if (cams.isNotEmpty) {
      logger.printLogLine(
        'Found ${cams.length} cameras from $lookupType lookup',
      );
      try {
        // Await the update so the speed cam warner sees new cameras before
        // handling the next CCP event.
        await updateSpeedCams(cams);
      } catch (e, stack) {
        logger.printLogLine(
          'updateSpeedCams failed: $e',
          logLevel: 'ERROR',
        );
        logger.printLogLine(stack.toString(), logLevel: 'DEBUG');
      }
      updateMapQueue();
      updateInfoPage(
        'SPEED_CAMERAS:$fix_cams,$traffic_cams,$distance_cams,$mobile_cams',
      );
    }

  void resolveDangersOnTheRoad(Map<String, dynamic> way) {
    final hazard = way['hazard'];
    if (hazard != null) {
      infoPageNotifier.value = hazard.toString().toUpperCase();
      if (!_hazardVoice) {
        voicePromptEvents.emit('HAZARD');
        _hazardVoice = true;
      }
    } else {
      if (_hazardVoice) {
        _hazardVoice = false;
      }
      if (infoPageNotifier.value != null &&
          infoPageNotifier.value!.isNotEmpty) {
        infoPageNotifier.value = null;
      }
    }

    void resolveDangersOnTheRoad(Map<String, dynamic> way) {
      final hazard = way['hazard'];
      if (hazard != null) {
        infoPageNotifier.value = hazard.toString().toUpperCase();
        if (!_hazardVoice) {
          voicePromptEvents.emit('HAZARD');
          _hazardVoice = true;
        }
      } else {
        if (_hazardVoice) {
          _hazardVoice = false;
        }
        if (infoPageNotifier.value != null &&
            infoPageNotifier.value!.isNotEmpty) {
          infoPageNotifier.value = null;
        }
      }

      if (way.containsKey('waterway')) {
        infoPageNotifier.value = way['waterway'].toString().toUpperCase();
        if (!_waterVoice) {
          voicePromptEvents.emit('WATER');
          _waterVoice = true;
        }
      } else {
        if (_waterVoice) {
          _waterVoice = false;
        }
      }

      if (way.containsKey('access') && way['access'] != 'yes') {
        if (!_accessControlVoice) {
          voicePromptEvents.emit('ACCESS_CONTROL');
          _accessControlVoice = true;
        }
      } else {
        if (_accessControlVoice) {
          _accessControlVoice = false;
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Caching and geometry helpers

  void updateRectanglePeriphery(Rect rect) {
    lastRect = rect;
    lastGeoRect = null;
  }

  void processAllSpeedCameras(List<SpeedCameraEvent> cams) {
    _cameraCache
      ..clear()
      ..addAll(removeDuplicateCameras(cams));
  }

  List<SpeedCameraEvent> processSpeedCamerasOnTheWay(
    Point point,
    double radius,
  ) {
    return _cameraCache
        .where(
          (c) => _distance(point.x, point.y, c.longitude, c.latitude) <= radius,
        )
        .toList();
  }

  Map<String, SpeedCameraEvent> buildDataStructure(
    List<SpeedCameraEvent> cams,
  ) {
    final map = <String, SpeedCameraEvent>{};
    for (final cam in cams) {
      map['${cam.latitude},${cam.longitude}'] = cam;
    }
    return map;
  }

  List<SpeedCameraEvent> speedCamLookup(Point p) {
    return processSpeedCamerasOnTheWay(p, 0.01); // approx 1km radius
  }

  List<Map<String, dynamic>>? _getCachedLocalData(
    GeoRect area,
    String? lookupType,
  ) {
    bool within(double lat, double lon) =>
        lat >= area.minLat &&
        lat <= area.maxLat &&
        lon >= area.minLon &&
        lon <= area.maxLon;

    if (lookupType == 'camera_ahead' || lookupType == 'distance_cam') {
      final cams = _cameraCache
          .where((c) => within(c.latitude, c.longitude))
          .map(
            (c) => {
              'lat': c.latitude,
              'lon': c.longitude,
              'tags': {'highway': 'speed_camera', 'name': c.name},
            },
          )
          .toList();
      return cams.isEmpty ? null : cams;
    } else if (lookupType == 'construction_ahead') {
      final areas = constructionAreas
          .where(
            (r) => within(r.minLat, r.minLon) || within(r.maxLat, r.maxLon),
          )
          .map(
            (r) => {
              'lat': r.minLat,
              'lon': r.minLon,
              'tags': {'construction': 'yes'},
            },
          )
          .toList();
      return areas.isEmpty ? null : areas;
    }
    return null;
  }

  void cleanupMapContent() {
    _cameraCache.clear();
    _cameraCacheKeys.clear();
    _tileCache.clear();
    _speedCache.clear();
    _directionCache.clear();
    _bearingCache.clear();
    clearCombinedTags(_combinedTags);
  }

  List<SpeedCameraEvent> removeDuplicateCameras(List<SpeedCameraEvent> cams) {
    final seen = <String>{};
    final result = <SpeedCameraEvent>[];
    for (final cam in cams) {
      final key = '${cam.latitude},${cam.longitude}';
      if (seen.add(key)) result.add(cam);
    }
    return result;
  }

  void updateNumberOfDistanceCameras(Map<String, dynamic> wayTags) {
    if (wayTags['role'] == 'device') {
      numberDistanceCams += 1;
    }
  }

  void cacheCcp(String key, dynamic value) => _tileCache[key] = value;
  void cacheTiles(String key, dynamic value) => _tileCache[key] = value;
  void cacheCspeed(String key, dynamic value) => _speedCache[key] = value;
  void cacheDirection(String key, dynamic value) =>
      _directionCache[key] = value;
  void cacheBearing(String key, dynamic value) => _bearingCache[key] = value;

  double convertCspeed(double speedKmh) => speedKmh / 3.6;

  Point calculateExtrapolatedPosition(
    Point start,
    double bearingDeg,
    double distanceMeters,
  ) {
    // Use the "destination point" formula on a sphere to extrapolate a new
    // geographic position.  [start] holds ``longitude`` (x) and ``latitude``
    // (y) in degrees.  [bearingDeg] is the direction of travel and
    // [distanceMeters] the travelled distance.
    const double earthRadius = 6378137.0; // WGS84 equatorial radius in metres

    final double brng = bearingDeg * math.pi / 180.0;
    final double lat1 = start.y * math.pi / 180.0;
    final double lon1 = start.x * math.pi / 180.0;
    final double dr = distanceMeters / earthRadius;

    final double lat2 = math.asin(
      math.sin(lat1) * math.cos(dr) +
          math.cos(lat1) * math.sin(dr) * math.cos(brng),
    );
    final double lon2 = lon1 +
        math.atan2(
          math.sin(brng) * math.sin(dr) * math.cos(lat1),
          math.cos(dr) - math.sin(lat1) * math.sin(lat2),
        );

    return Point(lon2 * 180.0 / math.pi, lat2 * 180.0 / math.pi);
  }

  double _distance(double lon1, double lat1, double lon2, double lat2) {
    final dx = lon1 - lon2;
    final dy = lat1 - lat2;
    return math.sqrt(dx * dx + dy * dy);
  }

  // ---------------------------------------------------------------------------
  // Rectangle and thread-pool helpers ported from the Python implementation

  /// Iterate through [rectAttributes] and trigger a cache lookup when the
  /// current tile position lies inside any stored rectangle.
  void checkSpecificRectangle() {
    rectAttributes.forEach((key, generator) {
      if (generator.length < 3) return;
      final Rect currentRect = generator[0] as Rect;
      final DoubleLinkedListNodes? linkedListGenerator =
          generator[1] as DoubleLinkedListNodes?;
      final BinarySearchTree? treeGenerator = generator[2] as BinarySearchTree?;

      if (currentRect.pointInRect(xtile, ytile)) {
        RectangleCalculatorThread.startThreadPoolDataLookup(
          triggerCacheLookup,
          lat: latitude,
          lon: longitude,
          linkedList: linkedListGenerator,
          tree: treeGenerator,
          cRect: currentRect,
          waitTillCompleted: false,
        );
        return;
      }
    });
  }

  /// Determine whether the direction stored in [matchingRect] matches the
  /// latest heading [direction].
  bool hasSameDirection() {
    return matchingRect.getRectangleIdent() == direction;
  }

  /// Check if the current [matchingRect] represents an extrapolated rectangle.
  bool isExtrapolatedRectMatching() {
    return matchingRect.getRectangleString().contains('EXTRAPOLATED');
  }

  /// Check if the previously processed rectangle was extrapolated.
  bool isExtrapolatedRectPrevious() {
    return previousRect != null &&
        previousRect!.getRectangleString().contains('EXTRAPOLATED');
  }

  // Geometry wrappers for parity with the Python class ---------------------

  Rect intersectRectangle(Rect a, Rect b) =>
      rect_utils.intersectRectangle(a, b);

  bool pointInIntersectedRect(Rect a, Rect b, double x, double y) =>
      rect_utils.pointInIntersectedRect(a, b, x, y);

  Rect extrapolateRectangle(Rect previous, Rect current) =>
      rect_utils.extrapolateRectangle(previous, current);

  bool checkAllRectangles(Point p, List<Rect> rects) =>
      rect_utils.checkAllRectangles(p, rects);

  List<Rect> sortRectangles(List<Rect> rects) =>
      rect_utils.sortRectangles(rects);

  // The following helpers mirror the ``start_thread_pool_*`` family from the
  // Python implementation. They dispatch asynchronous tasks via Futures to
  // keep API parity without relying on native threads.

  static Future<void> startThreadPoolConstructionAreas(
    Future<void> Function(GeoRect) func,
    int workerThreads,
    GeoRect lastGeoRect,
  ) async {
    await Future.microtask(() => func(lastGeoRect));
  }

  static Future<void> startThreadPoolDataLookup(
    Future<bool> Function({
      double latitude,
      double longitude,
      DoubleLinkedListNodes? linkedListGenerator,
      BinarySearchTree? treeGenerator,
      Rect? currentRect,
    }) func, {
    double? lat,
    double? lon,
    DoubleLinkedListNodes? linkedList,
    BinarySearchTree? tree,
    Rect? cRect,
    bool waitTillCompleted = true,
  }) async {
    final future = func(
      latitude: lat ?? 0,
      longitude: lon ?? 0,
      linkedListGenerator: linkedList,
      treeGenerator: tree,
      currentRect: cRect,
    );
    if (waitTillCompleted) {
      await future;
    }
  }

  static Future<void> startThreadPoolDataStructure(
    Future<void> Function({dynamic dataset, Rect? rectPreferred}) func, {
    int workerThreads = 1,
    Map<String, List<dynamic>> serverResponses = const {},
    bool extrapolated = false,
    bool waitTillCompleted = true,
  }) async {
    final tasks = <Future>[];
    serverResponses.forEach((_, dataList) {
      tasks.add(func(dataset: dataList[2], rectPreferred: dataList[4]));
    });
    if (waitTillCompleted) {
      await Future.wait(tasks);
    }
  }

  static Future<void> startThreadPoolProcessLookAheadInterrupts(
    Future<void> Function() func, {
    int workerThreads = 1,
  }) async {
    await Future.microtask(() => func());
  }

  static Future<void> startThreadPoolSpeedCamStructure(
    Future<void> Function(DoubleLinkedListNodes?, BinarySearchTree?) func, {
    int workerThreads = 1,
    DoubleLinkedListNodes? linkedList,
    BinarySearchTree? tree,
  }) async {
    await Future.microtask(() => func(linkedList, tree));
  }

  static Future<void> startThreadPoolSpeedCamera(
    Future<void> Function(GeoRect) func,
    int workerThreads,
    GeoRect lastGeoRect,
  ) async {
    await Future.microtask(() => func(lastGeoRect));
  }

  static Future<void> startThreadPoolUploadSpeedCameraToDrive(
    Future<void> Function(String, double, double) func,
    int workerThreads,
    String name,
    double latitude,
    double longitude,
  ) async {
    await Future.microtask(() => func(name, latitude, longitude));
  }

  // ---------------------------------------------------------------------------
  // OSM/network helpers

  Future<bool> triggerCacheLookup({
    double latitude = 0,
    double longitude = 0,
    DoubleLinkedListNodes? linkedListGenerator,
    BinarySearchTree? treeGenerator,
    Rect? currentRect,
  }) async {
    if (currentRect != null) {
      logger
          .printLogLine('Trigger Cache lookup from current Rect $currentRect');
    }
    if (linkedListGenerator == null) {
      logger.printLogLine(
          ' trigger_cache_lookup: linkedListGenerator instance not created!');
      return false;
    }
    linkedListGenerator.setTreeGeneratorInstance(treeGenerator);
    final node = linkedListGenerator.matchNode(latitude, longitude);
    if (node != null &&
        treeGenerator != null &&
        treeGenerator.contains(node.id)) {
      final way = treeGenerator[node.id]!;
      resolveDangersOnTheRoad(way.tags);
      if (!disableRoadLookup) {
        if (alternativeRoadLookup) {
          final roadName = await getRoadNameViaNominatim(latitude, longitude);
          if (roadName != null) {
            processRoadName(
              foundRoadName: true,
              roadName: roadName,
              foundCombinedTags: false,
              roadClass: way.tags['highway']?.toString() ?? 'unclassified',
              poi: way.tags['poi'] == true,
              facility: way.tags['facility'] == true,
            );
          }
          final maxspeed = resolveMaxSpeed(way.tags);
          final status = processMaxSpeed(maxspeed ?? '', maxspeed != null);
          if (status == 'MAX_SPEED_NOT_FOUND') {
            final def = processMaxSpeedForRoadClass(
              way.tags['highway']?.toString() ?? 'unclassified',
              null,
            );
            processMaxSpeed(def, true);
          }
        } else {
          final resolved = resolveRoadnameAndMaxSpeed(way.tags);
          processRoadName(
            foundRoadName: resolved.roadName != null,
            roadName: resolved.roadName ?? '',
            foundCombinedTags: false,
            roadClass: way.tags['highway']?.toString() ?? 'unclassified',
            poi: way.tags['poi'] == true,
            facility: way.tags['facility'] == true,
          );
          processMaxSpeed(
            resolved.maxSpeed ?? '',
            resolved.maxSpeed != null,
            roadName: resolved.roadName,
          );
        }
      } else {
        final maxspeed = resolveMaxSpeed(way.tags);
        final status = processMaxSpeed(maxspeed ?? '', maxspeed != null);
        if (status == 'MAX_SPEED_NOT_FOUND') {
          final def = processMaxSpeedForRoadClass(
            way.tags['highway']?.toString() ?? 'unclassified',
            null,
          );
          processMaxSpeed(def, true);
        }
      }
    }
    return true;
  }

  Future<OsmLookupResult> triggerOsmLookup(
    GeoRect area, {
    String? lookupType,
    int? nodeId,
    http.Client? client,
  }) async {
    logger.printLogLine(
      'triggerOsmLookup: lookupType=$lookupType nodeId=$nodeId area=$area',
      logLevel: 'DEBUG',
    );

    final bbox =
        '(${area.minLat},${area.minLon},${area.maxLat},${area.maxLon});';
    final baseUrlRaw = AppConfig.get<String>('speedCamWarner.baseurl') ??
        'https://overpass-api.de/api/interpreter';
    // Strip a trailing "?" which would otherwise make the path `/interpreter?`
    // and lead to HTTP 400 responses from the Overpass API.
    final baseUrl = baseUrlRaw.endsWith('?')
        ? baseUrlRaw.substring(0, baseUrlRaw.length - 1)
        : baseUrlRaw;
    final querystringCameras1 =
        AppConfig.get<String>('speedCamWarner.querystring_cameras1') ?? '';
    final querystringCameras2 =
        AppConfig.get<String>('speedCamWarner.querystring_cameras2') ?? '';
    final querystringCameras3 =
        AppConfig.get<String>('speedCamWarner.querystring_cameras3') ?? '';
    final querystringDistanceCams =
        AppConfig.get<String>('speedCamWarner.querystring_distance_cams') ?? '';
    final querystringConstructionAreas = AppConfig.get<String>(
          'speedCamWarner.querystring_construction_areas',
        ) ??
        '';
    final querystringConstructionAreas2 = AppConfig.get<String>(
          'speedCamWarner.querystring_construction_areas2',
        ) ??
        '';

    String query;
    String queryTermination = ");out body;";
    if (lookupType == 'camera_ahead') {
      query =
          '$querystringCameras1$bbox$querystringCameras2$bbox$querystringCameras3$bbox$queryTermination';
    } else if (lookupType == 'distance_cam') {
      query = '$querystringDistanceCams$bbox$queryTermination';
    } else if (lookupType == 'construction_ahead') {
      query =
          '$querystringConstructionAreas$bbox$querystringConstructionAreas2$bbox$queryTermination';
    } else if (lookupType == 'node') {
      if (nodeId == null) {
        return OsmLookupResult(
          false,
          'ERROR',
          null,
          'Missing nodeId for node lookup',
          area,
        );
      }
      query = '[out:json][timeout:25];node($nodeId);out body;';
      queryTermination = '';
    } else {
      logger.printLogLine(
        'triggerOsmLookup: Unsupported lookup type $lookupType',
        logLevel: 'ERROR',
      );
      return OsmLookupResult(
        false,
        'ERROR',
        null,
        'Unsupported lookup type $lookupType',
        area,
      );
    }
    logger.printLogLine('triggerOsmLookup query: $query', logLevel: 'DEBUG');

    // Build the request URI using a GET with the query supplied via the
    // `data` parameter.  ``Uri.replace`` handles proper URL encoding so that
    // characters such as quotes and spaces are percent encoded.  Strip any
    // leading ``data=`` from the configured query to avoid duplicated prefixes.
    final queryParam = query.startsWith('data=') ? query.substring(5) : query;
    final uri = Uri.parse(
      baseUrl,
    ).replace(queryParameters: {'data': queryParam});
    logger.printLogLine('triggerOsmLookup uri: $uri', logLevel: 'DEBUG');
    final http.Client httpClient = client ?? http.Client();

    for (var attempt = 1; attempt <= osmRetryMaxAttempts; attempt++) {
      final start = DateTime.now();
      http.Response? resp;
      try {
        resp = await httpClient.get(
          uri,
          headers: {
            'User-Agent': 'speedcamwarner-dart',
            'Accept': 'application/json',
          },
        ).timeout(osmRequestTimeout);
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final elements = data['elements'] as List<dynamic>?;
          logger.printLogLine(
            'triggerOsmLookup $lookupType returned ${elements?.length ?? 0} elements',
            logLevel: 'DEBUG',
          );
          updateOnlineStatus(true);
          if (client == null) httpClient.close();
          return OsmLookupResult(true, 'OK', elements, null, area);
        } else {
          await checkWorkerThreadStatus();
          logger.printLogLine(
            'triggerOsmLookup $lookupType non-200 HTTP ${resp.statusCode}',
            logLevel: 'WARNING',
          );
          if (client == null) httpClient.close();
          return OsmLookupResult(
            false,
            'ERROR',
            null,
            'HTTP ${resp.statusCode}',
            area,
          );
        }
      } on TimeoutException catch (e) {
        logger.printLogLine(
          'triggerOsmLookup $lookupType timeout on attempt $attempt: $e',
          logLevel: 'WARNING',
        );
        if (attempt >= osmRetryMaxAttempts) {
          await checkWorkerThreadStatus();
          final cached = _getCachedLocalData(area, lookupType);
          if (client == null) httpClient.close();
          if (cached != null && cached.isNotEmpty) {
            logger.printLogLine(
              'triggerOsmLookup $lookupType returning cached data after timeout',
              logLevel: 'WARNING',
            );
            updateOnlineStatus(false);
            return OsmLookupResult(true, 'CACHE', cached, e.toString(), area);
          }
          logger.printLogLine(
            'triggerOsmLookup $lookupType timeout after $osmRetryMaxAttempts attempts',
            logLevel: 'ERROR',
          );
          voicePromptEvents.emit('INTERNET_CONN_FAILED');
          updateOnlineStatus(false);
          return OsmLookupResult(false, 'TIMEOUT', null, e.toString(), area);
        }
        final delayMs = osmRetryBaseDelay.inMilliseconds * (1 << (attempt - 1));
        await Future.delayed(Duration(milliseconds: delayMs));
      } catch (e) {
        await checkWorkerThreadStatus();
        logger.printLogLine(
          'triggerOsmLookup $lookupType exception: $e',
          logLevel: 'ERROR',
        );
        if (client == null) httpClient.close();
        return OsmLookupResult(false, 'OSMERROR', null, e.toString(), area);
      } finally {
        final duration = DateTime.now().difference(start);
        reportDownloadTime(duration);
        final status = resp?.statusCode.toString() ?? 'FAILED';
        logger.printLogLine(
          'triggerOsmLookup $lookupType HTTP $status in ${duration.inMilliseconds}ms',
          logLevel: 'DEBUG',
        );
      }
    }

    if (client == null) httpClient.close();
    updateOnlineStatus(false);
    return OsmLookupResult(false, 'UNKNOWN', null, 'Unexpected error', area);
  }

  Future<void> checkWorkerThreadStatus() =>
      _threadPool.checkWorkerThreadStatus();

  void reportDownloadTime(Duration duration) {
    if (duration > maxDownloadTime) {
      voicePromptEvents.emit('LOW_DOWNLOAD_DATA_RATE');
    }
  }

  Future<String?> getRoadNameViaNominatim(double lat, double lon) async {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lon',
    );
    try {
      final resp = await http.get(
        uri,
        headers: {'User-Agent': 'speedcamwarner-dart'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return data['display_name']?.toString();
      }
    } catch (_) {}
    return null;
  }

  bool getOsmDataState() => _tileCache.isNotEmpty;

  void fillOsmData(Map<String, dynamic> data) {
    _tileCache.addAll(data);
  }

  Future<bool> internetAvailable() async {
    try {
      final resp = await http.get(
        Uri.parse('https://example.com'),
        headers: {'User-Agent': 'speedcamwarner-dart'},
      ).timeout(const Duration(seconds: 3));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // UI and status updates

  int? get maxspeed => maxspeedNotifier.value;
  String? get roadName => roadNameNotifier.value;
  String? get infoPage => infoPageNotifier.value;
  String? get maxspeedStatus => maxspeedStatusNotifier.value;
  String? get speedCamWarning => speedCamNotifier.value;
  int? get color => colorNotifier.value;
  double? get speedCamDistance => speedCamDistanceNotifier.value;
  String? get camText => camTextNotifier.value;
  String? get cameraRoad => cameraRoadNotifier.value;

  void updateMaxspeed(dynamic maxspeed, {List<double>? color}) {
    if (maxspeed == null) {
      return;
    }
    final String text = maxspeed.toString();
    if (text.isEmpty || text.toUpperCase() == 'CLEANUP') {
      maxspeedNotifier.value = null;
      return;
    }
    if (text.toUpperCase() == 'POI') {
      maxspeedNotifier.value = null;
      return;
    }
    if (maxspeed is num) {
      maxspeedNotifier.value = maxspeed.toInt();
    } else {
      maxspeedNotifier.value = int.tryParse(text);
    }
  }

  void updateRoadname(String? roadname, [bool foundCombinedTags = false]) {
    if (roadname == null || roadname.isEmpty || roadname == 'cleanup') {
      roadNameNotifier.value = '';
      return;
    }
    if (foundCombinedTags) {
      roadNameNotifier.value = "<combined_tags> not implemented!";
    } else {
      roadNameNotifier.value = roadname;
    }
  }

  void updateCamRadius(double value) => camRadiusNotifier.value = value;
  void updateInfoPage(String value) => infoPageNotifier.value = value;
  void updatePoiCount(int value) => poiCountNotifier.value = value;
  void updateOnlineStatus(bool value) => onlineStatusNotifier.value = value;
  void updateGpsStatus(bool value) => gpsStatusNotifier.value = value;

  void updateSpeedCam(String warning) => speedCamNotifier.value = warning;
  void updateColor(int color) => colorNotifier.value = color;

  void updateSpeedCamDistance(double? meter) =>
      speedCamDistanceNotifier.value = meter;

  void updateCamText(String? text) => camTextNotifier.value = text;

  void updateCameraRoad(String? road) => cameraRoadNotifier.value = road;
}
