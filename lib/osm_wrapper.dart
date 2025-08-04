class Maps {
  dynamic calculator;
  bool drawRects = true;
  double? centerLat;
  double? centerLng;
  double? heading;
  double? bearing;
  double? accuracy;
  List<dynamic> geoBoundsExtrapolated = [];
  List<dynamic> geoBounds = [];

  void setCalculatorThread(dynamic calculator) {
    this.calculator = calculator;
  }

  void setConfigs() {
    drawRects = true;
  }

  void osmUpdateCenter(double lat, double lng) {
    centerLat = lat;
    centerLng = lng;
  }

  void osmUpdateHeading(double heading) {
    this.heading = heading;
  }

  void osmUpdateBearing(double bearing) {
    this.bearing = bearing;
  }

  void osmUpdateAccuracy(double accuracy) {
    this.accuracy = accuracy;
  }

  void osmUpdateGeoBoundsExtrapolated(
      dynamic geoBounds, dynamic mostPropableHeading, String rectName) {
    geoBoundsExtrapolated.add([geoBounds, mostPropableHeading, rectName]);
  }

  void osmUpdateGeoBounds(
      dynamic geoBounds, dynamic mostPropableHeading, String rectName,
      {bool clear = false}) {
    if (clear) {
      this.geoBounds.clear();
    }
    this.geoBounds.add([geoBounds, mostPropableHeading, rectName]);
  }
}
