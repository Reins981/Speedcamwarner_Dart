import 'package:test/test.dart';
import 'package:workspace/overspeed_thread.dart';

void main() {
  test('processes overspeed and reset', () async {
    final thread = OverspeedThread(
      cond: ThreadCondition(),
      isResumed: () => true,
    );

    thread.addCurrentSpeed(60);
    thread.addOverspeedEntry({'limit': 50});
    await thread.process();
    expect(thread.difference.value, 10);

    // Now update only the speed without providing a new overspeed entry.
    // The thread should reuse the last max speed and reset the warning.
    thread.addCurrentSpeed(40);
    await thread.process();
    expect(thread.difference.value, isNull);

    await thread.stop();
  });
}

