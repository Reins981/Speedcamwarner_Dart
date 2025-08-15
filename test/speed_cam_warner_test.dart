import 'package:test/test.dart';
import 'package:workspace/speed_cam_warner.dart';
import 'package:workspace/rectangle_calculator.dart';
import 'package:workspace/voice_prompt_events.dart';
import 'package:workspace/config.dart';

class _ResumeStub {
  bool isResumed() => true;
}

void main() {
  test('triggerFreeFlow clears speed camera data', () async {
    AppConfig.loadFromMap({});
    final calculator = RectangleCalculatorThread();
    final warner = SpeedCamWarner(
      resume: _ResumeStub(),
      voicePromptEvents: VoicePromptEvents(),
      osmWrapper: null,
      calculator: calculator,
    );

    calculator.updateSpeedCam('CAMERA_AHEAD');
    calculator.updateSpeedCamDistance(42);
    calculator.updateCameraRoad('Test Road');

    warner.triggerFreeFlow();

    expect(calculator.speedCamNotifier.value, 'FREEFLOW');
    expect(calculator.speedCamDistanceNotifier.value, isNull);
    expect(calculator.cameraRoadNotifier.value, isNull);

    await calculator.dispose();
  });
}
