import 'package:test/test.dart';

import '../lib/voice_prompt_events.dart';

void main() {
  test('events are delivered to listeners', () async {
    final bus = VoicePromptEvents();
    final events = <dynamic>[];
    bus.stream.listen(events.add);
    bus.emit('GPS_ON');
    await Future.delayed(const Duration(milliseconds: 10));
    expect(events, contains('GPS_ON'));
  });
}
