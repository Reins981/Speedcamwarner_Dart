import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:async/async.dart';
import 'package:test/test.dart';

import 'package:workspace/rectangle_calculator.dart';
import 'package:workspace/config.dart';
import 'package:workspace/linked_list_generator.dart';
import 'package:workspace/rect.dart';
import 'package:workspace/tree_generator.dart';
import 'package:workspace/point.dart';
import 'package:workspace/speed_cam_warner.dart';
import 'package:workspace/voice_prompt_events.dart';
import 'package:workspace/overspeed_checker.dart';

void main() {
  group('RectangleCalculatorThread helpers', () {
    final calc =
        RectangleCalculatorThread(overspeedChecker: OverspeedChecker());

    test('calculateRectangleRadius', () {
      final radius = calc.calculateRectangleRadius(3, 4);
      expect(radius, closeTo(2.5, 1e-9));
    });

    test('calculatePoints2Angle mirrors python logic', () {
      final values = calc.calculatePoints2Angle(0, 0, 10, 0);
      expect(values[0], closeTo(10, 1e-9));
      expect(values[1], closeTo(-10, 1e-9));
      expect(values[2], closeTo(0, 1e-9));
      expect(values[3], closeTo(0, 1e-9));
    });

    test('rotatePoints2Angle rotates around origin', () {
      final values = calc.rotatePoints2Angle(1, -1, 0, 0, math.pi / 2);
      expect(values[0], closeTo(0, 1e-9));
      expect(values[2], closeTo(-1, 1e-9));
      expect(values[1], closeTo(0, 1e-9));
      expect(values[3], closeTo(1, 1e-9));
    });

    test('createGeoJsonTilePolygonAngle', () {
      final poly = calc.createGeoJsonTilePolygonAngle(1, 0, 0, 1, 1, 45.0);
      expect(poly.length, equals(5));
    });

    test('road class lookups', () {
      expect(calc.getRoadClassValue('primary'), equals(2));
      expect(calc.getRoadClassSpeed('residential'), equals('30'));
      expect(calc.getRoadClassTxt(2), 'primary');
    });

    test('processRoadName updates lastRoadName', () {
      final updated = calc.processRoadName(
        foundRoadName: true,
        roadName: 'Main St',
        foundCombinedTags: false,
        roadClass: 'primary',
      );
      expect(updated, isTrue);
      expect(calc.lastRoadName, equals('Main St'));
      expect(calc.roadName, equals('Main St'));
    });

    test('triggerCacheLookup sets road name and max speed', () async {
      final linked = DoubleLinkedListNodes();
      linked.appendNode(
        Node(
          id: 1,
          latitudeStart: 1.0,
          longitudeStart: 1.0,
          latitudeEnd: 1.0,
          longitudeEnd: 1.0,
        ),
      );
      final tree = BinarySearchTree();
      tree.insert(1, 1, {
        'name': 'Main St',
        'maxspeed': '50',
        'highway': 'residential',
      });
      await calc.triggerCacheLookup(
        latitude: 1.0,
        longitude: 1.0,
        linkedListGenerator: linked,
        treeGenerator: tree,
      );
      expect(calc.lastRoadName, equals('Main St'));
      expect(calc.roadName, equals('Main St'));
      expect(calc.lastMaxSpeed, equals(50));
    });

    test('updateNumberOfDistanceCameras increments counter', () {
      expect(calc.numberDistanceCams, equals(0));
      calc.updateNumberOfDistanceCameras({'role': 'device'});
      calc.updateNumberOfDistanceCameras({'role': 'none'});
      expect(calc.numberDistanceCams, equals(1));
    });

    test('direction and extrapolation helpers', () {
      final rc =
          RectangleCalculatorThread(overspeedChecker: OverspeedChecker());
      rc.direction = 'N';
      rc.matchingRect.setRectangleIdent('N');
      rc.matchingRect.setRectangleString('EXTRAPOLATED');
      rc.previousRect = Rect(pointList: [0, 0, 0, 0]);
      rc.previousRect?.setRectangleString('EXTRAPOLATED');
      expect(rc.hasSameDirection(), isTrue);
      expect(rc.isExtrapolatedRectMatching(), isTrue);
      expect(rc.isExtrapolatedRectPrevious(), isTrue);
    });

    test('startThreadPoolDataLookup executes', () async {
      bool called = false;
      Future<bool> dummy({
        double latitude = 0,
        double longitude = 0,
        DoubleLinkedListNodes? linkedListGenerator,
        BinarySearchTree? treeGenerator,
        Rect? currentRect,
      }) async {
        called = true;
        return true;
      }

      await RectangleCalculatorThread.startThreadPoolDataLookup(
        dummy,
        lat: 1,
        lon: 2,
        waitTillCompleted: true,
      );
      expect(called, isTrue);
    });

    test('triggerOsmLookup returns elements', () async {
      final mock = MockClient((req) async {
        final body = jsonEncode({
          'elements': [
            {'id': 1},
          ],
        });
        return http.Response(body, 200);
      });
      final String id = generateRectId(0, 0, 1, 1, "Default");
      final result = await calc.triggerOsmLookup(
        GeoRect(id: id, minLat: 0, minLon: 0, maxLat: 1, maxLon: 1),
        client: mock,
      );
      expect(result.success, isTrue);
      expect(result.elements, isNotNull);
      expect(result.elements!.length, equals(1));
    });

    test('triggerOsmLookup avoids duplicate data prefix', () async {
      // Mimic configuration that already contains the `data=` prefix
      AppConfig.loadFromMap({
        'speedCamWarner': {
          'querystring1': 'data=[out:json];',
          'querystring2': 'node[highway=speed_camera]',
          'querystring3': '(around:5,0,0)',
          'querystring4': ';out;'
        }
      });

      String? capturedBody;
      final mock = MockClient((req) async {
        capturedBody = req.body;
        return http.Response(jsonEncode({'elements': []}), 200);
      });

      final String id = generateRectId(0, 0, 1, 1, "Default");
      await calc.triggerOsmLookup(
        GeoRect(id: id, minLat: 0, minLon: 0, maxLat: 1, maxLon: 1),
        client: mock,
      );

      // Ensure the request body contains exactly one `data=` prefix
      expect(capturedBody, startsWith('data='));
      expect(capturedBody, isNot(startsWith('data=data=')));

      // Reset configuration for subsequent tests
      AppConfig.loadFromMap({});
    });

    test('triggerOsmLookup retries on timeout and falls back to cache',
        () async {
      final calc =
          RectangleCalculatorThread(overspeedChecker: OverspeedChecker());
      calc.osmRetryBaseDelay = const Duration(milliseconds: 1);
      calc.processAllSpeedCameras([
        SpeedCameraEvent(latitude: 0.5, longitude: 0.5, fixed: true, name: 'C'),
      ]);
      var calls = 0;
      final mock = MockClient((req) async {
        calls++;
        throw TimeoutException('timeout');
      });
      final String id = generateRectId(0, 0, 1, 1, "Default");
      final result = await calc.triggerOsmLookup(
        GeoRect(id: id, minLat: 0, minLon: 0, maxLat: 1, maxLon: 1),
        lookupType: 'camera_ahead',
        client: mock,
      );
      expect(calls, equals(calc.osmRetryMaxAttempts));
      expect(result.success, isTrue);
      expect(result.status, equals('CACHE'));
      expect(result.elements, isNotNull);
      expect(result.elements!.length, equals(1));
    });

    test('triggerOsmLookup surfaces timeout when no cache', () async {
      final calc =
          RectangleCalculatorThread(overspeedChecker: OverspeedChecker());
      calc.osmRetryBaseDelay = const Duration(milliseconds: 1);
      var calls = 0;
      final mock = MockClient((req) async {
        calls++;
        throw TimeoutException('timeout');
      });
      final String id = generateRectId(0, 0, 1, 1, "Default");
      final result = await calc.triggerOsmLookup(
        GeoRect(id: id, minLat: 0, minLon: 0, maxLat: 1, maxLon: 1),
        lookupType: 'camera_ahead',
        client: mock,
      );
      expect(calls, equals(calc.osmRetryMaxAttempts));
      expect(result.success, isFalse);
      expect(result.status, equals('TIMEOUT'));
    });

    test('uploadCameraToDrive writes json', () async {
      final dir = await Directory.systemTemp.createTemp();
      final path = '${dir.path}/cameras.json';
      await File(path).writeAsString(jsonEncode({'cameras': []}));
      final ok = await uploadCameraToDrive(
        name: 'Test',
        latitude: 1.0,
        longitude: 2.0,
        camerasJsonPath: path,
      );
      expect(ok, isTrue);
      final decoded =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      expect((decoded['cameras'] as List).length, equals(1));
      final dup = await uploadCameraToDrive(
        name: 'Test',
        latitude: 1.0,
        longitude: 2.0,
        camerasJsonPath: path,
      );
      expect(dup, isFalse);
    });

    test(
      'speedCamLookupAhead emits camera markers and updates counts',
      () async {
        final calc =
            RectangleCalculatorThread(overspeedChecker: OverspeedChecker());
        final queries = <String>[];
        final mock = MockClient((req) async {
          queries.add(
            Uri.decodeQueryComponent(
              req.url.queryParameters['data'] ?? '',
            ),
          );
          final body = jsonEncode({
            'elements': [
              {
                'lat': 1.0,
                'lon': 2.0,
                'tags': {
                  'highway': 'speed_camera',
                  'name': 'A',
                  'speed_camera': 'yes'
                },
              },
              {
                'lat': 3.0,
                'lon': 4.0,
                'tags': {
                  'highway': 'speed_camera',
                  'speed_camera': 'traffic_signals'
                },
              },
              {
                'lat': 5.0,
                'lon': 6.0,
                'tags': {'role': 'device'},
              },
            ],
          });
          return http.Response(body, 200);
        });
        final queue = StreamQueue(calc.cameras);
        await calc.speedCamLookupAhead(0, 0, 0, 0, client: mock);
        final cam1 = await queue.next;
        final cam2 = await queue.next;
        final cam3 = await queue.next;
        expect(queries.length, equals(2));
        expect(queries[0], contains('[highway=speed_camera]'));
        expect(queries[1], contains('mindistance'));
        expect(cam1.fixed || cam2.fixed || cam3.fixed, isTrue);
        expect(
          [cam1, cam2, cam3].where((c) => c.traffic).length,
          equals(1),
        );
        expect(
          [cam1, cam2, cam3].where((c) => c.distance).length,
          equals(1),
        );
        expect(calc.fix_cams, equals(1));
        expect(calc.traffic_cams, equals(1));
        expect(calc.distance_cams, equals(1));
        expect(calc.infoPage, equals('SPEED_CAMERAS:1,1,1,0'));
        await queue.cancel();
      },
    );

    test('resolveDangersOnTheRoad updates info page', () {
      final calc =
          RectangleCalculatorThread(overspeedChecker: OverspeedChecker());
      calc.resolveDangersOnTheRoad({'hazard': 'flood'});
      expect(calc.infoPage, equals('FLOOD'));
      calc.resolveDangersOnTheRoad({});
      expect(calc.infoPage, isNull);
    });

    test('updateMaxspeed and updateRoadname behave as python', () {
      final calc =
          RectangleCalculatorThread(overspeedChecker: OverspeedChecker());
      calc.updateMaxspeed(50);
      expect(calc.maxspeed, equals(50));
      calc.updateMaxspeed('cleanup');
      expect(calc.maxspeed, isNull);
      calc.updateRoadname('Main/Cross');
      expect(calc.roadName, equals('Cross/Main'));
      calc.updateRoadname('cleanup');
      expect(calc.roadName, equals(''));
    });

    test('processOffline clears road name', () async {
      final calc =
          RectangleCalculatorThread(overspeedChecker: OverspeedChecker());
      calc.lastMaxSpeed = '';
      calc.updateRoadname('Main', false);
      await calc.processOffline();
      expect(calc.roadName, equals(''));
    });

    test('processOffline extrapolates position using cached data', () async {
      final calc =
          RectangleCalculatorThread(overspeedChecker: OverspeedChecker());
      // Set initial cached values.
      calc.longitudeCached = 10.0;
      calc.latitudeCached = 20.0;
      calc.cacheCspeed('last', 36.0); // 36 km/h -> 10 m/s
      calc.cacheBearing('last', 90.0);

      await calc.processOffline();

      final expected =
          calc.calculateExtrapolatedPosition(Point(10.0, 20.0), 90.0, 10.0);

      expect(calc.longitudeCached, closeTo(expected.x, 1e-6));
      expect(calc.latitudeCached, closeTo(expected.y, 1e-6));
      expect(calc.positionNotifier.value.longitude, closeTo(expected.x, 1e-6));
      expect(calc.positionNotifier.value.latitude, closeTo(expected.y, 1e-6));

      await calc.dispose();
    });

    test('SpeedCamWarner receives extrapolated position updates', () async {
      final calc =
          RectangleCalculatorThread(overspeedChecker: OverspeedChecker());
      final warner = SpeedCamWarner(
        resume: null,
        voicePromptEvents: VoicePromptEvents(),
        osmWrapper: null,
        calculator: calc,
      );
      await warner.run();

      calc.longitudeCached = 5.0;
      calc.latitudeCached = 6.0;
      calc.cacheCspeed('last', 18.0); // 18 km/h -> 5 m/s
      calc.cacheBearing('last', 0.0);

      await calc.processOffline();

      expect(warner.lastPosition?.latitude, closeTo(calc.latitudeCached, 1e-6));
      expect(
          warner.lastPosition?.longitude, closeTo(calc.longitudeCached, 1e-6));

      await warner.stop();
      await calc.dispose();
    });

    test('processLookAheadInterrupts resolves road name', () async {
      final calc = _TestCalc();
      await calc.processLookAheadInterrupts();
      expect(calc.lastRoadName, equals('Test Road'));
      expect(calc.roadName, equals('Test Road'));
      expect(calc.lastMaxSpeed, equals(''));
    });

    test('vector gpsStatus OFFLINE triggers offline handling', () async {
      final calc =
          RectangleCalculatorThread(overspeedChecker: OverspeedChecker());
      calc.updateRoadname('Main', false);
      calc.addVectorSample(
        VectorData(
          longitude: 1.0,
          latitude: 1.0,
          speed: 0,
          bearing: 0,
          direction: 'Main',
          gpsStatus: 'OFFLINE',
          accuracy: 5,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));
      expect(calc.roadName, equals(''));
      expect(calc.onlineStatusNotifier.value, isFalse);
      expect(calc.gpsStatusNotifier.value, isFalse);
      await calc.dispose();
    });

    test('CALCULATE action processes look-ahead interrupts', () async {
      final calc = _InterruptCalc();
      calc.camerasLookAheadMode = true;
      calc.addVectorSample(
        VectorData(
          longitude: 1.0,
          latitude: 1.0,
          speed: 10,
          bearing: 0,
          direction: 'Main',
          gpsStatus: 'CALCULATE',
          accuracy: 5,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 100));
      expect(calc.lookAheadCalled, isTrue);
      expect(calc.roadName, equals('Test Road'));
      expect(calc.onlineStatusNotifier.value, isTrue);
      expect(calc.gpsStatusNotifier.value, isTrue);
      await calc.dispose();
    });

    test('processLookaheadItems triggers lookups', () async {
      final calc = _TestCalc();
      final start = DateTime.now().subtract(const Duration(seconds: 120));
      await calc.processLookaheadItems(start);
      expect(calc.speedCalled, isTrue);
      expect(calc.constructionCalled, isTrue);
    });

    test('rate limit prevents frequent lookups', () async {
      final calc = _RateLimitCalc();
      final start = DateTime.now().subtract(const Duration(seconds: 120));
      await calc.processLookaheadItems(start);
      expect(calc.speedCalls, equals(1));
      expect(calc.constructionCalls, equals(1));

      // Second call occurs immediately and should be skipped by the rate limiter.
      await calc.processLookaheadItems(start);
      expect(calc.speedCalls, equals(1));
      expect(calc.constructionCalls, equals(1));

      // After the interval passes both lookups should execute again.
      await Future.delayed(const Duration(seconds: 2));
      await calc.processLookaheadItems(start);
      expect(calc.speedCalls, equals(2));
      expect(calc.constructionCalls, equals(2));
    });

    test('processConstructionAreasLookupAheadResults stores areas', () async {
      final calc =
          RectangleCalculatorThread(overspeedChecker: OverspeedChecker());
      await calc.processConstructionAreasLookupAheadResults(
        [
          {
            'type': 'way',
            'nodes': [1],
            'tags': {'construction': 'yes'},
          },
          {
            'type': 'node',
            'id': 1,
            'lat': 1.0,
            'lon': 2.0,
          },
        ],
        'construction_ahead',
        0,
        0,
      );
      expect(calc.constructionAreas.isNotEmpty, isTrue);
    });
  });
}

class _TestCalc extends RectangleCalculatorThread {
  bool speedCalled = false;
  bool constructionCalled = false;

  @override
  Future<String?> getRoadNameViaNominatim(double lat, double lon) async =>
      'Test Road';

  @override
  Future<bool> internetAvailable() async => true;

  @override
  Future<void> speedCamLookupAhead(
    double xtile,
    double ytile,
    double lon,
    double lat, {
    http.Client? client,
  }) async {
    speedCalled = true;
  }

  @override
  Future<void> constructionsLookupAhead(
    double xtile,
    double ytile,
    double lon,
    double lat, {
    http.Client? client,
  }) async {
    constructionCalled = true;
  }

  @override
  Future<SpeedCameraEvent?> processPredictiveCameras(
    double longitude,
    double latitude,
  ) async =>
      null;
}

class _InterruptCalc extends RectangleCalculatorThread {
  bool lookAheadCalled = false;

  @override
  Future<void> processLookAheadInterrupts() async {
    lookAheadCalled = true;
    await super.processLookAheadInterrupts();
  }

  @override
  Future<void> processLookaheadItems(DateTime startTime,
      {bool previousCcp = false}) async {}

  @override
  Future<String?> getRoadNameViaNominatim(double lat, double lon) async =>
      'Test Road';

  @override
  Future<bool> internetAvailable() async => true;

  @override
  Future<OsmLookupResult> triggerOsmLookup(GeoRect area,
      {String? lookupType, int? nodeId, http.Client? client}) async {
    updateOnlineStatus(true);
    return OsmLookupResult(true, 'OK', [], null, area);
  }
}

class _RateLimitCalc extends RectangleCalculatorThread {
  int speedCalls = 0;
  int constructionCalls = 0;

  _RateLimitCalc() {
    dosAttackPreventionIntervalDownloads = 1;
    constructionAreaStartupTriggerMax = 0;
    constructionAreaLookupInterval = 1;
  }

  @override
  Future<String?> getRoadNameViaNominatim(double lat, double lon) async =>
      'Test Road';

  @override
  Future<bool> internetAvailable() async => true;

  @override
  Future<void> speedCamLookupAhead(
    double xtile,
    double ytile,
    double lon,
    double lat, {
    http.Client? client,
  }) async {
    speedCalls++;
  }

  @override
  Future<void> constructionsLookupAhead(
    double xtile,
    double ytile,
    double lon,
    double lat, {
    http.Client? client,
  }) async {
    constructionCalls++;
  }

  @override
  Future<SpeedCameraEvent?> processPredictiveCameras(
    double longitude,
    double latitude,
  ) async =>
      null;
}
