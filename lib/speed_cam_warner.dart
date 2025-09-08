import 'dart:async';
import 'dart:math';

import 'rectangle_calculator.dart';
import 'thread_base.dart';
import 'voice_prompt_events.dart';
import 'config.dart';
import 'logger.dart';
import 'package:latlong2/latlong.dart';
import 'ui/map_page.dart';

/// Ported from `SpeedCamWarnerThread.py`.
///
/// The class keeps track of speed camera warnings and provides numerous
/// helper functions for processing camera information.  The implementation is
/// a direct translation of the original Python thread based code.  Many of the
/// collaborators such as queues or UI widgets are typed as `dynamic` because
/// their concrete implementations live elsewhere in the project.
class SpeedCamWarner {
  // ---------------------------- configuration ----------------------------
  static bool camInProgress = false;

  final dynamic resume;
  final VoicePromptEvents voicePromptEvents;
  final dynamic osmWrapper; // ignore: unused_field
  final RectangleCalculatorThread calculator;

  // runtime state --------------------------------------------------------
  List<double?> ccpNodeCoordinates = [null, null];
  double? ccpBearing;
  Map<dynamic, List<dynamic>> itemQueue = {};
  Map<dynamic, List<dynamic>> itemQueueBackup = {};
  Map<dynamic, double> startTimes = {};
  List<dynamic> insertedSpeedcams = [];
  double longitude = 0.0;
  double latitude = 0.0;
  int dismissCounter = 0;
  dynamic currentCamPointer;
  bool maxStorageTimeIncreased = false;

  final Logger logger = Logger('SpeedCamWarner');

  /// Items older than this are considered out-of-date and discarded.
  static const Duration _staleThreshold = Duration(seconds: 2);

  // configuration values -------------------------------------------------
  bool enableInsideRelevantAngleFeature = true;
  double emergencyAngleDistance = 150; // meters
  bool deleteCamerasOutsideLookaheadRectangle = true;
  double maxAbsoluteDistance = 300000; // meters
  double maxStorageTime = 28800; // seconds
  late double maxStorageTimeBackup;
  int traversedCamerasInterval = 3; // seconds
  int maxDismissCounter = 5;
  int maxDistanceToFutureCamera = 5000; // meters

  StreamSubscription<Timestamped<Map<String, dynamic>>>? _sub;
  void Function()? _positionListener;
  LatLng? _lastPosition;

  SpeedCamWarner({
    required this.resume,
    required this.voicePromptEvents,
    required this.osmWrapper,
    required this.calculator,
  }) {
    setConfigs();
    Timer.periodic(Duration(seconds: traversedCamerasInterval), (_) {
      deletePassedCameras();
    });
  }

  // ----------------------------------------------------------------------
  void setConfigs() {
    enableInsideRelevantAngleFeature = AppConfig.get<bool>(
          'speedCamWarner.enable_inside_relevant_angle_feature',
        ) ??
        enableInsideRelevantAngleFeature;
    emergencyAngleDistance =
        (AppConfig.get<num>('speedCamWarner.emergency_angle_distance') ??
                emergencyAngleDistance)
            .toDouble();
    deleteCamerasOutsideLookaheadRectangle = AppConfig.get<bool>(
          'speedCamWarner.delete_cameras_outside_lookahead_rectangle',
        ) ??
        deleteCamerasOutsideLookaheadRectangle;
    maxAbsoluteDistance =
        (AppConfig.get<num>('speedCamWarner.max_absolute_distance') ??
                maxAbsoluteDistance)
            .toDouble();
    maxStorageTime = (AppConfig.get<num>('speedCamWarner.max_storage_time') ??
            maxStorageTime)
        .toDouble();
    traversedCamerasInterval =
        (AppConfig.get<num>('speedCamWarner.traversed_cameras_interval') ??
                traversedCamerasInterval)
            .toInt();
    maxDismissCounter =
        (AppConfig.get<num>('speedCamWarner.max_dismiss_counter') ??
                maxDismissCounter)
            .toInt();
    maxDistanceToFutureCamera =
        (AppConfig.get<num>('speedCamWarner.max_distance_to_future_camera') ??
                maxDistanceToFutureCamera)
            .toInt();

    // Keep a backup of the storage time for later restoration.
    maxStorageTimeBackup = maxStorageTime;
  }

  // ------------------------------ threading -----------------------------
  Future<void> run() async {
    logger.printLogLine('SpeedCamWarner thread started');
    _positionListener = () {
      _lastPosition = calculator.positionNotifier.value;
    };
    calculator.positionNotifier.addListener(_positionListener!);
    _sub = calculator.speedCamEvents.listen(process);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    if (_positionListener != null) {
      calculator.positionNotifier.removeListener(_positionListener!);
    }
    logger.printLogLine('SpeedCamWarner terminating');
  }

  /// Receive a raw position update from the GPS thread.  This mirrors the
  /// ``ccp`` updates produced by the original Python implementation.
  void updatePosition(VectorData vector) {
    longitude = vector.longitude;
    latitude = vector.latitude;
    ccpBearing = vector.bearing;
    _lastPosition = LatLng(vector.latitude, vector.longitude);
  }

  String camKey(double lat, double lon) =>
      '${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)}';

  List<double> parseCamKey(String key) {
    final parts = key.split(',');
    return [double.parse(parts[1]), double.parse(parts[0])];
  }

  void process(Timestamped<Map<String, dynamic>> envelope) async {
    logger.printLogLine('Processing speedcam event');
    if (DateTime.now().difference(envelope.timestamp) > _staleThreshold) {
      // Skip stale updates that may arrive out of order.
      return;
    }
    var item = envelope.data;

    if (item.containsKey('update_cam_name')) {
      String name = item['name'];
      final coords = (item['cam_coords'] as List).cast<double>();
      final updateKey = camKey(coords[1], coords[0]);
      logger.printLogLine('Received update_cam_name $name for $updateKey');
      if (itemQueue.containsKey(updateKey)) {
        itemQueue[updateKey]![7] = name;
      }
      return;
    }

    ccpBearing = item['bearing'];
    var stableCcp = item['stable_ccp'] ?? 'UNSTABLE';
    adaptMaxStorageTime(stableCcp);

    if (item['ccp'][0] == 'EXIT' || item['ccp'][1] == 'EXIT') {
      logger.printLogLine('Speedcamwarner thread got a termination item');
      return;
    }

    if (item['ccp'][0] == 'IGNORE' || item['ccp'][1] == 'IGNORE') {
      logger.printLogLine('Ignore CCP update');
    } else {
      logger.printLogLine('Received new CCP update');
      longitude = item['ccp'][0];
      latitude = item['ccp'][1];
    }

    // process fix cameras ------------------------------------------------
    if (item['fix_cam'][0] == true) {
      var enforcement = item['fix_cam'][3];
      if (!enforcement) {
        logger.printLogLine(
          'Fix Cam with ${item['fix_cam'][1]} ${item['fix_cam'][2]} is not an enforcement camera. Skipping..',
        );
        return null;
      }

      final insertKey =
          camKey(item['fix_cam'][2], item['fix_cam'][1]); // new stable object
      if (isAlreadyAdded(insertKey)) {
        logger.printLogLine(
          'Cam with ${item['fix_cam'][1]} ${item['fix_cam'][2]} already added. Skip processing..',
        );
        return null;
      } else {
        logger.printLogLine(
          'Add new fix cam (${item['fix_cam'][1]}, ${item['fix_cam'][2]})',
        );
        ccpNodeCoordinates = [
          double.tryParse(item['ccp_node'][0].toString()),
          double.tryParse(item['ccp_node'][1].toString())
        ];
        var linkedList = item['list_tree'][0];
        var tree = item['list_tree'][1];
        var startTime = DateTime.now().millisecondsSinceEpoch / 1000.0;

        String? roadname = item['name'];
        var maxSpeed = item['maxspeed'];
        var newCam = true;
        var previousLife = 'was_none';
        var predictive = false;
        var camDirection = convertCamDirection(item['direction']);
        startTimes[insertKey] = startTime;
        itemQueue[insertKey] = [
          'fix',
          false,
          ccpNodeCoordinates,
          linkedList,
          tree,
          -1.0,
          startTime,
          roadname,
          0.0,
          camDirection,
          maxSpeed,
          newCam,
          previousLife,
          predictive,
        ];
        insertedSpeedcams.add(insertKey);
      }
    }

    // process traffic cameras -------------------------------------------
    if (item['traffic_cam'][0] == true) {
      var enforcement = item['traffic_cam'][3];
      if (!enforcement) {
        print(
          'Traffic Cam with ${item['traffic_cam'][1]} ${item['traffic_cam'][2]} is not an enforcement camera. Skipping..',
        );
        return null;
      }

      final insertKey = camKey(item['traffic_cam'][2], item['traffic_cam'][1]);
      if (isAlreadyAdded(insertKey)) {
        print(
          'Cam with ${item['traffic_cam'][1]} ${item['traffic_cam'][2]} already added. Skip processing..',
        );
        return null;
      } else {
        print(
          'Add new traffic cam (${item['traffic_cam'][1]}, ${item['traffic_cam'][2]})',
        );
        logger.printLogLine(
          'Add new traffic cam (${item['traffic_cam'][1]}, ${item['traffic_cam'][2]})',
        );

        ccpNodeCoordinates = [
          double.tryParse(item['ccp_node'][0].toString()),
          double.tryParse(item['ccp_node'][1].toString())
        ];
        var linkedList = item['list_tree'][0];
        var tree = item['list_tree'][1];
        var startTime = DateTime.now().millisecondsSinceEpoch / 1000.0;

        String? roadname = item['name'];
        var maxSpeed = item['maxspeed'];
        var newCam = true;
        var previousLife = 'was_none';
        var predictive = false;
        var camDirection = convertCamDirection(item['direction']);
        startTimes[insertKey] = startTime;
        itemQueue[insertKey] = [
          'traffic',
          false,
          ccpNodeCoordinates,
          linkedList,
          tree,
          -1.0,
          startTime,
          roadname,
          0.0,
          camDirection,
          maxSpeed,
          newCam,
          previousLife,
          predictive,
        ];
        insertedSpeedcams.add(insertKey);
      }
    }

    // process distance cameras ------------------------------------------
    if (item['distance_cam'][0] == true) {
      var enforcement = item['distance_cam'][3];
      if (!enforcement) {
        print(
          'Distance Cam with ${item['distance_cam'][1]} ${item['distance_cam'][2]} is not an enforcement camera. Skipping..',
        );
        return null;
      }

      final insertKey =
          camKey(item['distance_cam'][2], item['distance_cam'][1]);
      if (isAlreadyAdded(insertKey)) {
        print(
          'Cam with ${item['distance_cam'][1]} ${item['distance_cam'][2]} already added. Skip processing..',
        );
        return null;
      } else {
        print(
          'Add new distance cam (${item['distance_cam'][1]}, ${item['distance_cam'][2]})',
        );
        logger.printLogLine(
          'Add new distance cam (${item['distance_cam'][1]}, ${item['distance_cam'][2]})',
        );

        ccpNodeCoordinates = [
          double.tryParse(item['ccp_node'][0].toString()),
          double.tryParse(item['ccp_node'][1].toString())
        ];
        var linkedList = item['list_tree'][0];
        var tree = item['list_tree'][1];
        var startTime = DateTime.now().millisecondsSinceEpoch / 1000.0;

        String? roadname = item['name'];
        var maxSpeed = item['maxspeed'];
        var newCam = true;
        var previousLife = 'was_none';
        var predictive = false;
        var camDirection = convertCamDirection(item['direction']);
        startTimes[insertKey] = startTime;
        itemQueue[insertKey] = [
          'distance',
          false,
          ccpNodeCoordinates,
          linkedList,
          tree,
          -1.0,
          startTime,
          roadname,
          0.0,
          camDirection,
          maxSpeed,
          newCam,
          previousLife,
          predictive,
        ];
        insertedSpeedcams.add(insertKey);
      }
    }

    // process mobile cameras --------------------------------------------
    if (item['mobile_cam'][0] == true) {
      var enforcement = item['mobile_cam'][3];
      if (!enforcement) {
        print(
          'Mobile Cam with ${item['mobile_cam'][1]} ${item['mobile_cam'][2]} is not an enforcement camera. Skipping..',
        );
        return null;
      }

      final insertKey = camKey(item['mobile_cam'][2], item['mobile_cam'][1]);
      if (isAlreadyAdded(insertKey)) {
        print(
          'Cam with ${item['mobile_cam'][1]} ${item['mobile_cam'][2]} already added. Skip processing..',
        );
        return null;
      } else {
        print(
          'Add new mobile cam (${item['mobile_cam'][1]}, ${item['mobile_cam'][2]})',
        );
        logger.printLogLine(
          'Add new mobile cam (${item['mobile_cam'][1]}, ${item['mobile_cam'][2]})',
        );

        ccpNodeCoordinates = [
          double.tryParse(item['ccp_node'][0].toString()),
          double.tryParse(item['ccp_node'][1].toString())
        ];
        var linkedList = item['list_tree'][0];
        var tree = item['list_tree'][1];
        var startTime = DateTime.now().millisecondsSinceEpoch / 1000.0;

        String? roadname = item['name'];
        var maxSpeed = item['maxspeed'];
        var predictive = item['predictive'] ?? false;
        var newCam = true;
        var previousLife = 'was_none';
        var camDirection = convertCamDirection(item['direction']);
        startTimes[insertKey] = startTime;
        itemQueue[insertKey] = [
          'mobile',
          false,
          ccpNodeCoordinates,
          linkedList,
          tree,
          -1.0,
          startTime,
          roadname,
          0.0,
          camDirection,
          maxSpeed,
          newCam,
          previousLife,
          predictive,
        ];
        insertedSpeedcams.add(insertKey);
      }
    }

    // after adding all cameras, continue with management of existing cams
    var camsToDelete = <dynamic>[];
    var camList = <List<dynamic>>[];

    // reinserting backup cameras if necessary
    for (var entry in itemQueueBackup.entries.toList()) {
      var cam = entry.key;
      var camAttributes = entry.value;
      final key = parseCamKey(cam);
      var currentDistance = checkDistanceBetweenTwoPoints(key, [
        longitude,
        latitude,
      ]);
      if (itemQueueBackup.containsKey(cam)) {
        var startTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
        camAttributes[6] = startTime;
        var lastDistance = camAttributes[8];
        if (currentDistance < lastDistance) {
          print(
            'Reinserting ${camAttributes[0]} camera $cam with new distance $currentDistance meters and start time $startTime seconds',
          );
          itemQueue[cam] = camAttributes;
          final queue = itemQueue[cam];
          if (queue != null) {
            queue[1] = false;
            queue[5] = -1;
            queue[6] = startTime;
            queue[8] = currentDistance;
            queue[11] = true;
            queue[12] = 'was_backup';
          }
          startTimes[cam] = startTime;
          itemQueueBackup.remove(cam);
        }
      }
    }

    for (var entry in itemQueue.entries.toList()) {
      var cam = entry.key;
      var camAttributes = entry.value;
      final key = parseCamKey(cam);
      var distance = checkDistanceBetweenTwoPoints(key, [longitude, latitude]);
      camAttributes.add(distance);
    }

    // sort based on last distance
    itemQueue = Map.fromEntries(
      itemQueue.entries.toList()
        ..sort((a, b) => (a.value.last as num).compareTo(b.value.last as num)),
    );

    for (var entry in itemQueue.entries.toList()) {
      var cam = entry.key;
      var camAttributes = entry.value;
      var distance = camAttributes.last;
      var roadName = itemQueue[cam]?[7] ?? '';
      print(
        'Initial Distance to speed cam ($cam, ${camAttributes[0]}): $distance meters , last distance: ${camAttributes[5]}, storage_time: ${camAttributes[6]} seconds, predictive: ${camAttributes[13]}, road name: $roadName',
      );

      if (distance < 0 ||
          camAttributes[1] == true ||
          distance >= maxAbsoluteDistance) {
        print(
            "Deleting camera $cam with distance $distance it's too far away or already passed!");
        camsToDelete.add(cam);
        removeCachedCamera(cam);
        //updateCalculatorCams(camAttributes);
        final camera = parseCamKey(cam);
        MapPage.removeCameraMarker(camera[0], camera[1]);
        triggerFreeFlow();
      } else {
        if (startTimes.containsKey(cam) && itemQueue.containsKey(cam)) {
          final queue = itemQueue[cam];
          if (queue != null && queue[12] == 'was_backup') {
            queue[12] = 'is_standard';
          } else {
            var startTime = DateTime.now().millisecondsSinceEpoch / 1000.0 -
                startTimes[cam]!;
            queue?[6] = startTime;
            queue?[11] = false;
          }

          if (camAttributes[1] == 'to_be_stored') {
            camsToDelete.add(cam);
            backupCamera(cam, distance);
          }

          if (camAttributes[1] == false) {
            camList.add([cam, distance]);
          }
        }
      }
    }

    deleteCameras(camsToDelete);

    var selected = sortPois(camList);
    var cam = selected.item1;
    var camEntry = selected.item2;
    var angleMismatchVoice = false;

    if (cam != currentCamPointer) {
      angleMismatchVoice = true;
      dismissCounter = 0;
    }
    currentCamPointer = cam;
    if (cam == null) {
      print('No cameras available. Abort sorting process');
      updateCamRoad(reset: true);
      return null;
    }

    var camListFollowup = [...camList];
    camListFollowup.remove(camEntry);
    var nextCamPair = sortPois(camListFollowup);
    var nextCam = nextCamPair.item1;
    var nextCamEntry = nextCamPair.item2;

    var nextCamRoad = '';
    var nextCamDistance = '';
    var nextCamDistanceAsInt = 0;
    var processNextCam = false;
    if (nextCam != null && itemQueue.containsKey(nextCam)) {
      try {
        nextCamRoad = itemQueue[nextCam]?[7] ?? '';
        if (nextCamRoad != '' && nextCamRoad.length > 20) {
          nextCamRoad = '${nextCamRoad.substring(0, 20)}...';
        }
        // The distance stored in the queue is only the initial value at the
        // time the camera was inserted.  For future cameras this value can
        // remain ``0.0`` which is misleading when presented to the user.  Always
        // recompute the current distance to keep the information accurate.
        final key = parseCamKey(nextCam);
        final nextDistance =
            checkDistanceBetweenTwoPoints(key, [longitude, latitude]);
        nextCamDistance = '$nextDistance';
        nextCamDistanceAsInt = int.tryParse(nextCamDistance.split('.')[0]) ?? 0;
        // Update the cached distance so subsequent lookups have a sensible
        // starting point instead of ``0.0``.
        itemQueue[nextCam]?[8] = nextDistance;
        processNextCam = true;
      } catch (_) {}
    }

    List<dynamic>? attributes;
    try {
      attributes = itemQueue[cam];
      if (attributes == null) return null;
    } catch (_) {
      print('Speed camera with coordinates ($cam) has been deleted already');
      return null;
    }
    var newCam = attributes[11];
    var camRoadName = attributes[7];
    var linkedList = attributes[3];
    var tree = attributes[4];
    var lastDistance = (attributes[5] as num?)?.toDouble() ?? -1.0;
    var maxSpeed = attributes[10];
    var predictive = attributes[13];
    var speedcamType = attributes[0];
    // Distance values may be stored as either integers or doubles depending on
    // how they were produced earlier in the pipeline.  Downstream logic
    // expects a ``double`` which previously resulted in a runtime type error
    // when an ``int`` slipped through.  Normalise the value here so that the
    // angle matching and subsequent calculations always operate on a ``double``
    // regardless of the original numeric type.
    var distance = (attributes[8] as num?)?.toDouble() ?? 0.0;

    // Calculate the follow-up distance to the already detected camera based on
    // the latest CCP position.  Previously the stored distance value was reused
    // which could lag behind the actual distance when the vehicle had moved in
    // the meantime.  Recomputing here keeps the warning logic in sync with the
    // current location before triggering any UI or voice updates.
    if (attributes[1] == false) {
      final key = parseCamKey(cam);
      distance = checkDistanceBetweenTwoPoints(key, [longitude, latitude]);
      print(
        ' Followup Distance to current speed cam ($cam, $speedcamType, $camRoadName): '
        '${distance.toDouble()} meters , last distance: $lastDistance, '
        'storage_time: ${attributes[6]} seconds, predictive: $predictive',
      );
      if (processNextCam) {
        try {
          print(
            ' -> Future speed cam in queue is: coords: '
            '($nextCam), road name: $nextCamRoad, distance: $nextCamDistance',
          );
        } catch (_) {
          print(' -> Future speed cam information unavailable');
        }
      } else {
        print(' No future speed cam in queue found');
      }
    }

    if (enableInsideRelevantAngleFeature) {
      if (!matchCameraAgainstAngle(
        cam,
        distance,
        camRoadName,
        angleMismatchVoice: angleMismatchVoice,
      )) {
        itemQueue[cam]?[5] = lastDistance;
        return null;
      }
    }

    triggerSpeedCamUpdate(
      roadName: camRoadName,
      distance: distance,
      camCoordinates: cam,
      speedcam: speedcamType,
      ccpNode: attributes[2],
      linkedList: linkedList,
      tree: tree,
      lastDistance: lastDistance,
      maxSpeed: maxSpeed,
      predictive: predictive,
      nextCamRoad: nextCamRoad,
      nextCamDistance: nextCamDistance,
      nextCamDistanceAsInt: nextCamDistanceAsInt,
      processNextCam: processNextCam,
    );
    // Propagate the current camera processing state to the calculator thread.
    // In the original Python implementation this mirrors
    // `self.calculator.camera_in_progress(...)` to keep the UI and prediction
    // logic in sync with whether a camera is actively being handled.
    calculator.cameraInProgress(camInProgress);

    return null;
  }

  // ---------------------- helper and utility methods --------------------
  void adaptMaxStorageTime(var stableCcp) {
    if (stableCcp == 'UNSTABLE' && !maxStorageTimeIncreased) {
      print('CCP is not stable. Increasing max storage time by 600 seconds');
      maxStorageTime += 600;
      maxStorageTimeIncreased = true;
    } else {
      maxStorageTime = maxStorageTimeBackup;
      maxStorageTimeIncreased = false;
    }
  }

  bool matchCameraAgainstAngle(
    dynamic cam,
    double currentDistanceToCam,
    dynamic camRoadName, {
    bool angleMismatchVoice = false,
  }) {
    if (!insideRelevantAngle(cam, currentDistanceToCam)) {
      camInProgress = false;
      triggerFreeFlow();
      print(
        'Leaving Speed Camera with coordinates: ($cam), road name: $camRoadName because of Angle mismatch',
      );
      if (angleMismatchVoice) {
        voicePromptEvents.emit('ANGLE_MISMATCH');
      }
      return false;
    }
    return true;
  }

  void backupCamera(dynamic cam, double distance) {
    try {
      var cpCamQueue = Map.from(itemQueue);
      itemQueueBackup[cam] = cpCamQueue[cam]!;
      itemQueueBackup[cam]![1] = false;
      itemQueueBackup[cam]![7] = cpCamQueue[cam]![7];
      itemQueueBackup[cam]![8] = distance;
      itemQueueBackup[cam]![12] = 'was_standard';
      var startTime =
          DateTime.now().millisecondsSinceEpoch / 1000.0 - cpCamQueue[cam]![6];
      print(
        'Backup camera $cam with last distance $distance km and start time $startTime seconds',
      );
    } catch (e) {
      print('Backup of camera $cam with last distance $distance km failed!');
    }
  }

  void deleteCameras(List<dynamic> camsToDelete) {
    for (var cam in camsToDelete) {
      try {
        itemQueue.remove(cam);
        startTimes.remove(cam);
      } catch (_) {
        print('Failed to delete camera $cam, camera already deleted');
      }
    }
    camsToDelete.clear();
  }

  void removeCachedCamera(dynamic cam) {
    try {
      var camIndex = insertedSpeedcams.indexOf(cam);
      print('Removing cached speed camera $cam at index $camIndex');
      insertedSpeedcams.removeAt(camIndex);
    } catch (_) {}
  }

  bool isAlreadyAdded(String camCoordinates) {
    final exists = insertedSpeedcams.contains(camCoordinates);
    if (exists) {
      logger.printLogLine('Duplicate camera ignored: $camCoordinates');
    }
    return exists;
  }

  void triggerFreeFlow() {
    if (resume?.isResumed() ?? true) {
      updateSpeedcam('FREEFLOW');
      updateBarWidgetMeters('');
      updateCamRoad(reset: true);
      updateMaxSpeed(reset: true);
    }
  }

  void triggerSpeedCamUpdate({
    required String? roadName,
    required double distance,
    required dynamic camCoordinates,
    required String speedcam,
    required dynamic ccpNode,
    required dynamic linkedList,
    required dynamic tree,
    required double lastDistance,
    dynamic maxSpeed,
    bool predictive = false,
    String nextCamRoad = '',
    String nextCamDistance = '',
    int nextCamDistanceAsInt = 0,
    bool processNextCam = false,
  }) {
    if (resume?.isResumed() ?? true) {
      updateNextCam(
        process: processNextCam,
        road: processNextCam ? nextCamRoad : null,
        distance: processNextCam ? nextCamDistanceAsInt : null,
      );
    }
    if (distance >= 0 && distance <= 100) {
      camInProgress = true;
      if (lastDistance == -1 || lastDistance > 100) {
        if (distance < 50) {
          if (speedcam == 'fix') {
            voicePromptEvents.emit('FIX_NOW');
          } else if (speedcam == 'traffic') {
            voicePromptEvents.emit('TRAFFIC_NOW');
          } else if (speedcam == 'mobile') {
            if (!predictive) {
              voicePromptEvents.emit('MOBILE_NOW');
            } else {
              voicePromptEvents.emit('MOBILE_PREDICTIVE_NOW');
            }
          } else {
            voicePromptEvents.emit('DISTANCE_NOW');
          }
        } else {
          if (speedcam == 'fix') {
            voicePromptEvents.emit('FIX_100');
          } else if (speedcam == 'traffic') {
            voicePromptEvents.emit('TRAFFIC_100');
          } else if (speedcam == 'mobile') {
            if (!predictive) {
              voicePromptEvents.emit('MOBILE_100');
            } else {
              voicePromptEvents.emit('MOBILE_PREDICTIVE_100');
            }
          } else {
            voicePromptEvents.emit('DISTANCE_100');
          }
        }

        checkRoadName(linkedList, tree, camCoordinates);
        if (resume?.isResumed() ?? true) {
          updateBarWidgetMeters(distance);
          updateCamRoad(road: roadName);
          updateMaxSpeed(maxSpeed: maxSpeed);
          updateSpeedcam(speedcam);
        }
      } else {
        checkRoadName(linkedList, tree, camCoordinates);
        if (resume?.isResumed() ?? true) {
          updateBarWidgetMeters(distance);
          updateCamRoad(road: roadName);
          updateMaxSpeed(maxSpeed: maxSpeed);
          updateSpeedcam(speedcam);
        }
      }
      lastDistance = 100;
      itemQueue[camCoordinates]?[1] = false;
    } else if (distance > 100 && distance <= 300) {
      camInProgress = true;
      itemQueue[camCoordinates]?[1] = false;
      if (lastDistance == -1 || lastDistance > 300) {
        if (speedcam == 'fix') {
          voicePromptEvents.emit('FIX_300');
        } else if (speedcam == 'traffic') {
          voicePromptEvents.emit('TRAFFIC_300');
        } else if (speedcam == 'mobile') {
          if (!predictive) {
            voicePromptEvents.emit('MOBILE_300');
          } else {
            voicePromptEvents.emit('MOBILE_PREDICTIVE_300');
          }
        } else {
          voicePromptEvents.emit('DISTANCE_300');
        }

        checkRoadName(linkedList, tree, camCoordinates);
        if (resume?.isResumed() ?? true) {
          updateBarWidgetMeters(distance);
          updateCamRoad(road: roadName);
          updateMaxSpeed(maxSpeed: maxSpeed);
          updateSpeedcam(speedcam);
        }
      } else {
        if (lastDistance == 300) {
          checkRoadName(linkedList, tree, camCoordinates);
          if (resume?.isResumed() ?? true) {
            updateBarWidgetMeters(distance);
            updateCamRoad(road: roadName);
            updateMaxSpeed(maxSpeed: maxSpeed);
            updateSpeedcam(speedcam);
          }
        } else {
          camInProgress = false;
          triggerFreeFlow();
          itemQueue[camCoordinates]?[1] = 'to_be_stored';
        }
      }
      lastDistance = 300;
    } else if (distance > 300 && distance <= 500) {
      camInProgress = true;
      itemQueue[camCoordinates]?[1] = false;
      if (lastDistance == -1 || lastDistance > 500) {
        if (speedcam == 'fix') {
          voicePromptEvents.emit('FIX_500');
        } else if (speedcam == 'traffic') {
          voicePromptEvents.emit('TRAFFIC_500');
        } else if (speedcam == 'mobile') {
          if (!predictive) {
            voicePromptEvents.emit('MOBILE_500');
          } else {
            voicePromptEvents.emit('MOBILE_PREDICTIVE_500');
          }
        } else {
          voicePromptEvents.emit('DISTANCE_500');
        }

        checkRoadName(linkedList, tree, camCoordinates);
        if (resume?.isResumed() ?? true) {
          updateBarWidgetMeters(distance);
          updateCamRoad(road: roadName);
          updateMaxSpeed(maxSpeed: maxSpeed);
          updateSpeedcam(speedcam);
        }
      } else {
        if (lastDistance == 500) {
          checkRoadName(linkedList, tree, camCoordinates);
          if (resume?.isResumed() ?? true) {
            updateBarWidgetMeters(distance);
            updateCamRoad(road: roadName);
            updateMaxSpeed(maxSpeed: maxSpeed);
            updateSpeedcam(speedcam);
          }
        } else {
          camInProgress = false;
          triggerFreeFlow();
          itemQueue[camCoordinates]?[1] = 'to_be_stored';
        }
      }
      lastDistance = 500;
    } else if (distance > 500 && distance <= 1000) {
      camInProgress = true;
      itemQueue[camCoordinates]?[1] = false;
      if (lastDistance == -1 || lastDistance > 1000) {
        if (speedcam == 'fix') {
          voicePromptEvents.emit('FIX_1000');
        } else if (speedcam == 'traffic') {
          voicePromptEvents.emit('TRAFFIC_1000');
        } else if (speedcam == 'mobile') {
          if (!predictive) {
            voicePromptEvents.emit('MOBILE_1000');
          } else {
            voicePromptEvents.emit('MOBILE_PREDICTIVE_1000');
          }
        } else {
          voicePromptEvents.emit('DISTANCE_1000');
        }

        checkRoadName(linkedList, tree, camCoordinates);
        if (resume?.isResumed() ?? true) {
          updateBarWidgetMeters(distance);
          updateCamRoad(road: roadName);
          updateMaxSpeed(maxSpeed: maxSpeed);
          updateSpeedcam(speedcam);
        }
      } else {
        if (lastDistance == 1000) {
          checkRoadName(linkedList, tree, camCoordinates);
          if (resume?.isResumed() ?? true) {
            updateBarWidgetMeters(distance);
            updateCamRoad(road: roadName);
            updateMaxSpeed(maxSpeed: maxSpeed);
            updateSpeedcam(speedcam);
          }
        } else {
          camInProgress = false;
          triggerFreeFlow();
          itemQueue[camCoordinates]?[1] = 'to_be_stored';
        }
      }
      lastDistance = 1000;
    } else if (distance > 1000 && distance <= 1500) {
      camInProgress = true;
      itemQueue[camCoordinates]?[1] = false;
      if (lastDistance == -1 || lastDistance > 1001) {
        print('$speedcam speed cam ahead with distance ${distance.toInt()} m');
        voicePromptEvents.emit('CAMERA_AHEAD');
        if (resume?.isResumed() ?? true) {
          updateBarWidgetMeters(distance);
          updateSpeedcam('CAMERA_AHEAD');
        }
      } else {
        if (lastDistance == 1001) {
          camInProgress = false;
          if (resume?.isResumed() ?? true) {
            updateCamRoad(road: roadName);
            updateBarWidgetMeters(distance);
            updateSpeedcam('CAMERA_AHEAD');
          }
        } else {
          camInProgress = false;
          triggerFreeFlow();
          itemQueue[camCoordinates]?[1] = 'to_be_stored';
        }
      }
      lastDistance = 1001;
    } else {
      if (lastDistance == -1 && distance < maxAbsoluteDistance) {
        triggerFreeFlow();
        camInProgress = false;
        return;
      }
      print(
        '$speedcam speed cam OUTSIDE relevant radius -> distance ${distance.toInt()} m',
      );
      camInProgress = false;
      triggerFreeFlow();
      lastDistance = maxAbsoluteDistance;
      itemQueue[camCoordinates]?[1] = true;
    }

    // finally update attributes
    itemQueue[camCoordinates]?[0] = speedcam;
    itemQueue[camCoordinates]?[1] = itemQueue[camCoordinates]?[1];
    itemQueue[camCoordinates]?[2] = ccpNode;
    itemQueue[camCoordinates]?[3] = linkedList;
    itemQueue[camCoordinates]?[4] = tree;
    itemQueue[camCoordinates]?[5] = lastDistance;
    itemQueue[camCoordinates]?[8] = distance;
  }

  // tuple like return for sortPois
  ({dynamic item1, List<dynamic>? item2}) sortPois(
    List<List<dynamic>> camList,
  ) {
    if (camList.isNotEmpty) {
      camList.sort((a, b) => (a[1] as num).compareTo(b[1] as num));
      var attr = camList.first;
      return (item1: attr[0], item2: attr);
    }
    return (item1: null, item2: null);
  }

  void checkRoadName(dynamic linkedList, dynamic tree, dynamic camCoordinates) {
    if (linkedList == null || tree == null) return;
    try {
      itemQueue[camCoordinates]?[7];
    } catch (_) {
      print(
        'Check road name for speed cam with coords $camCoordinates failed. Speed cameras had been deleted already',
      );
      return;
    }

    if (itemQueue[camCoordinates]?[7] == null) {
      var nodeId = linkedList.matchNode([camCoordinates[1], camCoordinates[0]]);
      if (nodeId != null) {
        if (tree.containsKey(nodeId)) {
          var way = tree[nodeId];
          if (tree.hasRoadNameAttribute(way)) {
            var roadName = tree.getRoadNameValue(way);
            try {
              itemQueue[camCoordinates]?[7] = roadName;
            } catch (_) {}
          }
        }
      }
    }
  }

  // simple wrappers for UI/gateway updates ------------------------------
  void updateSpeedcam(String speedcam) {
    calculator.updateSpeedCam(speedcam);
  }

  void updateBarWidgetMeters(dynamic meter) {
    if (meter is num) {
      calculator.updateSpeedCamDistance(meter.toDouble());
    } else {
      calculator.updateSpeedCamDistance(null);
    }
  }

  void updateCamRoad({String? road, bool reset = false}) {
    if (reset) {
      calculator.updateCameraRoad(null);
    } else {
      calculator.updateCameraRoad(road);
    }
  }

  void updateMaxSpeed({dynamic maxSpeed, bool reset = false}) {
    if (reset || maxSpeed == null) {
      calculator.updateMaxspeed('');
    } else {
      calculator.updateMaxspeed(maxSpeed);
    }
  }

  void updateNextCam({
    required bool process,
    String? road,
    int? distance,
  }) {
    calculator.updateNextCamInfo(
      process: process,
      road: road,
      distance: distance,
    );
  }

  LatLng? get lastPosition => _lastPosition;

  // geodesic calculations -----------------------------------------------
  double checkBeelineDistance(List<double> pt1, List<double> pt2) {
    var lon1 = pt1[0];
    var lat1 = pt1[1];
    var lon2 = pt2[0];
    var lat2 = pt2[1];
    var radius = 6371; // km
    var dlat = _degToRad(lat2 - lat1);
    var dlon = _degToRad(lon2 - lon1);
    var a = pow(sin(dlat / 2), 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * pow(sin(dlon / 2), 2);
    var c = 2 * atan2(sqrt(a), sqrt(1 - a));
    var d = radius * c;
    return (d * 1000).toInt().toDouble();
  }

  double checkDistanceBetweenTwoPoints(dynamic pt1, dynamic pt2) {
    var R = 6373.0; // km
    try {
      var lat1 = _degToRad(double.parse(pt1[1].toString()));
      var lon1 = _degToRad(double.parse(pt1[0].toString()));
      var lat2 = _degToRad(double.parse(pt2[1].toString()));
      var lon2 = _degToRad(double.parse(pt2[0].toString()));
      var dlon = lon2 - lon1;
      var dlat = lat2 - lat1;
      var a =
          pow(sin(dlat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dlon / 2), 2);
      var c = 2 * atan2(sqrt(a), sqrt(1 - a));
      var distance = R * c;
      return double.parse((distance * 1000).toStringAsFixed(3));
    } catch (_) {
      return -1;
    }
  }

  List<int>? convertCamDirection(dynamic camDir) {
    if (camDir == null) return null;
    List<int> camDirs = [];
    try {
      camDirs.add(int.parse(camDir.toString()));
    } catch (_) {
      var parts = camDir.toString().split(';');
      for (var p in parts) {
        try {
          camDirs.add(int.parse(p));
        } catch (_) {}
      }
    }
    return camDirs.isEmpty ? null : camDirs;
  }

  bool insideRelevantAngle(dynamic cam, double distanceToCamera) {
    try {
      var entry = itemQueue[cam];
      if (entry == null) return false;
      var camDirection = entry[9];
      var camType = entry[0];
      if (distanceToCamera < emergencyAngleDistance) {
        print(
          "Emergency report triggered for Speed Camera '$camType' ($cam): Distance: $distanceToCamera m < $emergencyAngleDistance m",
        );
        return true;
      }
      if (ccpBearing != null && camDirection != null) {
        var directionCcp = calculateDirection(ccpBearing!);
        if (directionCcp == null) return true;
        var directions =
            camDirection.map((d) => calculateDirection(d as double)).toList();
        if (directions.contains(directionCcp)) {
          return true;
        } else {
          print(
            "Speed Camera '$camType' ($cam): CCP bearing angle: $ccpBearing, Expected camera angle: $camDirection",
          );
          return false;
        }
      }
    } catch (_) {
      return true;
    }
    return true;
  }

  double calculateAngle(List<double> pt1, List<double> pt2) {
    var lon1 = pt1[0], lat1 = pt1[1];
    var lon2 = pt2[0], lat2 = pt2[1];
    var xDiff = lon2 - lon1;
    var yDiff = lat2 - lat1;
    return (atan2(yDiff, xDiff) * (180 / pi)).abs();
  }

  bool cameraInsideCameraRectangle(dynamic cam) {
    final key = parseCamKey(cam);
    var xtile = calculator.longlat2tile(key[1], key[0], calculator.zoom)[0];
    var ytile = calculator.longlat2tile(key[1], key[0], calculator.zoom)[1];
    var rectangle = calculator.rectSpeedCamLookahead;
    if (rectangle == null) return true;
    return rectangle.pointInRect(xtile, ytile);
  }

  double calculateCameraRectangleRadius() {
    var rectangle = calculator.rectSpeedCamLookahead;
    if (rectangle == null) return 0;
    return calculator.calculateRectangleRadius(
      rectangle.rectHeight(),
      rectangle.rectWidth(),
    );
  }

  void deletePassedCameras() {
    var itemDict = Map.from(itemQueue);
    var cameraItems = [itemDict];
    for (var cameras in cameraItems) {
      for (var entry in cameras.entries.toList()) {
        var cam = entry.key;
        var camAttributes = entry.value;
        if (deleteCamerasOutsideLookaheadRectangle &&
            !cameraInsideCameraRectangle(cam)) {
          print(
            'Deleting obsolete camera: $cam (camera is outside current camera rectangle with radius ${calculateCameraRectangleRadius()} km)',
          );
          deleteObsoleteCamera(cam, camAttributes);
          final camera = parseCamKey(cam);
          MapPage.removeCameraMarker(camera[0], camera[1]);
        } else {
          if (camAttributes[2][0] == 'IGNORE' ||
              camAttributes[2][1] == 'IGNORE') {
            final key = parseCamKey(cam);
            var distance = checkDistanceBetweenTwoPoints(key, [
              longitude,
              latitude,
            ]);
            if (distance.abs() >= maxAbsoluteDistance) {
              print(
                'Deleting obsolete camera: $cam (max distance $maxAbsoluteDistance m < current distance ${distance.abs()} m)',
              );
              deleteObsoleteCamera(cam, camAttributes);
              final camera = parseCamKey(cam);
              MapPage.removeCameraMarker(camera[0], camera[1]);
            } else {
              if (camAttributes[6] > maxStorageTime) {
                if (camAttributes[11] == false) {
                  print(
                    'Deleting obsolete camera: $cam because of storage time (max: $maxStorageTime seconds, current: ${camAttributes[6]})',
                  );
                  deleteObsoleteCamera(cam, camAttributes);
                  final camera = parseCamKey(cam);
                  MapPage.removeCameraMarker(camera[0], camera[1]);
                } else {
                  print('Camera $cam is new. Ignore deletion');
                }
              }
            }
          } else {
            final key = parseCamKey(cam);
            var distance =
                checkDistanceBetweenTwoPoints(key, camAttributes[2]) -
                    checkDistanceBetweenTwoPoints([
                      longitude,
                      latitude,
                    ], camAttributes[2]);
            if (distance < 0 && distance.abs() >= maxAbsoluteDistance) {
              print(
                'Deleting obsolete camera: $cam (max distance $maxAbsoluteDistance m < current distance ${distance.abs()} m)',
              );
              deleteObsoleteCamera(cam, camAttributes);
              final camera = parseCamKey(cam);
              MapPage.removeCameraMarker(camera[0], camera[1]);
            } else {
              if (distance < 0 &&
                  camAttributes[5] == -1 &&
                  camAttributes[6] > maxStorageTime) {
                if (camAttributes[11] == false) {
                  print(
                    'Deleting obsolete camera: $cam because of storage time (max: $maxStorageTime seconds, current: ${camAttributes[6]})',
                  );
                  deleteObsoleteCamera(cam, camAttributes);
                  final camera = parseCamKey(cam);
                  MapPage.removeCameraMarker(camera[0], camera[1]);
                } else {
                  print('Camera $cam is new. Ignore deletion');
                }
              }
            }
          }
        }
      }
    }
  }

  void deleteObsoleteCamera(dynamic cam, List<dynamic> camAttributes) {
    try {
      itemQueue.remove(cam);
      startTimes.remove(cam);
      removeCachedCamera(cam);
      //updateCalculatorCams(camAttributes);
      if (itemQueueBackup.containsKey(cam)) {
        itemQueueBackup.remove(cam);
      }
    } catch (e) {
      print('Deleting obsolete camera: $cam failed! Error: $e');
    }
  }

  void updateCalculatorCams(List<dynamic> camAttributes) {
    if (calculator != null && calculator is RectangleCalculatorThread) {
      if (camAttributes[0] == 'fix' && calculator.fix_cams > 0) {
        calculator.fix_cams -= 1;
        calculator.updateFixCamCount(calculator.fix_cams);
      } else if (camAttributes[0] == 'traffic' && calculator.traffic_cams > 0) {
        calculator.traffic_cams -= 1;
        calculator.updateTrafficCamCount(calculator.traffic_cams);
      } else if (camAttributes[0] == 'distance' &&
          calculator.distance_cams > 0) {
        calculator.distance_cams -= 1;
        calculator.updateDistanceCamCount(calculator.distance_cams);
      } else if (camAttributes[0] == 'mobile' && calculator.mobile_cams > 0) {
        calculator.mobile_cams -= 1;
        calculator.updateMobileCamCount(calculator.mobile_cams);
      }
    }
  }

  String? calculateDirection(double bearing) {
    if (0 <= bearing && bearing <= 11) {
      return 'TOP-N';
    } else if (11 < bearing && bearing < 22) {
      return 'N';
    } else if (22 <= bearing && bearing < 45) {
      return 'NNO';
    } else if (45 <= bearing && bearing < 67) {
      return 'NO';
    } else if (67 <= bearing && bearing < 78) {
      return 'ONO';
    } else if (78 <= bearing && bearing <= 101) {
      return 'TOP-O';
    } else if (101 < bearing && bearing < 112) {
      return 'O';
    } else if (112 <= bearing && bearing < 135) {
      return 'OSO';
    } else if (135 <= bearing && bearing < 157) {
      return 'SO';
    } else if (157 <= bearing && bearing < 168) {
      return 'SSO';
    } else if (168 <= bearing && bearing < 191) {
      return 'TOP-S';
    } else if (191 <= bearing && bearing < 202) {
      return 'S';
    } else if (202 <= bearing && bearing < 225) {
      return 'SSW';
    } else if (225 <= bearing && bearing < 247) {
      return 'SW';
    } else if (247 <= bearing && bearing < 258) {
      return 'WSW';
    } else if (258 <= bearing && bearing < 281) {
      return 'TOP-W';
    } else if (281 <= bearing && bearing < 292) {
      return 'W';
    } else if (292 <= bearing && bearing < 315) {
      return 'WNW';
    } else if (315 <= bearing && bearing < 337) {
      return 'NW';
    } else if (337 <= bearing && bearing < 348) {
      return 'NNW';
    } else if (348 <= bearing && bearing < 355) {
      return 'N';
    } else if (355 <= bearing && bearing <= 360) {
      return 'TOP-N';
    }
    return null;
  }

  double _degToRad(double deg) => deg * (pi / 180.0);
}
