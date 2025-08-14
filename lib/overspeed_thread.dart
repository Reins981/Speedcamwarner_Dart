import 'dart:async';
import 'dart:collection';

import 'logger.dart';

class ThreadCondition {
  bool terminate;
  ThreadCondition({this.terminate = false});
}

abstract class SpeedLayout {
  void resetOverspeed();
  void updateOverspeed(int value);
}

class OverspeedThread extends Logger {
  final ThreadCondition cond;
  final bool Function() isResumed;
  final SpeedLayout speedLayout;
  final bool Function()? runInBackground;
  final Future<void> Function()? waitForMainEvent;

  final Queue<dynamic> _currentSpeedQueue = Queue<dynamic>();
  final Queue<Map<String, dynamic>> _overspeedQueue =
      Queue<Map<String, dynamic>>();
  final StreamController<void> _currentSpeedNotifier =
      StreamController<void>.broadcast();
  final StreamController<void> _overspeedNotifier =
      StreamController<void>.broadcast();

  int? lastMaxSpeed;
  bool _running = false;

  OverspeedThread({
    required this.cond,
    required this.isResumed,
    required this.speedLayout,
    this.runInBackground,
    this.waitForMainEvent,
    StreamController<String>? logViewer,
  }) : super('OverspeedThread', logViewer: logViewer);

  void addCurrentSpeed(dynamic speed) {
    _currentSpeedQueue.add(speed);
    _currentSpeedNotifier.add(null);
  }

  void addOverspeedEntry(Map<String, dynamic> entry) {
    _overspeedQueue.add(entry);
    _overspeedNotifier.add(null);
  }

  void clearQueues() {
    _currentSpeedQueue.clear();
    _overspeedQueue.clear();
  }

  Future<void> run() async {
    _running = true;
    while (_running && !cond.terminate) {
      if (runInBackground?.call() ?? false) {
        await (waitForMainEvent?.call() ?? Future.value());
      }
      if (!isResumed()) {
        _currentSpeedQueue.clear();
        _overspeedQueue.clear();
        await Future.delayed(const Duration(milliseconds: 50));
        continue;
      }
      final status = await process();
      if (status == 'TERMINATE') {
        break;
      }
    }
    _overspeedQueue.clear();
    _currentSpeedQueue.clear();
    printLogLine('$runtimeType terminating');
    _running = false;
  }

  Future<String?> process() async {
    final currentSpeed = await _consumeCurrentSpeed();
    printLogLine('Received Current Speed: $currentSpeed');

    if (currentSpeed == null) {
      return null;
    }

    if (currentSpeed is String && currentSpeed == 'EXIT') {
      return 'TERMINATE';
    }

    final overspeedEntry = await _consumeOverspeedEntry();

    for (final entry in overspeedEntry.entries) {
      var maxSpeed = entry.value;
      printLogLine('Received Max Speed: $maxSpeed');

      if (maxSpeed is String && maxSpeed.contains('mph')) {
        maxSpeed = int.parse(maxSpeed.replaceAll(' mph', ''));
      }

      if (maxSpeed is int) {
        lastMaxSpeed = maxSpeed;
        _calculate(currentSpeed, maxSpeed);
      }
    }

    if (overspeedEntry.isEmpty && lastMaxSpeed != null) {
      printLogLine(
          ' Recalculating over speed entry according to last max speed');
      _calculate(currentSpeed, lastMaxSpeed!);
    }
    return null;
  }

  Future<dynamic> _consumeCurrentSpeed() async {
    while (_currentSpeedQueue.isEmpty) {
      await _currentSpeedNotifier.stream.first;
    }
    return _currentSpeedQueue.removeFirst();
  }

  Future<Map<String, dynamic>> _consumeOverspeedEntry() async {
    while (_overspeedQueue.isEmpty) {
      await _overspeedNotifier.stream.first;
    }
    return _overspeedQueue.removeFirst();
  }

  void _calculate(int currentSpeed, int maxSpeed) {
    if (currentSpeed > maxSpeed) {
      printLogLine(
          ' Driver is too fast: expected speed $maxSpeed, actual speed $currentSpeed');
      _processEntry(currentSpeed - maxSpeed);
    } else {
      _processEntry(10000);
    }
  }

  void _processEntry(int value) {
    if (value == 10000) {
      speedLayout.resetOverspeed();
    } else {
      speedLayout.updateOverspeed(value);
    }
  }

  Future<void> stop() async {
    _running = false;
    cond.terminate = true;
    await _currentSpeedNotifier.close();
    await _overspeedNotifier.close();
  }
}
