import "rectangle_calculator.dart";
class GpsProducer {
  String? _direction;
  double? _longitude;
  double? _latitude;

  void update(VectorData vector) {
    _direction = vector.direction;
    _longitude = vector.longitude;
    _latitude = vector.latitude;
  }

  String? get_direction() => _direction;

  List<double> get_lon_lat() => [_longitude ?? 0.0, _latitude ?? 0.0];
}
