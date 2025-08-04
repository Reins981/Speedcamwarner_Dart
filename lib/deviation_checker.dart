import 'dart:async';

class DeviationChecker {
  bool firstBearingSetAvailable = false;
  double avBearing = 0.0;
  double avBearingCurrent = 0.0;
  double avBearingPrev = 0.0;
  final StreamController<String> interruptQueue =
      StreamController<String>.broadcast();

  void process(List<double> currentBearingQueue) {
    if (currentBearingQueue.isEmpty) {
      updateAverageBearing('0');
      return;
    }

    calculateAverageBearing(currentBearingQueue);
  }

  void calculateAverageBearing(List<double> currentBearingQueue) {
    avBearing = currentBearingQueue.reduce((a, b) => a + b);
    double avBearingFinal = avBearing / currentBearingQueue.length;

    updateAverageBearing(avBearingFinal.toStringAsFixed(1));

    if (!firstBearingSetAvailable) {
      firstBearingSetAvailable = true;
      avBearingCurrent = avBearingFinal;
    } else {
      avBearingPrev = avBearingCurrent;
      avBearingCurrent = avBearingFinal;

      double avBearingDiffPositionPairQueues = avBearingCurrent - avBearingPrev;
      double avBearingDiffCurrentQueue =
          currentBearingQueue.first - avBearingCurrent;

      if ((-22 <= avBearingDiffPositionPairQueues &&
              avBearingDiffPositionPairQueues <= 22) &&
          (-13 <= avBearingDiffCurrentQueue &&
              avBearingDiffCurrentQueue <= 13)) {
        interruptQueue.add('STABLE');
        print('CCP is considered STABLE');
      } else {
        interruptQueue.add('UNSTABLE');
        print('Waiting for CCP to become STABLE again');
      }
    }
  }

  void updateAverageBearing(String avBearing) {
    print('Updated Average Bearing: $avBearing°');
  }

  void dispose() {
    interruptQueue.close();
  }
}

extension DeviationCheckerExtensions on DeviationChecker {
  Stream<String> get interruptQueueStream => interruptQueue.stream;

  void run() {
    print('DeviationChecker is running.');
  }

  void terminate() {
    print('DeviationChecker is terminating.');
    dispose();
  }
}
