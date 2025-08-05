import 'package:flutter_tts/flutter_tts.dart';

import 'voice_prompt_queue.dart';

const String _basePath = 'python/sounds';

/// Port of the Python `VoicePromptThread` used for acoustic warnings.
class VoicePromptThread {
  final dynamic flutterTts;
  final VoicePromptQueue voicePromptQueue;
  final dynamic dialogflowClient;
  bool aiVoicePrompts;
  final bool Function()? isResumed;
  final bool Function()? runInBackground;
  final Future<void> Function()? waitForMainEvent;

  bool _lock = false;
  bool _running = true;

  VoicePromptThread({
    required this.voicePromptQueue,
    required this.dialogflowClient,
    dynamic tts,
    this.aiVoicePrompts = true,
    this.isResumed,
    this.runInBackground,
    this.waitForMainEvent,
  }) : flutterTts = tts ?? FlutterTts() {
    _initializeTts();
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

  /// Start consuming items from [voicePromptQueue] until [stop] is called.
  Future<void> run() async {
    while (_running) {
      if (runInBackground?.call() ?? false) {
        await (waitForMainEvent?.call() ?? Future.value());
      }
      if (!(isResumed?.call() ?? true)) {
        voicePromptQueue.clearGpsSignalQueue();
        voicePromptQueue.clearMaxSpeedExceededQueue();
        voicePromptQueue.clearOnlineQueue();
        voicePromptQueue.clearArQueue();
        continue;
      }

      final voiceEntry = await voicePromptQueue.consumeItems();
      if (!_running) break;
      await process(voiceEntry);
    }
    voicePromptQueue.clearGpsSignalQueue();
    voicePromptQueue.clearMaxSpeedExceededQueue();
    voicePromptQueue.clearOnlineQueue();
    voicePromptQueue.clearArQueue();
  }

  void stop() {
    _running = false;
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
      final sound = mapVoiceEntryToSound(voiceEntry);
      if (sound != null) {
        _lock = true;
        await _playSound(sound);
        _lock = false;
      }
    }
  }

  Future<void> synthesizeSpeech(String text) async {
    try {
      await flutterTts.speak(text);
    } catch (_) {}
  }

  Future<void> _playSound(String sound) async {
    // Actual audio playback is platform specific.  For the purposes of the
    // port we simply print the requested sound file.
    print('Trigger sound $sound');
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
