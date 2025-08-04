import 'dart:math';

class SpeedCamWarner {
  final dynamic itemQueue;
  final dynamic calculator;
  final double emergencyAngleDistance;
  final double? ccpBearing;

  SpeedCamWarner({
    required this.itemQueue,
    required this.calculator,
    required this.emergencyAngleDistance,
    this.ccpBearing,
  });

  List<int>? convertCamDirection(dynamic camDir) {
    if (camDir == null) return null;

    List<int> camDirs = [];
    try {
      camDirs.add(int.parse(camDir.toString()));
    } catch (e) {
      for (var camD in camDir.toString().split(';')) {
        try {
          camDirs.add(int.parse(camD));
        } catch (e) {
          // Ignore invalid entries
        }
      }
    }

    return camDirs.isEmpty ? null : camDirs;
  }

  bool insideRelevantAngle(dynamic cam, double distanceToCamera) {
    try {
      var camDirection = itemQueue[cam][9];
      var camType = itemQueue[cam][0];

      if (distanceToCamera < emergencyAngleDistance) {
        print(
            "Emergency report triggered for Speed Camera '$camType' ($cam): Distance: $distanceToCamera m < $emergencyAngleDistance m");
        return true;
      }

      if (ccpBearing != null && camDirection != null) {
        var directionCcp = _calculateDirection(ccpBearing!);
        if (directionCcp == null) return true;

        var directions =
            camDirection.map((d) => _calculateDirection(d)).toList();
        if (directions.contains(directionCcp)) {
          return true;
        } else {
          print(
              "Speed Camera '$camType' ($cam): CCP bearing angle: $ccpBearing, Expected camera angle: $camDirection");
          return false;
        }
      }
    } catch (e) {
      return true;
    }
    return true;
  }

  double calculateAngle(List<double> pt1, List<double> pt2) {
    double lon1 = pt1[0], lat1 = pt1[1];
    double lon2 = pt2[0], lat2 = pt2[1];

    double xDiff = lon2 - lon1;
    double yDiff = lat2 - lat1;
    return (atan2(yDiff, xDiff) * (180 / pi)).abs();
  }

  bool cameraInsideCameraRectangle(dynamic cam) {
    var xtile = calculator.longlat2tile(cam[1], cam[0], calculator.zoom)[0];
    var ytile = calculator.longlat2tile(cam[1], cam[0], calculator.zoom)[1];

    var rectangle = calculator.rectSpeedCamLookahead;
    if (rectangle == null) return true;

    return rectangle.pointInRect(xtile, ytile);
  }

  double calculateCameraRectangleRadius() {
    var rectangle = calculator.rectSpeedCamLookahead;
    if (rectangle == null) return 0;

    return calculator.calculateRectangleRadius(
        rectangle.rectHeight(), rectangle.rectWidth());
  }

  double? _calculateDirection(double angle) {
    // Placeholder for direction calculation logic
    return angle;
  }
}
