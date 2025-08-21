import 'dart:async';
import 'package:flutter/foundation.dart';

import 'logger.dart';

class ThreadCondition {
  bool terminate;
  ThreadCondition({this.terminate = false});
}

class DeviationCheckerThread extends Logger {
  bool firstBearingSetAvailable = false;
  double avBearing = 0.0;
  double avBearingCurrent = 0.0;
  double avBearingPrev = 0.0;

  final ThreadCondition cond;
  final ThreadCondition condAr;
  final ValueNotifier<String> avBearingValue;
  bool isResumed;

  final StreamController<dynamic> _averageAngleController =
      StreamController<dynamic>();
  final StreamController<String> interruptController =
      StreamController<String>.broadcast();

  Stream<String> get stream => interruptController.stream;

  bool _running = false;
  StreamSubscription? _avgSub;

  DeviationCheckerThread({
    required this.cond,
    required this.condAr,
    required this.avBearingValue,
    this.isResumed = true,
    StreamController<String>? logViewer,
  }) : super('DeviationCheckerThread', logViewer: logViewer);

  void addAverageAngleData(dynamic data) {
    if (_averageAngleController.isClosed) {
      return;
    }
    _averageAngleController.add(data);
  }

  void start() {
    if (_running) return;
    _running = true;
    _avgSub = _averageAngleController.stream.listen((data) {
      if (_running) {
        process(data);
      }
    });
    _runLoop();
  }

  Future<void> _runLoop() async {
    while (_running && !cond.terminate && !condAr.terminate) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    cleanup();
    if (cond.terminate) {
      interruptController.add('TERMINATE');
    }
    if (condAr.terminate) {
      interruptController.add('CLEAR');
    }
    printLogLine('$runtimeType terminating');
    await dispose();
  }

  void cleanup() {
    firstBearingSetAvailable = false;
  }

  void process(dynamic currentBearingQueue) {
    calculateAverageBearing(currentBearingQueue);
  }

  void calculateAverageBearing(dynamic currentBearingQueue) {
    avBearing = 0.0;

    if (currentBearingQueue is num) {
      if (currentBearingQueue == 0.001) {
        if (isResumed) {
          updateAverageBearing('---.-');
        }
        return;
      } else if (currentBearingQueue == 0.002) {
        printLogLine('Deviation Checker Thread got a termination item');
        return;
      } else if (currentBearingQueue == 0.0) {
        if (isResumed) {
          updateAverageBearing('0');
        }
        return;
      }
    } else if (currentBearingQueue == 'TERMINATE') {
      return;
    }

    if (currentBearingQueue is! List<double> || currentBearingQueue.isEmpty) {
      return;
    }

    for (final entry in currentBearingQueue) {
      avBearing += entry;
    }

    final double avBearingFinal = avBearing / currentBearingQueue.length;

    if (isResumed) {
      updateAverageBearing(avBearingFinal.toStringAsFixed(1));
    }

    final double avFirstEntry = currentBearingQueue.first;
    final double firstAvEntryCurrent = avFirstEntry;

    if (!firstBearingSetAvailable) {
      firstBearingSetAvailable = true;
      avBearingCurrent = avBearingFinal;
    } else {
      avBearingPrev = avBearingCurrent;
      avBearingCurrent = avBearingFinal;

      final double avBearingDiffPositionPairQueues =
          avBearingCurrent - avBearingPrev;
      final double avBearingDiffCurrentQueue =
          firstAvEntryCurrent - avBearingCurrent;

      if ((-22 <= avBearingDiffPositionPairQueues &&
              avBearingDiffPositionPairQueues <= 22) &&
          (-13 <= avBearingDiffCurrentQueue &&
              avBearingDiffCurrentQueue <= 13)) {
        interruptController.add('STABLE');
        printLogLine('CCP is considered STABLE');
      } else {
        interruptController.add('UNSTABLE');
        printLogLine('Waiting for CCP to become STABLE again');
      }
    }
  }

  void updateAverageBearing(String avBearing) {
    Future.microtask(() {
      avBearingValue.value = '$avBearing°';
    });
  }

  Future<void> dispose() async {
    _running = false;
    await _avgSub?.cancel();
    await _averageAngleController.close();
    await interruptController.close();
  }

  void terminate() {
    cond.terminate = true;
    condAr.terminate = true;
  }
}
