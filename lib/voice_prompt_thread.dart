import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';

import 'voice_prompt_events.dart';

/// Port of the Python `VoicePromptThread` used for acoustic warnings.
class VoicePromptThread {
  final dynamic flutterTts;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final VoicePromptEvents voicePromptEvents;
  final dynamic dialogflowClient;
  bool aiVoicePrompts;
  final bool Function()? isResumed;
  final bool Function()? runInBackground;
  final Future<void> Function()? waitForMainEvent;

  bool _lock = false;
  bool _running = true;

  static const String _basePath = 'python/sounds';

  VoicePromptThread({
    required this.voicePromptEvents,
    required this.dialogflowClient,
    dynamic tts,
    this.aiVoicePrompts = true,
    this.isResumed,
    this.runInBackground,
    this.waitForMainEvent,
  }) : flutterTts = tts ?? FlutterTts() {
    _initializeTts();
    _audioPlayer.onPlayerComplete.listen((event) {
      _lock = false;
    });
  }

  Future<void> _initializeTts() async {
    try {
      final voices = await flutterTts.getVoices;
      for (final voice in voices) {
        if (voice.toString().toLowerCase().contains('female')) {
          await flutterTts.setVoice(voice);
          break;
        }
      }
      await flutterTts.setSpeechRate(0.6);
    } catch (_) {
      // Ignore platform exceptions in headless environments.
    }
  }

  /// Configure thread options like AI voice prompts.
  void setConfigs({bool aiVoicePrompts = true}) {
    this.aiVoicePrompts = aiVoicePrompts;
  }

  /// Start consuming items from [voicePromptEvents] until [stop] is called.
  StreamSubscription<dynamic>? _sub;

  Future<void> run() async {
    _sub = voicePromptEvents.stream.listen((event) async {
      if (!_running) return;
      if (runInBackground?.call() ?? false) {
        await (waitForMainEvent?.call() ?? Future.value());
      }
      if (!(isResumed?.call() ?? true)) {
        return;
      }
      if (event is String) {
        await process(event);
      }
    });
  }

  Future<void> stop() async {
    _running = false;
    await _sub?.cancel();
  }

  Future<void> playSound(String fileName) async {
    _lock = true;
    await _audioPlayer.play(AssetSource('$_basePath/$fileName'));
  }

  Future<void> process(String voiceEntry) async {
    while (_lock) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (aiVoicePrompts) {
      final response = await dialogflowClient.detectIntent(voiceEntry);
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

  Future<void> synthesizeSpeech(String text) async {
    try {
      await flutterTts.speak(text);
    } catch (_) {}
  }

  /// Map the incoming [voiceEntry] identifier to a sound file within
  /// ``python/sounds``.  Returns `null` if no mapping exists.
  String? mapVoiceEntryToSound(String voiceEntry) {
    final map = <String, String>{
      'EXIT_APPLICATION': 'app_exit.wav',
      'ADDED_POLICE': 'police_added.wav',
      'ADDING_POLICE_FAILED': 'police_failed.wav',
      'STOP_APPLICATION': 'app_stopped.wav',
      'OSM_DATA_ERROR': 'data_error.wav',
      'INTERNET_CONN_FAILED': 'inet_failed.wav',
      'HAZARD': 'hazard.wav',
      'EMPTY_DATASET_FROM_SERVER': 'empty_data.wav',
      'LOW_DOWNLOAD_DATA_RATE': 'low_download_rate.wav',
      'GPS_OFF': 'gps_off.wav',
      'GPS_LOW': 'gps_weak.wav',
      'GPS_ON': 'gps_established.wav',
      'SPEEDCAM_BACKUP': 'camera_backup.wav',
      'SPEEDCAM_REINSERT': 'speed_cam_reinserted.wav',
      'FIX_100': 'fix_100.wav',
      'TRAFFIC_100': 'traffic_100.wav',
      'MOBILE_100': 'mobile_100.wav',
      'DISTANCE_100': 'distance_100.wav',
      'FIX_300': 'fix_300.wav',
      'TRAFFIC_300': 'traffic_300.wav',
      'MOBILE_300': 'mobile_300.wav',
      'DISTANCE_300': 'distance_300.wav',
      'FIX_500': 'fix_500.wav',
      'TRAFFIC_500': 'traffic_500.wav',
      'MOBILE_500': 'mobile_500.wav',
      'DISTANCE_500': 'distance_500.wav',
      'FIX_1000': 'fix_1000.wav',
      'TRAFFIC_1000': 'traffic_1000.wav',
      'MOBILE_1000': 'mobile_1000.wav',
      'DISTANCE_1000': 'distance_1000.wav',
      'FIX_NOW': 'fix_now.wav',
      'TRAFFIC_NOW': 'traffic_now.wav',
      'MOBILE_NOW': 'mobile_now.wav',
      'DISTANCE_NOW': 'distance_now.wav',
      'CAMERA_AHEAD': 'camera_ahead.wav',
      'WATER': 'water.wav',
      'ACCESS_CONTROL': 'access_control.wav',
      'POI_SUCCESS': 'poi_success.wav',
      'POI_FAILED': 'poi_failed.wav',
      'NO_ROUTE': 'no_route.wav',
      'ROUTE_STOPPED': 'route_stopped.wav',
      'POI_REACHED': 'poi_reached.wav',
      'ANGLE_MISMATCH': 'angle_mismatch.wav',
      'AR_HUMAN': 'human.wav',
    };
    final file = map[voiceEntry];
    return file != null ? '$_basePath/$file' : null;
  }
}
