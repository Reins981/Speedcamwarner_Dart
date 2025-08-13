import 'package:test/test.dart';
import 'package:workspace/app_controller.dart';
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
}
