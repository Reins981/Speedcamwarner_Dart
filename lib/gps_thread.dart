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
  bool _running = false;

  /// Stream of incoming [VectorData] samples.
  Stream<VectorData> get stream => _controller.stream;

  /// Start emitting samples.  If a [source] stream is provided its events are
  /// forwarded to listeners.  Otherwise samples can be pushed manually via
  /// [addSample].
  void start({Stream<VectorData>? source}) {
    _running = true;
    source?.listen((event) {
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

  /// Stop emitting samples and close the underlying stream controller.
  Future<void> stop() async {
    _running = false;
    await _controller.close();
  }
}
