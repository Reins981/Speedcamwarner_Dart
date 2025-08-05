import 'dart:async';
import 'dart:collection';

/// Queue structure mirroring the Python `VoicePromptQueue`.  Individual
/// categories are stored in their own [Queue] and consumers wait on a broadcast
/// stream until any queue receives an item.
class VoicePromptQueue {
  final Queue<String> _gpsSignalQueue = Queue();
  final Queue<String> _maxSpeedExceededQueue = Queue();
  final Queue<String> _onlineQueue = Queue();
  final Queue<String> _poiQueue = Queue();
  final Queue<String> _cameraQueue = Queue();
  final Queue<String> _infoQueue = Queue();
  final Queue<String> _arQueue = Queue();

  final StreamController<void> _notifier = StreamController<void>.broadcast();

  void _notify() => _notifier.add(null);

  /// Wait until any queue has an item and return the highest‑priority entry.
  Future<String> consumeItems() async {
    while (true) {
      final item = _dequeue();
      if (item != null) return item;
      await _notifier.stream.first;
    }
  }

  String? _dequeue() {
    if (_cameraQueue.isNotEmpty && _gpsSignalQueue.isNotEmpty) {
      _gpsSignalQueue.removeLast();
      return _cameraQueue.removeLast();
    }
    if (_cameraQueue.isNotEmpty && _infoQueue.isNotEmpty) {
      _infoQueue.removeLast();
      return _cameraQueue.removeLast();
    }
    if (_cameraQueue.isNotEmpty && _onlineQueue.isNotEmpty) {
      _onlineQueue.removeLast();
      return _cameraQueue.removeLast();
    }
    if (_cameraQueue.isNotEmpty) return _cameraQueue.removeLast();
    if (_arQueue.isNotEmpty) return _arQueue.removeLast();
    if (_gpsSignalQueue.isNotEmpty &&
        _maxSpeedExceededQueue.isNotEmpty &&
        _onlineQueue.isNotEmpty) {
      _gpsSignalQueue.removeLast();
      _onlineQueue.removeLast();
      return _maxSpeedExceededQueue.removeLast();
    }
    if (_gpsSignalQueue.isNotEmpty && _maxSpeedExceededQueue.isNotEmpty) {
      _gpsSignalQueue.removeLast();
      return _maxSpeedExceededQueue.removeLast();
    }
    if (_gpsSignalQueue.isNotEmpty && _onlineQueue.isNotEmpty) {
      _onlineQueue.removeLast();
      return _gpsSignalQueue.removeLast();
    }
    if (_maxSpeedExceededQueue.isNotEmpty && _onlineQueue.isNotEmpty) {
      _onlineQueue.removeLast();
      return _maxSpeedExceededQueue.removeLast();
    }
    if (_maxSpeedExceededQueue.isNotEmpty) {
      return _maxSpeedExceededQueue.removeLast();
    }
    if (_gpsSignalQueue.isNotEmpty) {
      return _gpsSignalQueue.removeLast();
    }
    if (_onlineQueue.isNotEmpty) {
      return _onlineQueue.removeLast();
    }
    if (_poiQueue.isNotEmpty) {
      return _poiQueue.removeLast();
    }
    if (_infoQueue.isNotEmpty) {
      return _infoQueue.removeLast();
    }
    return null;
  }

  void produceGpsSignal(String item) {
    _gpsSignalQueue.add(item);
    _notify();
  }

  void produceInfo(String item) {
    _infoQueue.add(item);
    _notify();
  }

  void produceMaxSpeedExceeded(String item) {
    _maxSpeedExceededQueue.add(item);
    _notify();
  }

  void produceOnlineStatus(String item) {
    _onlineQueue.add(item);
    _notify();
  }

  void producePoiStatus(String item) {
    _poiQueue.add(item);
    _notify();
  }

  void produceArStatus(String item) {
    _arQueue.add(item);
    _notify();
  }

  void produceCameraStatus(String item) {
    _cameraQueue.add(item);
    _notify();
  }

  void clearGpsSignalQueue() => _gpsSignalQueue.clear();
  void clearMaxSpeedExceededQueue() => _maxSpeedExceededQueue.clear();
  void clearOnlineQueue() => _onlineQueue.clear();
  void clearPoiQueue() => _poiQueue.clear();
  void clearCameraQueue() => _cameraQueue.clear();
  void clearInfoQueue() => _infoQueue.clear();
  void clearArQueue() => _arQueue.clear();
}
