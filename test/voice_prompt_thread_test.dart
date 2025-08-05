import 'package:test/test.dart';

import '../lib/voice_prompt_queue.dart';
import '../lib/voice_prompt_thread.dart';

class FakeTts {
  String? lastText;
  Future<List<dynamic>> get getVoices async => [];
  Future<void> setVoice(dynamic voice) async {}
  Future<void> setSpeechRate(double rate) async {}
  Future<void> speak(String text) async {
    lastText = text;
  }
}

class FakeDialogflow {
  Future<String> detectIntent(String text) async => 'response:$text';
}

void main() {
  test('ai voice prompts speak dialogflow response', () async {
    final thread = VoicePromptThread(
      voicePromptQueue: VoicePromptQueue(),
      dialogflowClient: FakeDialogflow(),
      tts: FakeTts(),
      aiVoicePrompts: true,
    );
    await thread.process('hello');
    expect((thread.flutterTts as FakeTts).lastText, 'response:hello');
  });

  test('non ai mapping returns sound path', () {
    final thread = VoicePromptThread(
      voicePromptQueue: VoicePromptQueue(),
      dialogflowClient: FakeDialogflow(),
      tts: FakeTts(),
      aiVoicePrompts: false,
    );
    final sound = thread.mapVoiceEntryToSound('GPS_OFF');
    expect(sound, contains('gps_off.wav'));
  });

  test('setConfigs toggles aiVoicePrompts', () {
    final thread = VoicePromptThread(
      voicePromptQueue: VoicePromptQueue(),
      dialogflowClient: FakeDialogflow(),
      tts: FakeTts(),
    );
    thread.setConfigs(aiVoicePrompts: false);
    expect(thread.aiVoicePrompts, isFalse);
  });

  test('run clears queues when not resumed', () async {
    final queue = VoicePromptQueue();
    queue.produceGpsSignal('GPS_ON');
    final tts = FakeTts();
    final thread = VoicePromptThread(
      voicePromptQueue: queue,
      dialogflowClient: FakeDialogflow(),
      tts: tts,
      isResumed: () => false,
    );

    final future = thread.run();
    await Future.delayed(const Duration(milliseconds: 100));
    thread.stop();
    await future;
    expect(tts.lastText, isNull);
  });
}
