import 'dart:async';

/// Broadcasts voice prompt events to interested listeners.
///
/// Producers emit events via [emit] while consumers subscribe to [stream].
class VoicePromptEvents {
  final StreamController<dynamic> _controller =
      StreamController<dynamic>.broadcast();

  /// Stream of all voice prompt entries.
  Stream<dynamic> get stream => _controller.stream;

  /// Emit a new voice prompt [event].
  void emit(dynamic event) => _controller.add(event);

  /// Close the underlying stream controller.
  Future<void> dispose() => _controller.close();
}
