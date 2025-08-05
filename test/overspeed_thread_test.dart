import 'package:test/test.dart';
import 'package:workspace/overspeed_thread.dart';

class _MockSpeedLayout implements SpeedLayout {
  int? lastValue;
  int resetCount = 0;

  @override
  void resetOverspeed() {
    lastValue = null;
    resetCount++;
  }

  @override
  void updateOverspeed(int value) {
    lastValue = value;
  }
}

void main() {
  test('processes overspeed and reset', () async {
    final layout = _MockSpeedLayout();
    final thread = OverspeedThread(
      cond: ThreadCondition(),
      isResumed: () => true,
      speedLayout: layout,
    );

    thread.addCurrentSpeed(60);
    thread.addOverspeedEntry({'limit': 50});
    await thread.process();
    expect(layout.lastValue, 10);

    thread.addCurrentSpeed(40);
    thread.addOverspeedEntry({});
    await thread.process();
    expect(layout.lastValue, isNull);
    expect(layout.resetCount, 1);

    await thread.stop();
  });
}

