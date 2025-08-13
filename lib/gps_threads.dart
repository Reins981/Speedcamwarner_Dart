import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart' as xml;

import 'gps_test_data_generator.dart';
import 'config.dart';

class Logger {
  final String name;
  Logger(this.name);

  void printLogLine(String message, {String logLevel = 'INFO'}) {
    // ignore: avoid_print
    print('[' + name + '][' + logLevel + '] ' + message);
  }
}

class StoppableThread {
  bool _terminated = false;
  bool get terminated => _terminated;
  void stop() {
    _terminated = true;
  }
}

class GPSConsumerThread extends StoppableThread {
  final dynamic mainApp;
  final dynamic resume;
  final dynamic cv;
  final dynamic gpsqueue;
  final dynamic cond;
  final Logger logger;

  // Notifiers that allow a Flutter UI to react to GPS updates without any
  // Kivy widgets. `speed` publishes the current speed in km/h, `bearingText`
  // holds the last bearing string and `gpsAccuracy` forwards accuracy updates.
  final ValueNotifier<double> speed = ValueNotifier<double>(0);
  final ValueNotifier<String> bearingText = ValueNotifier<String>('');
  final ValueNotifier<String> gpsAccuracy = ValueNotifier<String>('');

  bool displayMiles = false;

  GPSConsumerThread(
    this.mainApp,
    this.resume,
    this.cv,
    this.gpsqueue,
    this.cond, {
    Logger? logViewer,
  }) : logger = logViewer ?? Logger('GPSConsumerThread') {
    setConfigs();
  }

  void setConfigs() {
    displayMiles =
        AppConfig.get<bool>('gpsConsumer.display_miles') ?? displayMiles;
  }

  void run() {
    while (!(cond?.terminate ?? false)) {
      if (mainApp?.runInBackGround == true) {
        mainApp?.mainEvent?.wait();
      }
      if (!(resume?.isResumed() ?? false)) {
        gpsqueue?.clearGpsqueue(cv);
      } else {
        process();
      }
    }
    logger.printLogLine('${runtimeType} terminating');
    gpsqueue?.clearGpsqueue(cv);
    stop();
  }

  void speedUpdate(double key) {
    var value = displayMiles ? key / 1.609344 : key;
    speed.value = value;
  }

  void process() {
    try {
      var gpsData = gpsqueue?.consume(cv);
      cv?.release();

      gpsData?.forEach((key, value) {
        if (value == 3) {
          if (key == '---.-' || key == '...') {
            clearAll();
          } else {
            double floatKey = double.tryParse('$key') ?? 0.0;
            speedUpdate(floatKey);
          }
        } else if (value == 4) {
          bearingText.value = key;
        } else if (value == 5) {
          gpsAccuracy.value = key;
        } else if (value == 1) {
          logger.printLogLine('Exit item received');
        } else {
          logger.printLogLine('Invalid value $value received!');
        }
      });
    } catch (e) {
      logger.printLogLine('Error processing GPS data: $e');
    }
  }

  void clearAll() {
    speed.value = 0;
    bearingText.value = '';
    gpsAccuracy.value = '';
  }
}

class GPSThread extends StoppableThread {
  static int gpsInaccuracyCounter = 0;

  final dynamic mainApp;
  final dynamic g;
  final dynamic cv;
  final dynamic cvVector;
  final dynamic cvAverageAngle;
  final dynamic voicePromptQueue;
  final dynamic ms;
  final dynamic vdata;
  final dynamic gpsqueue;
  final dynamic averageAngleQueue;
  final dynamic cvMap;
  final dynamic mapQueue;
  final dynamic osmWrapper;
  final dynamic cvCurrentspeed;
  final dynamic currentspeedQueue;
  final dynamic cvGpsData;
  final dynamic gpsDataQueue;
  final dynamic cvSpeedcam;
  final dynamic speedCamQueue;
  final dynamic calculator;
  final dynamic cond;
  final Logger logger;

  bool startup = true;
  bool firstOfflineCall = true;
  bool offState = false;
  bool onState = false;
  bool inProgress = false;
  bool isFilled = false;
  bool dayUpdateDone = false;
  bool nightUpdateDone = false;
  bool mapThreadStarted = false;
  double? latitude;
  double? longitude;
  double? latitudeBot;
  double? longitudeBot;
  double? accuracy;
  double? lastBearing;
  List<double> currentBearings = [];
  String? currDrivingDirection;
  double lastSpeed = 0;
  bool triggerSpeedCorrection = false;
  List<Map<String, dynamic>> routeData = [];
  List<Map<String, dynamic>> gpsData = [];
  Iterator<Map<String, dynamic>>? gpsDataIterator;

  // config items
  bool gpsTestData = false;
  int maxGpsEntries = 0;
  String gpxFile = '';
  double gpsTreshold = 40;
  int gpsInaccuracyTreshold = 4;
  bool recording = false;

  GPSThread(
      this.mainApp,
      this.g,
      this.cv,
      this.cvVector,
      this.cvAverageAngle,
      this.voicePromptQueue,
      this.ms,
      this.vdata,
      this.gpsqueue,
      this.averageAngleQueue,
      this.cvMap,
      this.mapQueue,
      this.osmWrapper,
      this.cvCurrentspeed,
      this.currentspeedQueue,
      this.cvGpsData,
      this.gpsDataQueue,
      this.cvSpeedcam,
      this.speedCamQueue,
      this.calculator,
      this.cond,
      {Logger? logViewer})
      : logger = logViewer ?? Logger('GPSThread') {
    setConfigs();
  }

  void setConfigs() {
    gpsTestData = AppConfig.get<bool>('gpsThread.gps_test_data') ?? true;
    maxGpsEntries =
        (AppConfig.get<num>('gpsThread.max_gps_entries') ?? 50000).toInt();
    gpxFile = AppConfig.get<String>('gpsThread.gpx_file') ??
        'python/gpx/Weekend_Karntner_5SeenTour.gpx';
    gpsTreshold =
        (AppConfig.get<num>('gpsThread.gps_treshold') ?? 40).toDouble();
    gpsInaccuracyTreshold =
        (AppConfig.get<num>('gpsThread.gps_inaccuracy_treshold') ?? 4)
            .toInt();
    recording = AppConfig.get<bool>('gpsThread.recording') ?? false;
    if (gpsTestData) {
      loadRouteData();
    }
  }

  void startRecording() {
    recording = true;
    routeData = [];
    logger.printLogLine('Route recording started');
  }

  void stopRecording() {
    recording = false;
    saveRouteData();
    logger.printLogLine('Route recording stopped');
  }

  void loadRouteData() {
    gpsTestData = true;
    recording = false;
    try {
      final file = File(gpxFile);
      if (!file.existsSync()) {
        logger.printLogLine('Route data file <$gpxFile> not found!!!');
        gpsTestData = false;
        return;
      }
      final document =
          xml.XmlDocument.parse(file.readAsStringSync());
      final points = document.findAllElements('trkpt');
      final routePoints = points.isNotEmpty
          ? points
          : document.findAllElements('rtept');
      gpsData = routePoints.map((pt) {
        final lat = double.tryParse(pt.getAttribute('lat') ?? '0') ?? 0;
        final lon = double.tryParse(pt.getAttribute('lon') ?? '0') ?? 0;
        return {
          'data': {
            'gps': {
              'accuracy': 5,
              'latitude': lat,
              'longitude': lon,
              'speed': 0,
              'bearing': 0,
            }
          },
          'name': 'location'
        };
      }).toList();
      gpsDataIterator = gpsData.iterator;
    } catch (e) {
      logger.printLogLine('Error loading route data: $e');
      gpsTestData = false;
    }
  }

  void saveRouteData() {
    if (routeData.isEmpty) {
      logger.printLogLine('No route data to save', logLevel: 'WARNING');
      return;
    }
    logger.printLogLine('Saving route data to GPX file', logLevel: 'WARNING');
    final builder = xml.XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('gpx', nest: () {
      builder.element('trk', nest: () {
        builder.element('trkseg', nest: () {
          for (final point in routeData) {
            final lat = point['latitude'];
            final lon = point['longitude'];
            final speed = point['speed'];
            final timestamp = DateTime.fromMillisecondsSinceEpoch(
                (point['timestamp'] * 1000).toInt(),
                isUtc: true);
            builder.element('trkpt',
                attributes: {'lat': '$lat', 'lon': '$lon'}, nest: () {
              builder.element('time',
                  nest: timestamp.toUtc().toIso8601String());
              builder.element('speed', nest: '$speed');
            });
          }
        });
      });
    });
    final document = builder.buildDocument();
    final destinationPath = 'python/gpx/route_data.gpx';
    File(destinationPath).writeAsStringSync(
        document.toXmlString(pretty: true));
    logger.printLogLine('Route data saved to GPX file', logLevel: 'WARNING');
  }

  void run() {
    while (!(cond?.terminate ?? false)) {
      if (mainApp?.runInBackGround == true) {
        mainApp?.mainEvent?.wait();
      }
      var status = process();
      if (status == 'EXIT') {
        break;
      }
    }
    voicePromptQueue?.produceGpsSignal('EXIT_APPLICATION');
    gpsqueue?.produce(cv, {'EXIT': 1});
    vdata?.setVectorData(
        cvVector, 'vector_data', 0.0, 0.0, 0.0, 0.0, '-', 'EXIT', 0);
    produceBearingSet(0.002);
    mapQueue?.produce(cvMap, 'EXIT');
    startup = true;
    firstOfflineCall = true;
    logger.printLogLine('${runtimeType} terminating');
    stop();
  }

  dynamic process() {
    var gpsAccuracy = 'OFF';

    if (startup) {
      vdata?.setVectorData(cvVector, 'vector_data', 0.0, 0.0, 0.0, 0.0,
          '-', 'INIT', 0);
      ms?.updateGui?.call();
      startup = false;
      sleep(const Duration(milliseconds: 300));
    }

    Map<String, dynamic>? event;
    if (gpsTestData) {
      if (gpsDataIterator != null && gpsDataIterator!.moveNext()) {
        event = gpsDataIterator!.current;
        sleep(const Duration(milliseconds: 1300));
      }
    } else {
      var item = gpsDataQueue?.consume(cvGpsData);
      cvGpsData?.release?.call();
      if (item != null && item['EXIT'] != null) {
        return 'EXIT';
      }
      event = item != null ? item['event'] : null;
      var gpsStatus = item != null ? item['status'] : null;
      if (gpsStatus != null &&
          gpsStatus != 'available' &&
          gpsStatus != 'provider-enabled') {
        processOffroute(gpsAccuracy);
      }
    }

    if (event != null) {
      inProgress = false;
      var gps = event['data']?['gps'];
      if (gps != null && gps['accuracy'] != null) {
        var accuracyVal = gps['accuracy'];
        if (accuracyVal is num && accuracyVal.toInt() <= gpsTreshold) {
          bool successCoords = false;
          double? speedVector;
          double? speed;
          double? lon;
          double? lat;
          if (gps['speed'] != null) {
            speed = ((gps['speed'] as num) * 3.6).toDouble();
            speedVector = (gps['speed'] as num).toDouble();
          }
          if (gps['latitude'] != null && gps['longitude'] != null) {
            lat = (gps['latitude'] as num).toDouble();
            lon = (gps['longitude'] as num).toDouble();
            successCoords = true;
            if (recording) {
              logger.printLogLine(
                  'Recording route data: $lat, $lon',
                  logLevel: 'WARNING');
              routeData.add({
                'latitude': lat,
                'longitude': lon,
                'speed': speed,
                'timestamp': DateTime.now().millisecondsSinceEpoch / 1000
              });
            }
          }
          if (speed == null || !successCoords) {
            logger.printLogLine(
                'Could not retrieve speed or coordinates from event!. Skipping..',
                logLevel: 'WARNING');
            return null;
          }
          callbackGps(lon!, lat!);
          var correctedSpeed = correctSpeed(speed);
          if (correctedSpeed != 'DISMISS') {
            gpsqueue?.produce(cv, {correctedSpeed: 3});
            currentspeedQueue?.produce(
                cvCurrentspeed, (correctedSpeed as double).round());
          } else {
            logger.printLogLine(
                'Speed dismissed: Ignore Current Speed Queue Update');
          }
          gpsqueue?.produce(
              cv, {accuracyVal.toStringAsFixed(1): 5});
          var dirBear = calculateDirection(event);
          var direction = dirBear?['direction'];
          var bearing = dirBear?['bearing'];
          if (direction == null) {
            logger.printLogLine(
                'Could not calculate direction from event!. Skipping..',
                logLevel: 'WARNING');
            return null;
          }
          if (speedVector != null && speedVector > 0) {
            vdata?.setVectorData(
                cvVector,
                'vector_data',
                lon,
                lat,
                speedVector,
                bearing,
                direction,
                'CALCULATE',
                accuracyVal.toInt());
            speedCamQueue?.produce(cvSpeedcam, {
              'ccp': (lon, lat),
              'fix_cam': (false, 0, 0),
              'traffic_cam': (false, 0, 0),
              'distance_cam': (false, 0, 0),
              'mobile_cam': (false, 0, 0),
              'ccp_node': (null, null),
              'list_tree': (null, null),
              'stable_ccp': null,
              'bearing': bearing
            });
          }
          gpsqueue?.produce(cv, {'$bearing $direction': 4});
          produceBearingSet(bearing);
          setAccuracy(accuracyVal.toDouble());

          osmWrapper?.osmUpdateHeading(direction);
          osmWrapper?.osmUpdateBearing((bearing as num).toInt());
          osmWrapper?.osmUpdateCenter(lat, lon);
          osmWrapper?.osmUpdateAccuracy(accuracy);
          osmDataIsFilled();
          updateMapQueue();
        } else {
          gpsAccuracy = (accuracyVal is num)
              ? accuracyVal.toStringAsFixed(1)
              : '$accuracyVal';
          processOffroute(gpsAccuracy);
        }
      }
    }
    return null;
  }

  void processOffroute(dynamic gpsAccuracy) {
    if (alreadyOff()) {
      // nothing
    } else {
      if (gpsAccuracy != 'OFF' &&
          !firstOfflineCall &&
          gpsInaccuracyCounter <= gpsInaccuracyTreshold) {
        gpsInaccuracyCounter += 1;
        logger.printLogLine(
            'Processing inaccurate GPS signal number ($gpsInaccuracyCounter)');
        gpsqueue?.produce(cv, {'...': 5});
        gpsqueue?.produce(cv, {'...': 3});
        inProgress = true;
        return;
      }
      gpsInaccuracyCounter = 0;
      gpsqueue?.clearGpsqueue(cv);
      logger.printLogLine('GPS status is $gpsAccuracy');
      if (gpsAccuracy != 'OFF') {
        voicePromptQueue?.produceGpsSignal('GPS_LOW');
      } else {
        voicePromptQueue?.produceGpsSignal('GPS_OFF');
      }
      g?.offState?.call();
      gpsqueue?.produce(cv, {'---.-': 3});
      offState = true;
      onState = false;
      inProgress = false;
      gpsqueue?.produce(cv, {gpsAccuracy: 5});
      resetOsmDataState();
    }
    if (firstOfflineCall) {
      firstOfflineCall = false;
    }
    vdata?.setVectorData(cvVector, 'vector_data', 0.0, 0.0, 0.0, 0.0,
        '-', 'OFFLINE', 0);
    averageAngleQueue?.clearAverageAngleData(cvAverageAngle);
  }

  void callbackGps(double lon, double lat) {
    setLonLat(lat, lon);
    setLonLatBot(lat, lon);
    gpsInaccuracyCounter = 0;
    if (!alreadyOn()) {
      logger.printLogLine('GPS status is ON');
      voicePromptQueue?.produceGpsSignal('GPS_ON');
      calculator?.updateMaxspeed('');
      g?.onState?.call();
      onState = true;
      offState = false;
    }
  }

  dynamic correctSpeed(double speed) {
    if (speed > 0) {
      lastSpeed = speed;
      triggerSpeedCorrection = true;
    }
    if (speed == 0 && triggerSpeedCorrection) {
      var corrected = lastSpeed > 0 ? lastSpeed : 'DISMISS';
      logger.printLogLine('Speed value corrected to $corrected');
      triggerSpeedCorrection = false;
      return corrected;
    } else if (speed == 0 && !triggerSpeedCorrection) {
      triggerSpeedCorrection = true;
      lastSpeed = 0;
    }
    return speed;
  }

  void updateMapQueue() {
    if (mapThreadStarted) {
      mapQueue?.produce(cvMap, 'UPDATE');
    }
  }

  void updateMapState({bool mapThreadStarted = false}) {
    this.mapThreadStarted = mapThreadStarted;
  }

  String? getDirection() {
    return currDrivingDirection;
  }

  Map<String, dynamic>? calculateDirection(dynamic event) {
    String? direction;
    double? bearing;
    var gps = event['data']?['gps'];
    if (gps != null && gps['bearing'] != null) {
      bearing = (gps['bearing'] as num).toDouble();
      if (0 <= bearing && bearing <= 11) {
        direction = 'TOP-N';
        lastBearing = bearing;
      } else if (11 < bearing && bearing < 22) {
        direction = 'N';
        lastBearing = bearing;
      } else if (22 <= bearing && bearing < 45) {
        direction = 'NNO';
        lastBearing = bearing;
      } else if (45 <= bearing && bearing < 67) {
        direction = 'NO';
        lastBearing = bearing;
      } else if (67 <= bearing && bearing < 78) {
        direction = 'ONO';
        lastBearing = bearing;
      } else if (78 <= bearing && bearing <= 101) {
        direction = 'TOP-O';
        lastBearing = bearing;
      } else if (101 < bearing && bearing < 112) {
        direction = 'O';
        lastBearing = bearing;
      } else if (112 <= bearing && bearing < 135) {
        direction = 'OSO';
        lastBearing = bearing;
      } else if (135 <= bearing && bearing < 157) {
        direction = 'SO';
        lastBearing = bearing;
      } else if (157 <= bearing && bearing < 168) {
        direction = 'SSO';
      } else if (168 <= bearing && bearing < 191) {
        direction = 'TOP-S';
        lastBearing = bearing;
      } else if (191 <= bearing && bearing < 202) {
        direction = 'S';
        lastBearing = bearing;
      } else if (202 <= bearing && bearing < 225) {
        direction = 'SSW';
        lastBearing = bearing;
      } else if (225 <= bearing && bearing < 247) {
        direction = 'SW';
        lastBearing = bearing;
      } else if (247 <= bearing && bearing < 258) {
        direction = 'WSW';
        lastBearing = bearing;
      } else if (258 <= bearing && bearing < 281) {
        direction = 'TOP-W';
      } else if (281 <= bearing && bearing < 292) {
        direction = 'W';
        lastBearing = bearing;
      } else if (292 <= bearing && bearing < 315) {
        direction = 'WNW';
        lastBearing = bearing;
      } else if (315 <= bearing && bearing < 337) {
        direction = 'NW';
        lastBearing = bearing;
      } else if (337 <= bearing && bearing < 348) {
        direction = 'NNW';
        lastBearing = bearing;
      } else if (348 <= bearing && bearing < 355) {
        direction = 'N';
        lastBearing = bearing;
      } else if (355 <= bearing && bearing <= 360) {
        direction = 'TOP-N';
        lastBearing = bearing;
      } else {
        logger.printLogLine(
            'Something bad happened here, direction = -',
            logLevel: 'ERROR');
        direction = calculateBearingDeviation(bearing, lastBearing);
      }
      currDrivingDirection = direction;
    }
    return {'direction': direction, 'bearing': bearing};
  }

  static String calculateBearingDeviation(
      double currentBearing, double? lastBearing) {
    if (lastBearing != null) {
      if (currentBearing >= lastBearing) {
        double deviation = ((currentBearing - lastBearing) / lastBearing) * 100;
        if (deviation > 20) {
          return 'ONO';
        }
        return 'NO';
      } else {
        double deviation =
            ((currentBearing - lastBearing).abs() / lastBearing) * 100;
        if (deviation > 20) {
          return 'NO';
        }
        return 'ONO';
      }
    }
    return 'NO';
  }

  void produceBearingSet(double bearing) {
    if (bearing == 0.002 || bearing == 0.001 || bearing == 0.0) {
      initAverageBearingUpdate(bearing);
      return;
    }
    if (currentBearings.length == 5) {
      initAverageBearingUpdate(currentBearings);
      return;
    }
    currentBearings.add(bearing);
  }

  void resetCurrentBearings() {
    currentBearings = [];
  }

  void initAverageBearingUpdate(dynamic currentBearings) {
    averageAngleQueue?.produce(cvAverageAngle, currentBearings);
    resetCurrentBearings();
  }

  void setLonLat(double lat, double lon) {
    latitude = lat;
    longitude = lon;
  }

  void setLonLatBot(double lat, double lon) {
    latitudeBot = lat;
    longitudeBot = lon;
  }

  List<double?> getLonLat() {
    return [longitude, latitude];
  }

  List<double?> getLonLatBot() {
    return [longitudeBot, latitudeBot];
  }

  void setAccuracy(double acc) {
    accuracy = acc;
  }

  bool getCurrentGpsState() => alreadyOn();

  bool gpsInProgress() => inProgress;

  bool alreadyOn() => onState;

  bool alreadyOff() => offState;

  bool getOsmDataState() => isFilled;

  void osmDataIsFilled() {
    isFilled = true;
  }

  void resetOsmDataState() {
    isFilled = false;
  }
}

