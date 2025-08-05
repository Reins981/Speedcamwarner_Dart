import 'dart:async';

import 'package:test/test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workspace/location_manager.dart';
import 'package:workspace/rectangle_calculator.dart';

void main() {
  test('location manager forwards position as vector data', () async {
    final controller = StreamController<Position>();
    final manager = LocationManager();

    manager.start(positionStream: controller.stream);

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
    expect(data.speed, 3.0);
    expect(data.bearing, 4.0);
    expect(data.accuracy, 5.0);

    await manager.stop();
    await controller.close();
  });
}

