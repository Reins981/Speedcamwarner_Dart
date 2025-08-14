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

/// Wrapper that tags queue items with the time they were enqueued.
///
/// Consumers can use the [timestamp] to detect and discard stale data if
/// necessary.  The timestamp is captured when the instance is created.
class Timestamped<T> {
  Timestamped(this.data) : timestamp = DateTime.now();

  /// Payload carried through the queue.
  final T data;

  /// Moment when [data] was added to the queue.
  final DateTime timestamp;
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
  final StreamController<Timestamped<T>> _events =
      StreamController<Timestamped<T>>.broadcast();

  /// Stream of interrupt items tagged with enqueue timestamps.
  Stream<Timestamped<T>> get stream => _events.stream;

  Future<T> consume() => _queue.consume();

  void produce(T item) {
    _queue.produce(item);
    _events.add(Timestamped<T>(item));
  }

  void clear() => _queue.clear();

  Future<void> dispose() => _events.close();
}

class OverspeedQueue<T> {
  final Queue<T> _queue = Queue<T>();
  final StreamController<Timestamped<T>> _events =
      StreamController<Timestamped<T>>.broadcast();

  /// Stream of overspeed events with enqueue timestamps.
  Stream<Timestamped<T>> get stream => _events.stream;

  T? consume() => _queue.isEmpty ? null : _queue.removeLast();

  void produce(T item) {
    _queue.addLast(item);
    _events.add(Timestamped<T>(item));
  }

  void clear() => _queue.clear();

  Future<void> dispose() => _events.close();
}

class PoiQueue<T> {
  final _NotifyingFifoQueue<T> _queue = _NotifyingFifoQueue<T>();
  final StreamController<Timestamped<T>> _events =
      StreamController<Timestamped<T>>.broadcast();

  /// Stream mirroring produced POI items.
  Stream<Timestamped<T>> get stream => _events.stream;

  Future<T?> consume() => _queue.consume();

  void produce(T item) {
    _queue.produce(item);
    _events.add(Timestamped<T>(item));
  }

  void clear() => _queue.clear();

  int size() => _queue.size();

  Future<void> dispose() => _events.close();
}

class GpsDataQueue<T> {
  final _NotifyingDeque<T> _queue = _NotifyingDeque<T>();
  final StreamController<Timestamped<T>> _events =
      StreamController<Timestamped<T>>.broadcast();

  /// Stream of GPS samples with timestamps.
  Stream<Timestamped<T>> get stream => _events.stream;

  Future<T> consume() => _queue.consume();

  void produce(T item) {
    _queue.produce(item);
    _events.add(Timestamped<T>(item));
  }

  void clear() => _queue.clear();

  Future<void> dispose() => _events.close();
}

class CurrentSpeedQueue<T> {
  final _NotifyingDeque<T> _queue = _NotifyingDeque<T>();
  final StreamController<Timestamped<T>> _events =
      StreamController<Timestamped<T>>.broadcast();

  /// Stream of current speed updates.
  Stream<Timestamped<T>> get stream => _events.stream;

  Future<T> consume() => _queue.consume();

  void produce(T item) {
    _queue.produce(item);
    _events.add(Timestamped<T>(item));
  }

  void clear() => _queue.clear();

  Future<void> dispose() => _events.close();
}

class MapQueue<T> {
  final _NotifyingDeque<T> _mapQueue = _NotifyingDeque<T>();
  final Queue<T> _cameraQueueOsm = Queue<T>();
  final Queue<T> _camerasQueueCloud = Queue<T>();
  final Queue<T> _camerasQueueDb = Queue<T>();
  final Queue<T> _constructionAreaQueue = Queue<T>();

  final StreamController<Timestamped<T>> _mapEvents =
      StreamController<Timestamped<T>>.broadcast();
  final StreamController<Timestamped<T>> _osmEvents =
      StreamController<Timestamped<T>>.broadcast();
  final StreamController<Timestamped<T>> _constructionEvents =
      StreamController<Timestamped<T>>.broadcast();
  final StreamController<Timestamped<T>> _cloudEvents =
      StreamController<Timestamped<T>>.broadcast();
  final StreamController<Timestamped<T>> _dbEvents =
      StreamController<Timestamped<T>>.broadcast();

  /// Stream mirroring general map updates.
  Stream<Timestamped<T>> get stream => _mapEvents.stream;

  /// Stream of OSM camera updates.
  Stream<Timestamped<T>> get osmStream => _osmEvents.stream;

  /// Stream of construction area updates.
  Stream<Timestamped<T>> get constructionStream =>
      _constructionEvents.stream;

  /// Stream of cloud camera updates.
  Stream<Timestamped<T>> get cloudStream => _cloudEvents.stream;

  /// Stream of database camera updates.
  Stream<Timestamped<T>> get dbStream => _dbEvents.stream;

  Future<T> consume() => _mapQueue.consume();

  void produce(T item) {
    _mapQueue.produce(item);
    _mapEvents.add(Timestamped<T>(item));
  }

  void clearMapUpdate() => _mapQueue.clear();

  List<T> consumeOsm() =>
      _cameraQueueOsm.isEmpty ? [] : [_cameraQueueOsm.removeFirst()];

  void produceOsm(T item) {
    _cameraQueueOsm.addLast(item);
    _osmEvents.add(Timestamped<T>(item));
  }

  List<T> consumeConstruction() => _constructionAreaQueue.isEmpty
      ? []
      : [_constructionAreaQueue.removeFirst()];

  void produceConstruction(T item) {
    _constructionAreaQueue.addLast(item);
    _constructionEvents.add(Timestamped<T>(item));
  }

  List<T> consumeCloud() =>
      _camerasQueueCloud.isEmpty ? [] : [_camerasQueueCloud.removeFirst()];

  void produceCloud(T item) {
    _camerasQueueCloud.addLast(item);
    _cloudEvents.add(Timestamped<T>(item));
  }

  List<T> consumeDb() =>
      _camerasQueueDb.isEmpty ? [] : [_camerasQueueDb.removeFirst()];

  void produceDb(T item) {
    _camerasQueueDb.addLast(item);
    _dbEvents.add(Timestamped<T>(item));
  }

  Future<void> dispose() async {
    await _mapEvents.close();
    await _osmEvents.close();
    await _constructionEvents.close();
    await _cloudEvents.close();
    await _dbEvents.close();
  }
}

class VectorDataPoolQueue {
  final Map<String, List<dynamic>> _vectorData = {};
  final _NotifyingDeque<Map<String, List<dynamic>>> _queue =
      _NotifyingDeque<Map<String, List<dynamic>>>();
  final StreamController<Timestamped<Map<String, List<dynamic>>>> _events =
      StreamController<Timestamped<Map<String, List<dynamic>>>>.broadcast();

  /// Stream of vector data snapshots.
  Stream<Timestamped<Map<String, List<dynamic>>>> get stream =>
      _events.stream;

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
    final snapshot = Map<String, List<dynamic>>.from(_vectorData);
    _queue.produce(snapshot);
    _events.add(Timestamped<Map<String, List<dynamic>>>(snapshot));
  }

  Future<Map<String, List<dynamic>>> getVectorData() => _queue.consume();

  void clearVectorData() => _queue.clear();

  Future<void> dispose() => _events.close();
}

class AverageAngleQueue<T> {
  final _NotifyingDeque<T> _queue = _NotifyingDeque<T>();
  final StreamController<Timestamped<T>> _events =
      StreamController<Timestamped<T>>.broadcast();

  /// Stream of average angle updates.
  Stream<Timestamped<T>> get stream => _events.stream;

  void produce(T item) {
    _queue.produce(item);
    _events.add(Timestamped<T>(item));
  }

  Future<T> getAverageAngleData() => _queue.consume();

  void clearAverageAngleData() => _queue.clear();

  Future<void> dispose() => _events.close();
}

class GPSQueue<T> {
  final _NotifyingDeque<T> _queue = _NotifyingDeque<T>();
  final StreamController<Timestamped<T>> _events =
      StreamController<Timestamped<T>>.broadcast();

  /// Stream of GPS queue items.
  Stream<Timestamped<T>> get stream => _events.stream;

  Future<T> consume() => _queue.consume();

  void produce(T item) {
    _queue.produce(item);
    _events.add(Timestamped<T>(item));
  }

  void clearGpsQueue() => _queue.clear();

  Future<void> dispose() => _events.close();
}

class SpeedCamQueue<T> {
  final _NotifyingDeque<Timestamped<T>> _queue =
      _NotifyingDeque<Timestamped<T>>();
  final StreamController<Timestamped<T>> _events =
      StreamController<Timestamped<T>>.broadcast();

  /// Stream mirroring speed camera queue items.
  Stream<Timestamped<T>> get stream => _events.stream;

  /// Retrieve the next camera update along with its enqueue timestamp.
  Future<Timestamped<T>> consume() => _queue.consume();

  /// Add a new camera update, automatically tagging it with a timestamp.
  void produce(T item) {
    final ts = Timestamped<T>(item);
    _queue.produce(ts);
    _events.add(ts);
  }

  void clearCamQueue() => _queue.clear();

  Future<void> dispose() => _events.close();
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

