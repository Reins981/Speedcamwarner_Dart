import 'package:test/test.dart';
import 'package:workspace/overspeed_checker.dart';

void main() {
  test('detects overspeed and reset', () {
    final checker = OverspeedChecker();
    checker.updateLimit(50);
    checker.updateSpeed(60);
    expect(checker.lastDifference, 10);
    checker.updateLimit(null);
    expect(checker.lastDifference, isNull);
  });
}
