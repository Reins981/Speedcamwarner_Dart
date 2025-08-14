import 'dart:async';

import 'rectangle_calculator.dart';
import 'voice_prompt_events.dart';
import 'logger.dart';

/// Simplified speed camera warner that reacts to camera events emitted by the
/// [RectangleCalculatorThread].
class SpeedCamWarner {
  final dynamic resume;
  final VoicePromptEvents voicePromptEvents;
  final dynamic osmWrapper;
  final RectangleCalculatorThread calculator;

  final Logger logger = Logger('SpeedCamWarner');

  final Set<String> _seenCameras = <String>{};
  StreamSubscription<SpeedCameraEvent>? _sub;

  SpeedCamWarner({
    required this.resume,
    required this.voicePromptEvents,
    required this.osmWrapper,
    required this.calculator,
  });

  /// Start listening for camera events.
  Future<void> run() async {
    logger.printLogLine('SpeedCamWarner thread started');
    _sub = calculator.cameras.listen(_onCamera);
  }

  /// Stop listening for camera events.
  Future<void> stop() async {
    await _sub?.cancel();
    logger.printLogLine('SpeedCamWarner terminating');
  }

  void _onCamera(SpeedCameraEvent cam) {
    final key = '${cam.latitude},${cam.longitude}';
    if (_seenCameras.contains(key)) return;
    _seenCameras.add(key);
    updateSpeedcam(cam);
  }

  /// Forward the camera type to the [VoicePromptEvents] stream.
  void updateSpeedcam(SpeedCameraEvent cam) {
    voicePromptEvents.emit({'type': _typeFor(cam), 'name': cam.name});
  }

  String _typeFor(SpeedCameraEvent cam) {
    if (cam.fixed) return 'fix';
    if (cam.traffic) return 'traffic';
    if (cam.distance) return 'distance';
    if (cam.mobile) return 'mobile';
    return 'unknown';
  }
}

