import 'package:test/test.dart';
import 'package:workspace/overspeed_thread.dart';

void main() {
  test('detects overspeed and reset', () {
    final checker = OverspeedThread(
      cond: ThreadCondition(),
      isResumed: () => true,
    );

    checker.setSpeedAndLimit(speed: 60, limit: 50);
    expect(checker.lastDifference, 10);

    checker.setSpeedAndLimit(speed: 40, limit: null);
    expect(checker.lastDifference, isNull);
  });
}
