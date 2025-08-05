import 'dart:async';

/// Minimal thread-pool style helper built on top of Dart's [Future] API. The
/// original Python project used ``concurrent.futures`` to run blocking
/// lookups in parallel.  In Dart we can achieve similar behaviour by spawning
/// multiple futures and waiting for them to complete with [Future.wait].
class ThreadPool {
  final List<Future> _active = [];

  /// Start a collection of tasks returned by [createTasks] and wait for all to
  /// complete.  The results are returned in the same order as the tasks.  Each
  /// invocation stores the futures in [_active] so callers may later await
  /// [checkWorkerThreadStatus] to ensure the pool is idle.
  Future<List<T>> startThreadPoolLookup<T>(
      List<Future<T>> Function() createTasks) {
    final tasks = createTasks();
    _active.addAll(tasks);
    return Future.wait(tasks);
  }

  /// Await completion of all active tasks.  This mirrors the status checks in
  /// the original thread-pool implementation.
  Future<void> checkWorkerThreadStatus() async {
    if (_active.isEmpty) return;
    await Future.wait(_active);
    _active.clear();
  }
}

/// Run a speed‑camera lookup asynchronously for the provided [lookup] callback.
/// The callback receives a context object [arg] and must return a list of
/// results.  The helper simply forwards the call but keeps the API similar to
/// the Python implementation where it was dispatched on a background thread.
Future<List<T>> speedCamLookupAhead<T, A>(A arg,
    Future<List<T>> Function(A) lookup) async {
  return lookup(arg);
}

/// Run a construction‑area lookup asynchronously.  Identical to
/// [speedCamLookupAhead] but kept separate for clarity.
Future<List<T>> constructionsLookupAhead<T, A>(A arg,
    Future<List<T>> Function(A) lookup) async {
  return lookup(arg);
}
