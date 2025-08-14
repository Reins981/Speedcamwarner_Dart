import 'dart:async';

import 'config.dart';

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

  final _markerRemovalController =
      StreamController<MarkerRemovalEvent>.broadcast();

  /// Stream of marker removal events emitted when obsolete cameras need to
  /// disappear from the map.
  Stream<MarkerRemovalEvent> get markerRemovals =>
      _markerRemovalController.stream;

  void setCalculatorThread(dynamic calculator) {
    this.calculator = calculator;
  }

  void setConfigs() {
    drawRects =
        AppConfig.get<bool>('osmWrapper.draw_rects') ??
            AppConfig.get<bool>('osmWrapperPorted.draw_rects') ??
            drawRects;
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

  /// Emit a [MarkerRemovalEvent] so listeners can purge outdated camera markers
  /// from their map widgets.  The actual map interaction happens wherever the
  /// event stream is consumed; this keeps the [Maps] class free of UI details
  /// and uses event controllers instead of legacy queues.
  void remove_marker_from_map(double lon, double lat) {
    _markerRemovalController.add(MarkerRemovalEvent(lon, lat));
  }

  /// Close the underlying [StreamController]. Should be called when the map is
  /// disposed to avoid memory leaks.
  Future<void> dispose() async {
    await _markerRemovalController.close();
  }
}

/// Event object describing a map marker that should be removed.
class MarkerRemovalEvent {
  final double lon;
  final double lat;

  MarkerRemovalEvent(this.lon, this.lat);
}
