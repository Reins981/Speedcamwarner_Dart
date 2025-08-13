import 'package:test/test.dart';
import 'package:workspace/app_controller.dart';
import 'package:workspace/rectangle_calculator.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  test('start starts all services and stop terminates them', () async {
    final controller = AppController();
    await controller.start(positionStream: const Stream<Position>.empty());

    expect(controller.gps.isRunning, isTrue);
    expect(controller.locationManager.isRunning, isTrue);
    expect(controller.calculator.isRunning, isTrue);

    await controller.stop();

    expect(controller.gps.isRunning, isFalse);
    expect(controller.locationManager.isRunning, isFalse);
    expect(controller.calculator.isRunning, isFalse);

    await controller.dispose();
  });

  test('AppController can replay a GPX track', () async {
    final controller = AppController();
    await controller.start(gpxFile: 'gpx/nordspange_tr2.gpx');
    final VectorData sample = await controller.gps.stream.first;
    expect(sample.latitude, closeTo(52.54380991, 1e-6));
    expect(sample.longitude, closeTo(13.27306718, 1e-6));
    await controller.stop();
    await controller.dispose();
  });
}
