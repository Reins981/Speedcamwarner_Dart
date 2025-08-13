import 'osm_wrapper.dart';
import 'thread_base.dart';

/// Minimal thread consuming map updates and forwarding them to [osmWrapper].
///
/// The original project used a separate OS thread to update the map display.
/// In this Dart port the heavy lifting is omitted – the thread merely drains
/// the [MapQueue] so producers don't block and can be cleanly shut down.
class OsmThread {
  final Maps osmWrapper;
  final MapQueue<dynamic> mapQueue;
  final ThreadCondition cond;

  OsmThread({
    required this.osmWrapper,
    required this.mapQueue,
    ThreadCondition? cond,
  }) : cond = cond ?? ThreadCondition(false);

  /// Continuously consume map updates until [stop] is called.
  Future<void> run() async {
    while (!(cond.terminate)) {
      final item = await mapQueue.consume();
      if (item == 'EXIT') {
        break;
      }
      // Map rendering is not implemented in this port; updates are ignored.
    }
    // ignore: avoid_print
    print('OsmThread terminating');
  }

  /// Signal the thread to terminate and unblock any pending [consume] call.
  Future<void> stop() async {
    cond.setTerminateState(true);
    mapQueue.produce('EXIT');
  }
}

