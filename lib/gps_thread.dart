import 'dart:async';

import 'logger.dart';
import 'rectangle_calculator.dart';
import 'voice_prompt_queue.dart';
import 'config.dart';

/// Simplified port of the GPS handling thread from the Python code base.  The
/// original application relied on OS threads and condition variables to push
/// GPS samples into the calculation pipeline.  In Dart we model this as a
/// [Stream] of [VectorData] objects.  Consumers may listen to [stream] or
/// forward the events to [RectangleCalculatorThread.addVectorSample].
class GpsThread extends Logger {
  GpsThread({this.voicePromptQueue, double? accuracyThreshold})
      : accuracyThreshold =
            (accuracyThreshold ??
                    AppConfig.get<num>('gpsThread.gps_inaccuracy_treshold') ??
                    4)
                .toDouble(),
        gpsTestData = AppConfig.get<bool>('gpsThread.gps_test_data') ?? false,
        maxGpsEntries =
            (AppConfig.get<num>('gpsThread.max_gps_entries') ?? 50000).toInt(),
        gpxFile = AppConfig.get<String>('gpsThread.gpx_file') ??
            'python/gpx/Weekend_Karntner_5SeenTour.gpx',
        gpsTreshold =
            (AppConfig.get<num>('gpsThread.gps_treshold') ?? 40).toDouble(),
        recording = AppConfig.get<bool>('gpsThread.recording') ?? false,
        super('GpsThread');

  final VoicePromptQueue? voicePromptQueue;
  final double accuracyThreshold;
  final bool gpsTestData;
  final int maxGpsEntries;
  final String gpxFile;
  final double gpsTreshold;
  bool recording;

  final StreamController<VectorData> _controller =
      StreamController<VectorData>.broadcast();
  StreamSubscription<VectorData>? _sourceSub;
  bool _running = false;
  String? _lastSignal;

  /// Indicates whether the GPS thread is currently running.
  bool get isRunning => _running;

  /// Stream of incoming [VectorData] samples.
  Stream<VectorData> get stream => _controller.stream;

  /// Start emitting samples.  If a [source] stream is provided its events are
  /// forwarded to listeners.  Otherwise samples can be pushed manually via
  /// [addSample].
  void start({Stream<VectorData>? source}) {
    if (_running) return;
    _running = true;
    printLogLine(
        'GPS thread started testData=$gpsTestData maxEntries=$maxGpsEntries recording=$recording threshold=$gpsTreshold');
    _sourceSub = source?.listen((event) {
      if (_running) {
        printLogLine(
            'Forwarding vector ${event.latitude}, ${event.longitude}, speed ${event.speed}');
        _handleSample(event);
      }
    });
  }

  /// Push a single [VectorData] sample into the GPS stream.
  void addSample(VectorData vector) {
    if (_running) {
      printLogLine(
          'Manually added sample ${vector.latitude}, ${vector.longitude}, speed ${vector.speed}');
      _handleSample(vector);
    }
  }

  /// Stop emitting samples but keep the stream open for a possible restart.
  Future<void> stop() async {
    _running = false;
    printLogLine('GPS thread stopping');
    await _sourceSub?.cancel();
    _sourceSub = null;
    if (voicePromptQueue != null && _lastSignal != 'GPS_OFF') {
      voicePromptQueue!.produceGpsSignal('GPS_OFF');
      _lastSignal = 'GPS_OFF';
    }
  }

  /// Permanently dispose the underlying stream controller.
  Future<void> dispose() async {
    await _sourceSub?.cancel();
    await _controller.close();
  }

  void _handleSample(VectorData vector) {
    _controller.add(vector);
    if (voicePromptQueue != null) {
      String signal;
      if (vector.gpsStatus != 1) {
        signal = 'GPS_OFF';
      } else if (vector.accuracy > accuracyThreshold) {
        signal = 'GPS_LOW';
      } else {
        signal = 'GPS_ON';
      }
      if (signal != _lastSignal) {
        voicePromptQueue!.produceGpsSignal(signal);
        _lastSignal = signal;
      }
    }
  }
}
