import 'package:flutter_tts/flutter_tts.dart';

class VoicePromptThread {
  final FlutterTts _flutterTts = FlutterTts();
  final dynamic voicePromptQueue;
  final dynamic dialogflowClient;
  final bool aiVoicePrompts;
  bool _lock = false;

  VoicePromptThread({
    required this.voicePromptQueue,
    required this.dialogflowClient,
    this.aiVoicePrompts = false,
  }) {
    _initializeTts();
  }

  Future<void> _initializeTts() async {
    // Set the default voice to a female voice if available
    List<dynamic> voices = await _flutterTts.getVoices;
    for (var voice in voices) {
      if (voice.toString().toLowerCase().contains("female")) {
        await _flutterTts.setVoice(voice);
        break;
      }
    }

    // Set the speaking rate
    await _flutterTts.setSpeechRate(0.6); // Adjust as needed
  }

  Future<void> synthesizeSpeech(String text) async {
    await _flutterTts.speak(text);
  }

  Future<void> process() async {
    var voiceEntry = voicePromptQueue.consumeItems();

    while (_lock) {
      await Future.delayed(Duration(milliseconds: 100));
    }

    if (aiVoicePrompts) {
      // Use Dialogflow to generate a response
      var response = await dialogflowClient.detectIntent(voiceEntry);
      print("Dialogflow response: $response");

      // Convert Dialogflow response text to speech
      _lock = true;
      await synthesizeSpeech(response);
      _lock = false;
    }
  }
}
