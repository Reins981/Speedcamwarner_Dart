import 'package:test/test.dart';
import '../lib/rectangle_calculator.dart';
import '../lib/point.dart';
import '../lib/overspeed_checker.dart';

void main() {
  test('camera cache lookup and cleanup', () {
    final calc = RectangleCalculatorThread(overspeedChecker: OverspeedChecker());
    calc.processAllSpeedCameras([
      SpeedCameraEvent(latitude: 1, longitude: 1, fixed: true),
    ]);
    final res = calc.speedCamLookup(Point(1, 1));
    expect(res.length, 1);
    calc.cleanupMapContent();
    expect(calc.speedCamLookup(Point(1, 1)).isEmpty, isTrue);
  });
}
