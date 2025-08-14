import 'package:test/test.dart';

import '../lib/voice_prompt_events.dart';
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

class TestVoicePromptThread extends VoicePromptThread {
  final List<String> played = [];
  TestVoicePromptThread({
    required super.voicePromptEvents,
    required super.dialogflowClient,
    super.tts,
    super.aiVoicePrompts,
  });

  @override
  Future<void> playSound(String fileName) async {
    played.add(fileName);
  }
}

void main() {
  test('ai voice prompts speak dialogflow response', () async {
    final thread = VoicePromptThread(
      voicePromptEvents: VoicePromptEvents(),
      dialogflowClient: FakeDialogflow(),
      tts: FakeTts(),
      aiVoicePrompts: true,
    );
    await thread.process('hello');
    expect((thread.flutterTts as FakeTts).lastText, 'response:hello');
  });

  test('non ai mapping returns sound path', () {
    final thread = VoicePromptThread(
      voicePromptEvents: VoicePromptEvents(),
      dialogflowClient: FakeDialogflow(),
      tts: FakeTts(),
      aiVoicePrompts: false,
    );
    final sound = thread.mapVoiceEntryToSound('GPS_OFF');
    expect(sound, contains('gps_off.wav'));
    final low = thread.mapVoiceEntryToSound('GPS_LOW');
    expect(low, contains('gps_weak.wav'));
  });

  test('setConfigs toggles aiVoicePrompts', () {
    final thread = VoicePromptThread(
      voicePromptEvents: VoicePromptEvents(),
      dialogflowClient: FakeDialogflow(),
      tts: FakeTts(),
    );
    thread.setConfigs(aiVoicePrompts: false);
    expect(thread.aiVoicePrompts, isFalse);
  });

  test('run ignores events when not resumed', () async {
    final events = VoicePromptEvents();
    final tts = FakeTts();
    final thread = VoicePromptThread(
      voicePromptEvents: events,
      dialogflowClient: FakeDialogflow(),
      tts: tts,
      isResumed: () => false,
    );

    await thread.run();
    events.emit('GPS_ON');
    await Future.delayed(const Duration(milliseconds: 100));
    await thread.stop();
    expect(tts.lastText, isNull);
  });

  test('ar events processed by voice thread', () async {
    final thread = TestVoicePromptThread(
      voicePromptEvents: VoicePromptEvents(),
      dialogflowClient: FakeDialogflow(),
      tts: FakeTts(),
      aiVoicePrompts: false,
    );
    await thread.process('AR_HUMAN');
    expect(thread.played, contains('human.wav'));
  });
}
