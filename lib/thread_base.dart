import 'dart:async';
import 'dart:collection';

/// Utilities ported from the original Python `ThreadBase` module.
///
/// The Python project implemented a large set of thread-synchronised queues and
/// helper classes for exchanging data between threads.  Dart does not expose
/// low level threading primitives, therefore the classes below use
/// [StreamController]s to notify waiting consumers whenever new data becomes
/// available.  Each queue mirrors the behaviour of its Python counterpart but
/// with a much smaller API surface that is easier to consume from asynchronous
/// Dart code.

/// Simple flag wrapper used throughout the original code base.
class ThreadCondition {
  bool terminate;
  ThreadCondition(this.terminate);

  void setTerminateState(bool state) => terminate = state;
}

/// Minimal stand-in for the Python `StoppableThread`.  In the Dart port the
/// long-running tasks are typically implemented with futures or streams, but
/// some callers still expect a class that can be stopped.
abstract class StoppableThread {
  bool _stopped = false;

  bool get isRunning => !_stopped;

  void stop() => _stopped = true;

  void stopSpecific() => stop();
}

class _NotifyingDeque<T> {
  final Queue<T> _queue = Queue<T>();
  final StreamController<void> _notifier =
      StreamController<void>.broadcast();

  bool get _hasItem => _queue.isNotEmpty;

  T _remove() => _queue.removeLast();

  void _add(T item) => _queue.addLast(item);

  void clear() {
    _queue.clear();
    _notifier.add(null);
  }

  Future<T> consume() async {
    while (!_hasItem) {
      await _notifier.stream.first;
    }
    return _remove();
  }

  void produce(T item) {
    _add(item);
    _notifier.add(null);
  }
}

class _NotifyingFifoQueue<T> {
  final Queue<T> _queue = Queue<T>();
  final StreamController<void> _notifier =
      StreamController<void>.broadcast();

  bool get _hasItem => _queue.isNotEmpty;

  T _remove() => _queue.removeFirst();

  void _add(T item) => _queue.addLast(item);

  void clear() {
    _queue.clear();
    _notifier.add(null);
  }

  Future<T?> consume() async {
    while (!_hasItem) {
      await _notifier.stream.first;
    }
    return _remove();
  }

  void produce(T item) {
    _add(item);
    _notifier.add(null);
  }

  int size() => _queue.length;
}

class InterruptQueue<T> {
  final _NotifyingDeque<T> _queue = _NotifyingDeque<T>();

  Future<T> consume() => _queue.consume();

  void produce(T item) => _queue.produce(item);

  void clear() => _queue.clear();
}

class OverspeedQueue<T> {
  final Queue<T> _queue = Queue<T>();

  T? consume() => _queue.isEmpty ? null : _queue.removeLast();

  void produce(T item) => _queue.addLast(item);

  void clear() => _queue.clear();
}

class PoiQueue<T> {
  final _NotifyingFifoQueue<T> _queue = _NotifyingFifoQueue<T>();

  Future<T?> consume() => _queue.consume();

  void produce(T item) => _queue.produce(item);

  void clear() => _queue.clear();

  int size() => _queue.size();
}

class GpsDataQueue<T> {
  final _NotifyingDeque<T> _queue = _NotifyingDeque<T>();

  Future<T> consume() => _queue.consume();

  void produce(T item) => _queue.produce(item);

  void clear() => _queue.clear();
}

class CurrentSpeedQueue<T> {
  final _NotifyingDeque<T> _queue = _NotifyingDeque<T>();

  Future<T> consume() => _queue.consume();

  void produce(T item) => _queue.produce(item);

  void clear() => _queue.clear();
}

class MapQueue<T> {
  final _NotifyingDeque<T> _mapQueue = _NotifyingDeque<T>();
  final Queue<T> _cameraQueueOsm = Queue<T>();
  final Queue<T> _camerasQueueCloud = Queue<T>();
  final Queue<T> _camerasQueueDb = Queue<T>();
  final Queue<T> _constructionAreaQueue = Queue<T>();

  Future<T> consume() => _mapQueue.consume();

  void produce(T item) => _mapQueue.produce(item);

  void clearMapUpdate() => _mapQueue.clear();

  List<T> consumeOsm() =>
      _cameraQueueOsm.isEmpty ? [] : [_cameraQueueOsm.removeFirst()];

  void produceOsm(T item) => _cameraQueueOsm.addLast(item);

  List<T> consumeConstruction() => _constructionAreaQueue.isEmpty
      ? []
      : [_constructionAreaQueue.removeFirst()];

  void produceConstruction(T item) => _constructionAreaQueue.addLast(item);

  List<T> consumeCloud() =>
      _camerasQueueCloud.isEmpty ? [] : [_camerasQueueCloud.removeFirst()];

  void produceCloud(T item) => _camerasQueueCloud.addLast(item);

  List<T> consumeDb() =>
      _camerasQueueDb.isEmpty ? [] : [_camerasQueueDb.removeFirst()];

  void produceDb(T item) => _camerasQueueDb.addLast(item);
}

class VectorDataPoolQueue {
  final Map<String, List<dynamic>> _vectorData = {};
  final _NotifyingDeque<Map<String, List<dynamic>>> _queue =
      _NotifyingDeque<Map<String, List<dynamic>>>();

  void setVectorData(String key, dynamic longitude, dynamic latitude,
      dynamic cspeed, dynamic bearing, dynamic direction, dynamic gpsstatus,
      dynamic accuracy) {
    final lon = longitude is double ? longitude : double.parse('$longitude');
    final lat = latitude is double ? latitude : double.parse('$latitude');
    final speed = cspeed is double ? cspeed : double.parse('$cspeed');
    final bear = bearing is double ? bearing : double.parse('$bearing');

    _vectorData[key] = [
      [lon, lat],
      speed,
      bear,
      direction,
      gpsstatus,
      accuracy
    ];
    _queue.produce(Map<String, List<dynamic>>.from(_vectorData));
  }

  Future<Map<String, List<dynamic>>> getVectorData() => _queue.consume();

  void clearVectorData() => _queue.clear();
}

class AverageAngleQueue<T> {
  final _NotifyingDeque<T> _queue = _NotifyingDeque<T>();

  void produce(T item) => _queue.produce(item);

  Future<T> getAverageAngleData() => _queue.consume();

  void clearAverageAngleData() => _queue.clear();
}

class GPSQueue<T> {
  final _NotifyingDeque<T> _queue = _NotifyingDeque<T>();

  Future<T> consume() => _queue.consume();

  void produce(T item) => _queue.produce(item);

  void clearGpsQueue() => _queue.clear();
}

class SpeedCamQueue<T> {
  final _NotifyingDeque<T> _queue = _NotifyingDeque<T>();

  Future<T> consume() => _queue.consume();

  void produce(T item) => _queue.produce(item);

  void clearCamQueue() => _queue.clear();
}

class TaskCounter {
  int _taskCounter = 0;

  void setTaskCounter() => _taskCounter++;

  int get taskCounter => _taskCounter;
}

class ResultMapper {
  final Map<int, dynamic> _serverResponse = {};

  Map<int, dynamic> get serverResponse => _serverResponse;

  void setServerResponse(int taskCounter, bool onlineAvailable, String status,
      dynamic data, String internalError, dynamic currentRect) {
    _serverResponse[taskCounter] =
        [onlineAvailable, status, data, internalError, currentRect];
  }

  void setBuildResponse(int taskCounter, dynamic currentRect) {
    _serverResponse[taskCounter] = currentRect;
  }

  void setGoogleDriveUploadResponse(int taskCounter, dynamic result) {
    _serverResponse[taskCounter] = result;
  }
}

