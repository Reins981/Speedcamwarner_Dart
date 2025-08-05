import 'package:test/test.dart';

import '../lib/voice_prompt_queue.dart';

void main() {
  test('camera prompts override gps signals', () async {
    final queue = VoicePromptQueue();
    queue.produceGpsSignal('GPS_LOW');
    queue.produceCameraStatus('CAMERA_AHEAD');
    final item = await queue.consumeItems();
    expect(item, 'CAMERA_AHEAD');
  });

  test('maxspeed exceeded has priority over gps', () async {
    final queue = VoicePromptQueue();
    queue.produceGpsSignal('GPS_LOW');
    queue.produceMaxSpeedExceeded('FIX_NOW');
    final item = await queue.consumeItems();
    expect(item, 'FIX_NOW');
  });
}
