import 'thread_base.dart';

/// Minimal placeholder for the original Python OSM thread.
/// It currently performs no work but keeps the start/stop lifecycle
/// compatible with the rest of the application.
class OsmThread {
  final ThreadCondition cond;
  bool _running = false;

  OsmThread({ThreadCondition? cond}) : cond = cond ?? ThreadCondition(false);

  Future<void> run() async {
    _running = true;
    while (_running && !(cond.terminate)) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> stop() async {
    _running = false;
    cond.setTerminateState(true);
  }
}
