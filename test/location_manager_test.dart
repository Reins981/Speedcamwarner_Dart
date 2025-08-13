import 'dart:async';

import 'package:test/test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workspace/location_manager.dart';
import 'package:workspace/rectangle_calculator.dart';

void main() {
  test('location manager forwards position as vector data', () async {
    final controller = StreamController<Position>();
    final manager = LocationManager();

    await manager.start(positionStream: controller.stream);
    expect(manager.isRunning, isTrue);

    final future = manager.stream.first;

    controller.add(Position(
      longitude: 1.0,
      latitude: 2.0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      accuracy: 5.0,
      altitude: 0.0,
      heading: 4.0,
      speed: 3.0,
      speedAccuracy: 0.0,
    ));

    final VectorData data = await future;

    expect(data.longitude, 1.0);
    expect(data.latitude, 2.0);
    expect(data.speed, closeTo(10.8, 1e-9));
    expect(data.bearing, 4.0);
    expect(data.accuracy, 5.0);

    await manager.stop();
    expect(manager.isRunning, isFalse);
    await controller.close();
    await manager.dispose();
  });

  test('location manager can replay GPX file', () async {
    final manager = LocationManager();
    await manager.start(gpxFile: 'gpx/nordspange_tr2.gpx', minTime: 1);
    final sample = await manager.stream.first;
    expect(sample.latitude, closeTo(52.54380991, 1e-6));
    expect(sample.longitude, closeTo(13.27306718, 1e-6));
    await manager.stop();
    await manager.dispose();
  });
}

