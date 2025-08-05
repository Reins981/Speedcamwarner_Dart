import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';

class VoicePromptThread {
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final dynamic voicePromptQueue;
  final dynamic dialogflowClient;
  final bool aiVoicePrompts;
  bool _lock = false;

  static const String _basePath = 'python/sounds';

  VoicePromptThread({
    required this.voicePromptQueue,
    required this.dialogflowClient,
    this.aiVoicePrompts = false,
  }) {
    _initializeTts();
    _audioPlayer.onPlayerComplete.listen((event) {
      _lock = false;
    });
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

  Future<void> playSound(String fileName) async {
    _lock = true;
    await _audioPlayer.play(AssetSource('$_basePath/$fileName'));
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
    } else {
      String? sound;
      switch (voiceEntry) {
        case 'EXIT_APPLICATION':
          sound = 'app_exit.wav';
          break;
        case 'ADDED_POLICE':
          sound = 'police_added.wav';
          break;
        case 'ADDING_POLICE_FAILED':
          sound = 'police_failed.wav';
          break;
        case 'STOP_APPLICATION':
          sound = 'app_stopped.wav';
          break;
        case 'OSM_DATA_ERROR':
          sound = null;
          break;
        case 'INTERNET_CONN_FAILED':
          sound = 'inet_failed.wav';
          break;
        case 'HAZARD':
          sound = 'hazard.wav';
          break;
        case 'EMPTY_DATASET_FROM_SERVER':
          sound = null;
          break;
        case 'LOW_DOWNLOAD_DATA_RATE':
          sound = 'low_download_rate.wav';
          break;
        case 'GPS_OFF':
          sound = 'gps_off.wav';
          break;
        case 'GPS_LOW':
          sound = 'gps_weak.wav';
          break;
        case 'GPS_ON':
          sound = 'gps_established.wav';
          break;
        case 'SPEEDCAM_BACKUP':
          sound = 'camera_backup.wav';
          break;
        case 'SPEEDCAM_REINSERT':
          sound = 'speed_cam_reinserted.wav';
          break;
        case 'FIX_100':
          sound = 'fix_100.wav';
          break;
        case 'TRAFFIC_100':
          sound = 'traffic_100.wav';
          break;
        case 'MOBILE_100':
          sound = 'mobile_100.wav';
          break;
        case 'DISTANCE_100':
          sound = 'distance_100.wav';
          break;
        case 'FIX_300':
          sound = 'fix_300.wav';
          break;
        case 'TRAFFIC_300':
          sound = 'traffic_300.wav';
          break;
        case 'MOBILE_300':
          sound = 'mobile_300.wav';
          break;
        case 'DISTANCE_300':
          sound = 'distance_300.wav';
          break;
        case 'FIX_500':
          sound = 'fix_500.wav';
          break;
        case 'TRAFFIC_500':
          sound = 'traffic_500.wav';
          break;
        case 'MOBILE_500':
          sound = 'mobile_500.wav';
          break;
        case 'DISTANCE_500':
          sound = 'distance_500.wav';
          break;
        case 'FIX_1000':
          sound = 'fix_1000.wav';
          break;
        case 'TRAFFIC_1000':
          sound = 'traffic_1000.wav';
          break;
        case 'MOBILE_1000':
          sound = 'mobile_1000.wav';
          break;
        case 'DISTANCE_1000':
          sound = 'distance_1000.wav';
          break;
        case 'FIX_NOW':
          sound = 'fix_now.wav';
          break;
        case 'TRAFFIC_NOW':
          sound = 'traffic_now.wav';
          break;
        case 'MOBILE_NOW':
          sound = 'mobile_now.wav';
          break;
        case 'DISTANCE_NOW':
          sound = 'distance_now.wav';
          break;
        case 'CAMERA_AHEAD':
          sound = 'camera_ahead.wav';
          break;
        case 'WATER':
          sound = 'water.wav';
          break;
        case 'ACCESS_CONTROL':
          sound = 'access_control.wav';
          break;
        case 'POI_SUCCESS':
          sound = 'poi_success.wav';
          break;
        case 'POI_FAILED':
          sound = 'poi_failed.wav';
          break;
        case 'NO_ROUTE':
          sound = 'no_route.wav';
          break;
        case 'ROUTE_STOPPED':
          sound = 'route_stopped.wav';
          break;
        case 'POI_REACHED':
          sound = 'poi_reached.wav';
          break;
        case 'ANGLE_MISMATCH':
          sound = 'angle_mismatch.wav';
          break;
        case 'AR_HUMAN':
          sound = 'human.wav';
          break;
        default:
          sound = null;
      }

      if (sound != null) {
        await playSound(sound);
      }
    }
  }
}
