import 'package:test/test.dart';
import 'package:workspace/overspeed_checker.dart';

void main() {
  test('detects overspeed and reset', () {
    final checker = OverspeedChecker();
    checker.process(60, {'limit': 50});
    expect(checker.lastDifference, 10);
    checker.process(40, {});
    expect(checker.lastDifference, isNull);
  });
}
