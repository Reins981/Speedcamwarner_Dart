import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:workspace/speed_cam_warner.dart';

import 'logger.dart';
import 'rect.dart';
import 'service_account.dart';
import 'rectangle_calculator.dart'
    show SpeedCameraEvent, RectangleCalculatorThread;
import 'thread_base.dart';
import 'gps_producer.dart';
import 'config.dart';
import 'voice_prompt_events.dart';

/// Representation of a user contributed camera.
class UserCamera {
  final int id;
  final String? name;
  final String? roadName;
  final double lon;
  final double lat;

  const UserCamera(this.id, this.name, this.roadName, this.lon, this.lat);
}

/// Port of the legacy Python ``POIReader`` implementation from ``SQL.py``.
///
/// The class is responsible for loading speed‑camera data from the bundled
/// SQLite database as well as periodically updating user contributed POIs from
/// the cloud.  Many collaborators are injected as ``dynamic`` because their
/// Dart ports are outside the scope of this change.  The behaviour mirrors the
/// original implementation as closely as possible but some heavy lifting
/// (SQLite access, Google Drive interaction) remains to be implemented in
/// dedicated modules.
class POIReader extends Logger {
  final GpsProducer gpsProducer;
  final RectangleCalculatorThread calculator;
  final MapQueue<dynamic> mapQueue;
  final VoicePromptEvents voicePromptEvents;
  final StreamController<String>? logViewer;

  /// Global members translated from the Python implementation
  sqlite.Database? connection;
  List<List<dynamic>>? poiRawData;
  String? lastValidDrivingDirection;
  double? lastValidLongitude;
  double? lastValidLatitude;
  final List<List<double>> poisConvertedFix = [];
  final List<List<double>> poisConvertedMobile = [];
  final List<List<double>> resultPoisFix = [];
  final List<List<double>> resultPoisMobile = [];
  final Map<String, List<dynamic>> speedCamDict = {};
  final List<Map<String, List<dynamic>>> speedCamList = [];
  final Map<String, List<dynamic>> speedCamDictDb = {};
  final List<Map<String, List<dynamic>>> speedCamListDb = [];

  /// Timers
  Timer? timer1;
  Timer? timer2;
  Timer? timer3;

  /// OSM layer zoom and rectangle
  final int zoom = 17;
  Rect? poiRect;

  bool _initialDownloadFinished = false;

  bool get initialDownloadFinished => _initialDownloadFinished;

  /// Configuration values (seconds)
  late int uTimeFromCloud;
  late int initTimeFromCloud;
  late int uTimeFromDb;
  late int poiDistance;
  double maxAbsoluteDistance = 300000; // meters

  POIReader(
    this.gpsProducer,
    this.calculator,
    this.mapQueue,
    this.voicePromptEvents,
    this.logViewer,
  ) : super('POIReader', logViewer: logViewer) {
    _setConfigs();
    _process();
  }

  /// Mirror the configuration setup from the Python version.
  void _setConfigs() {
    // Cloud cyclic update time in seconds (runs every x seconds)
    uTimeFromCloud =
        (AppConfig.get<num>('sql.u_time_from_cloud') ?? 60).toInt();
    // Initial update time from cloud (one time operation)
    initTimeFromCloud =
        (AppConfig.get<num>('sql.init_time_from_cloud') ?? 10).toInt();
    // POIs from database update time in seconds (one shot after x seconds)
    uTimeFromDb = (AppConfig.get<num>('sql.u_time_from_db') ?? 30).toInt();
    poiDistance = (AppConfig.get<num>('main.poi_distance') ?? 50).toInt();
    maxAbsoluteDistance =
        (AppConfig.get<num>('speedCamWarner.max_absolute_distance') ??
                maxAbsoluteDistance)
            .toDouble();
    calculator.rectangle_periphery_poi_reader = poiDistance.toDouble();
  }

  /// Cancel running timers – called from main UI thread.
  void stopTimer() {
    timer1?.cancel();
    timer2?.cancel();
    timer3?.cancel();
  }

  /// Process initial loading and schedule cyclic tasks.
  void _process() {
    _openConnection();
    _execute();
    _convertCamMortonCodes();
    _updatePoisFromDb();
    timer1 = Timer.periodic(
      Duration(seconds: uTimeFromDb),
      (_) => _updatePoisFromDb(),
    );

    // Schedule a one-shot update from the cloud and a periodic refresher.
    timer2 = Timer.periodic(
      Duration(seconds: uTimeFromCloud),
      (_) => unawaited(_updatePoisFromCloud()),
    );
    timer3 = Timer(
      Duration(seconds: initTimeFromCloud),
      () => unawaited(_updatePoisFromCloud()),
    );
  }

  /// Open the bundled SQLite database using the ``sqlite3`` package.
  void _openConnection() {
    final dbPath = File('python/poidata.db3');
    if (!dbPath.existsSync()) {
      connection = null;
      return;
    }
    connection = sqlite.sqlite3.open(dbPath.path);
  }

  /// Execute the database query to load POI data.
  void _execute() {
    if (connection != null) {
      final result = connection!.select(
        'SELECT a.catId, a.mortonCode from pPoiCategoryTable c '
        'inner join pPoiAddressTable a on c.catId = a.catId and c.catId between ? and ?',
        [2014, 2015],
      );
      poiRawData = result
          .map((row) => [row['catId'] as int, row['mortonCode'] as int])
          .toList();
    } else {
      printLogLine('Could not open database poidata.db3', logLevel: 'WARNING');
      poiRawData = null;
    }
  }

  /// Convert morton codes to longitude/latitude pairs and populate the
  /// ``poisConvertedFix`` and ``poisConvertedMobile`` lists.
  void _convertCamMortonCodes() {
    if (poiRawData == null) return;

    for (final camTuple in poiRawData!) {
      final x = _decodeMorton2X(camTuple[1] as int);
      final y = _decodeMorton2Y(camTuple[1] as int);
      final longLat = calculator.tile2longlat(x.toDouble(), y.toDouble(), 17);
      final longitude = longLat[0];
      final latitude = longLat[1];

      if (camTuple[0] == 2014) {
        poisConvertedFix.add([longitude, latitude]);
      } else if (camTuple[0] == 2015) {
        poisConvertedMobile.add([longitude, latitude]);
      }
    }

    printLogLine(' Number of fix cams: ${poisConvertedFix.length}');
    printLogLine(' Number of mobile cams: ${poisConvertedMobile.length}');
    printLogLine(
      '#######################################################################',
    );
  }

  // Inverse of Part1By1 – "delete" all odd-indexed bits
  int _compact1By1(int x) {
    x &= 0x55555555;
    x = (x ^ (x >> 1)) & 0x33333333;
    x = (x ^ (x >> 2)) & 0x0f0f0f0f;
    x = (x ^ (x >> 4)) & 0x00ff00ff;
    x = (x ^ (x >> 8)) & 0x0000ffff;
    return x;
  }

  // Inverse of Part1By2 – "delete" all bits not at positions divisible by 3
  int _compact1By2(int x) {
    x &= 0x09249249;
    x = (x ^ (x >> 2)) & 0x030c30c3;
    x = (x ^ (x >> 4)) & 0x0300f00f;
    x = (x ^ (x >> 8)) & 0xff0000ff;
    x = (x ^ (x >> 16)) & 0x000003ff;
    return x;
  }

  int _decodeMorton2X(int code) => _compact1By1(code >> 0);
  int _decodeMorton2Y(int code) => _compact1By1(code >> 1);

  void _printConvertedCodes() {
    printLogLine(' Fix cameras:');
    printLogLine(poisConvertedFix.toString());
    printLogLine(' Mobile cameras:');
    printLogLine(poisConvertedMobile.toString());
  }

  /// Send camera information to the speed‑camera queue for further processing.
  void _propagateCamera(
      String? roadName, double longitude, double latitude, String cameraType,
      {List<double>? ccpPair}) {
    printLogLine(
      'Propagating $cameraType camera (${longitude.toStringAsFixed(5)}, ${latitude.toStringAsFixed(5)})',
    );

    if (ccpPair != null) {
      var distance = SpeedCamWarner.checkDistanceBetweenTwoPoints(
          ccpPair, [longitude, latitude]);

      if (distance > maxAbsoluteDistance) {
        printLogLine(
          '$cameraType camera is too far away from current position (${distance.toStringAsFixed(0)} m), ignoring it',
          logLevel: 'WARNING',
        );
        return;
      }
    }

    unawaited(
      calculator.updateSpeedCams([
        SpeedCameraEvent(
          latitude: latitude,
          longitude: longitude,
          fixed: cameraType == 'fix_cam',
          traffic: cameraType == 'traffic_cam',
          distance: cameraType == 'distance_cam',
          mobile: cameraType == 'mobile_cam',
          name: roadName ?? '',
        ),
      ], mapUpdate: true),
    );
  }

  /// Prepare an entry for the OSM wrapper (map display of cameras).
  void _prepareCameraForOsmWrapper(
    String cameraKey,
    double lon,
    double lat, {
    String? name,
    String cameraSource = 'cloud',
  }) {
    final entry = [lat, lon, lat, lon, true, null, null, name ?? '---'];
    if (cameraSource == 'cloud') {
      speedCamDict[cameraKey] = entry;
    } else {
      speedCamDictDb[cameraKey] = entry;
    }
  }

  void _cleanupSpeedCams() {
    final cameras = [speedCamList, speedCamListDb];
    for (final cameraList in cameras) {
      if (cameraList.length >= 100) {
        printLogLine(
          ' Limit of speed camera list (100) reached! Deleting all speed cameras from source list',
          logLevel: 'WARNING',
        );
        cameraList.clear();
      }
    }
  }

  void _updateMapQueue() {
    mapQueue.produce('UPDATE');
  }

  void _updateSpeedCamsCloud(List<Map<String, List<dynamic>>> speedCams) {
    mapQueue.produceCloud(speedCams);
  }

  void _updateSpeedCamsDb(List<Map<String, List<dynamic>>> speedCams) {
    mapQueue.produceDb(speedCams);
  }

  void _updateOsmWrapper({String cameraSource = 'cloud'}) {
    final processingDict =
        cameraSource == 'cloud' ? speedCamDict : speedCamDictDb;
    final processingList =
        cameraSource == 'cloud' ? speedCamList : speedCamListDb;

    if (processingDict.isNotEmpty) {
      processingList.add(Map<String, List<dynamic>>.from(processingDict));
    }

    if (cameraSource == 'cloud') {
      _updateSpeedCamsCloud(processingList);
    } else {
      _updateSpeedCamsDb(processingList);
    }
    _updateMapQueue();
    _cleanupSpeedCams();
  }

  /// Parse and process user cameras from the downloaded JSON file.
  void _processPoisFromCloud() {
    printLogLine("Processing POI's from cloud..");

    String? direction = gpsProducer.get_direction();
    var lonLat = gpsProducer.get_lon_lat();
    double longitude = lonLat[0];
    double latitude = lonLat[1];
    List<double> ccpPair = [longitude, latitude];

    if (direction == '-' || direction == null) {
      printLogLine(' Waiting for valid direction once');
      return;
    }

    final file = File(ServiceAccount.fileName);
    if (!file.existsSync()) {
      printLogLine(
        "Processing POI's from cloud failed: ${ServiceAccount.fileName} not found!",
        logLevel: 'ERROR',
      );
      voicePromptEvents.emit('POI_FAILED');
      return;
    }

    final userPois = jsonDecode(file.readAsStringSync());
    if (!(userPois is Map) || !userPois.containsKey('cameras')) {
      printLogLine(
        "Processing POI's from cloud failed: No POI's to process in ${ServiceAccount.fileName}",
        logLevel: 'WARNING',
      );
      voicePromptEvents.emit('POI_FAILED');
      return;
    }

    final cameras = userPois['cameras'] as List<dynamic>;
    final numCameras = cameras.length;
    printLogLine('Found $numCameras cameras from cloud!');
    calculator.updateInfoPage('POI_CAMERAS:$numCameras');
    _initialDownloadFinished = true;

    var camId = 200000;
    for (final camera in cameras) {
      try {
        final name = camera['name'];
        final roadName = camera['road_name'];
        final lat = camera['coordinates'][0]['latitude'];
        final lon = camera['coordinates'][0]['longitude'];

        final userCam = UserCamera(
          camId,
          name,
          roadName,
          (lon as num).toDouble(),
          (lat as num).toDouble(),
        );

        printLogLine(
          'Adding and propagating camera from cloud (${userCam.name}, ${userCam.lat}, ${userCam.lon})',
        );
        _prepareCameraForOsmWrapper(
          'MOBILE$camId',
          userCam.lon,
          userCam.lat,
          name: userCam.name,
        );
        _updateOsmWrapper();
        _propagateCamera(
            userCam.roadName, userCam.lon, userCam.lat, 'mobile_cam',
            ccpPair: ccpPair);
        camId += 1;
      } catch (_) {
        printLogLine(
          'Ignore adding camera $camera from cloud because of missing attributes',
          logLevel: 'WARNING',
        );
      }
    }
  }

  /// Download latest POIs from Google Drive via the ``ServiceAccount`` helper.
  Future<void> _updatePoisFromCloud() async {
    printLogLine("Updating POI's from cloud ..");
    try {
      final driveClient = await ServiceAccount.buildDriveFromCredentials();
      if (driveClient == null) {
        printLogLine(
          'Updating cameras (file_id: ${ServiceAccount.fileId}) from service account failed! (NO_AUTH_CLIENT)',
          logLevel: 'ERROR',
        );
        return;
      }
      final status = await ServiceAccount.downloadFileFromGoogleDrive(
        ServiceAccount.fileId,
        driveClient,
      );
      if (status != 'success') {
        printLogLine(
          'Updating cameras (file_id: ${ServiceAccount.fileId}) from service account failed! ($status)',
          logLevel: 'ERROR',
        );
      } else {
        printLogLine(
          'Updating cameras (file_id: ${ServiceAccount.fileId}) from service account success!',
        );
        _processPoisFromCloud();
      }
    } catch (e) {
      printLogLine(
        'Updating cameras (file_id: ${ServiceAccount.fileId}) from service account failed! ($e)',
        logLevel: 'ERROR',
      );
    }
  }

  /// Update POIs from the bundled sqlite database based on the current driving
  /// direction and GPS position.
  void _updatePoisFromDb() {
    printLogLine("Updating POI's from database ..");

    resultPoisFix.clear();
    resultPoisMobile.clear();

    poiRect?.deleteRect();

    String? direction = gpsProducer.get_direction();
    var lonLat = gpsProducer.get_lon_lat();
    double longitude = lonLat[0];
    double latitude = lonLat[1];

    if (direction == '-' || direction == null) {
      if (lastValidDrivingDirection != null &&
          lastValidLongitude != null &&
          lastValidLatitude != null) {
        direction = lastValidDrivingDirection;
        longitude = lastValidLongitude!;
        latitude = lastValidLatitude!;
      } else {
        printLogLine(' Waiting for valid direction once');
        return;
      }
    } else {
      lastValidDrivingDirection = direction;
      lastValidLongitude = longitude;
      lastValidLatitude = latitude;
    }

    printLogLine(' Updating Speed Cam Warner Thread');
    final tiles = calculator.longlat2tile(latitude, longitude, zoom);
    final xtile = tiles[0];
    final ytile = tiles[1];

    final polygon = calculator.createGeoJsonTilePolygon(
      direction!,
      zoom,
      xtile,
      ytile,
      calculator.rectangle_periphery_poi_reader,
    );

    final lonMin = polygon[0];
    final latMin = polygon[1];
    final lonMax = polygon[2];
    final latMax = polygon[3];

    final pt1 = calculator.longlat2tile(latMin, lonMin, zoom);
    final pt2 = calculator.longlat2tile(latMax, lonMax, zoom);
    poiRect = calculator.calculate_rectangle_border(pt1, pt2);
    poiRect?.setRectangleIdent(direction);
    poiRect?.setRectangleString('POIRECT');

    final rectangleRadius = calculator.calculate_rectangle_radius(
      poiRect!.rectHeight(),
      poiRect!.rectWidth(),
    );
    printLogLine(' rectangle POI radius $rectangleRadius');
    calculator.update_cam_radius(rectangleRadius);

    for (final camera in poisConvertedFix) {
      final longitudeCam = camera[0];
      final latitudeCam = camera[1];
      final camTiles = calculator.longlat2tile(latitudeCam, longitudeCam, zoom);
      if (poiRect!.pointInRect(camTiles[0], camTiles[1])) {
        printLogLine(' Found a fix speed cam');
        resultPoisFix.add(camera);
      }
    }

    for (final camera in poisConvertedMobile) {
      final longitudeCam = camera[0];
      final latitudeCam = camera[1];
      final camTiles = calculator.longlat2tile(latitudeCam, longitudeCam, zoom);
      if (poiRect!.pointInRect(camTiles[0], camTiles[1])) {
        printLogLine(' Found a mobile speed cam');
        resultPoisMobile.add(camera);
      }
    }

    printLogLine(
      ' fix cameras: ${resultPoisFix.length}, mobile cameras ${resultPoisMobile.length}',
    );
    calculator.updateInfoPage(
      'POI_FIX:${resultPoisFix.length};POI_MOBILE:${resultPoisMobile.length}',
    );

    for (var i = 0; i < resultPoisFix.length; i++) {
      final camera = resultPoisFix[i];
      final longitudeCam = camera[0];
      final latitudeCam = camera[1];
      printLogLine(
        'Adding and propagating fix camera from db ($longitudeCam, $latitudeCam)',
      );
      _propagateCamera(null, longitudeCam, latitudeCam, 'fix_cam');
      _prepareCameraForOsmWrapper(
        'FIX_DB$i',
        longitudeCam,
        latitudeCam,
        cameraSource: 'db',
      );
    }

    for (var i = 0; i < resultPoisMobile.length; i++) {
      final camera = resultPoisMobile[i];
      final longitudeCam = camera[0];
      final latitudeCam = camera[1];
      printLogLine(
        'Adding and propagating mobile camera from db ($longitudeCam, $latitudeCam)',
      );
      _propagateCamera(null, longitudeCam, latitudeCam, 'mobile_cam');
      _prepareCameraForOsmWrapper(
        'MOBILE_DB$i',
        longitudeCam,
        latitudeCam,
        cameraSource: 'db',
      );
    }

    // Inform the OSM wrapper about cameras originating from the database
    _updateOsmWrapper(cameraSource: 'db');
  }
}
