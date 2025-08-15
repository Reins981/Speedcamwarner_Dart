import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:workspace/gps_thread.dart';
import 'package:workspace/rectangle_calculator.dart';
import 'package:workspace/voice_prompt_events.dart';

void main() {
  test('gps thread feeds rectangle calculator', () async {
    final gps = GpsThread();
    final calc = RectangleCalculatorThread();
    final completer = Completer<GeoRect>();
    calc.rectangles.listen((rect) {
      if (rect != null && !completer.isCompleted) {
        completer.complete(rect);
      }
    });

    calc.bindVectorStream(gps.stream);
    gps.start();
    gps.addSample(
      VectorData(
        longitude: 1.0,
        latitude: 1.0,
        speed: 50,
        bearing: 0,
        direction: 'Main',
        gpsStatus: 1,
        accuracy: 5,
      ),
    );

    final rect = await completer.future.timeout(const Duration(seconds: 1));
    expect(rect, isNotNull);
    final tiles = calc.longlat2tile(1.0, 1.0, calc.zoom);
    expect(calc.lastRect!.pointInRect(tiles[0], tiles[1]), isTrue);

    await gps.stop();
    await calc.dispose();
  });

  test('gps thread forwards gps accuracy to voice queue', () async {
    final events = VoicePromptEvents();
    final gps = GpsThread(voicePromptEvents: events, accuracyThreshold: 10);
    gps.start();
    gps.addSample(
      VectorData(
        longitude: 1.0,
        latitude: 1.0,
        speed: 0,
        bearing: 0,
        direction: 'Main',
        gpsStatus: 1,
        accuracy: 5,
      ),
    );
    final first = await events.stream.first.timeout(
      const Duration(milliseconds: 100),
    );
    expect(first, 'GPS_ON');

    gps.addSample(
      VectorData(
        longitude: 1.0,
        latitude: 1.0,
        speed: 0,
        bearing: 0,
        direction: 'Main',
        gpsStatus: 1,
        accuracy: 20,
      ),
    );
    final second = await events.stream.first.timeout(
      const Duration(milliseconds: 100),
    );
    expect(second, 'GPS_LOW');

    await gps.stop();
  });

  test('gps thread records route to gpx', () async {
    final gps = GpsThread();
    gps.start();
    gps.startRecording();
    gps.addSample(
      VectorData(
        longitude: 1.0,
        latitude: 1.0,
        speed: 50,
        bearing: 0,
        direction: 'Main',
        gpsStatus: 1,
        accuracy: 5,
      ),
    );
    await gps.stopRecording('gpx/test_route.gpx');
    expect(File('gpx/test_route.gpx').existsSync(), isTrue);
    await gps.stop();
  });
}
