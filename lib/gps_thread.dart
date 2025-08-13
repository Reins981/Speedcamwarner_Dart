import 'dart:async';

import 'rectangle_calculator.dart';

/// Simplified port of the GPS handling thread from the Python code base.  The
/// original application relied on OS threads and condition variables to push
/// GPS samples into the calculation pipeline.  In Dart we model this as a
/// [Stream] of [VectorData] objects.  Consumers may listen to [stream] or
/// forward the events to [RectangleCalculatorThread.addVectorSample].
class GpsThread {
  final StreamController<VectorData> _controller =
      StreamController<VectorData>.broadcast();
  StreamSubscription<VectorData>? _sourceSub;
  bool _running = false;

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
    _sourceSub = source?.listen((event) {
      if (_running) {
        _controller.add(event);
      }
    });
  }

  /// Push a single [VectorData] sample into the GPS stream.
  void addSample(VectorData vector) {
    if (_running) {
      _controller.add(vector);
    }
  }

  /// Stop emitting samples but keep the stream open for a possible restart.
  Future<void> stop() async {
    _running = false;
    await _sourceSub?.cancel();
    _sourceSub = null;
  }

  /// Permanently dispose the underlying stream controller.
  Future<void> dispose() async {
    await _sourceSub?.cancel();
    await _controller.close();
  }
}
