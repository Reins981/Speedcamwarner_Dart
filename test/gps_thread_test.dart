import 'dart:async';

import 'package:test/test.dart';
import 'package:workspace/gps_thread.dart';
import 'package:workspace/rectangle_calculator.dart';

void main() {
  test('gps thread feeds rectangle calculator', () async {
    final gps = GpsThread();
    final calc = RectangleCalculatorThread();
    final completer = Completer<GeoRect>();
    calc.rectangles.listen((rect) {
      if (!completer.isCompleted) {
        completer.complete(rect);
      }
    });

    calc.bindVectorStream(gps.stream);
    gps.start();
    gps.addSample(VectorData(
        longitude: 1.0,
        latitude: 1.0,
        speed: 50,
        bearing: 0,
        direction: 'Main',
        gpsStatus: 1,
        accuracy: 5));

    final rect = await completer.future
        .timeout(const Duration(seconds: 1));
    expect(rect, isNotNull);
    expect(calc.lastRect!.pointInRect(1.0, 1.0), isTrue);

    await gps.stop();
    await calc.dispose();
  });
}
