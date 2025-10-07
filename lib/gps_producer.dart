import "dart:async";
import "rectangle_calculator.dart";

class GpsProducer {
  String? _direction;
  double? _longitude;
  double? _latitude;

  final StreamController<double> _maxAccelController =
      StreamController<double>.broadcast();

  Stream<double> get maxAccelStream => _maxAccelController.stream;

  void update(VectorData vector) {
    _direction = vector.direction;
    _longitude = vector.longitude;
    _latitude = vector.latitude;
  }

  void setMaxAccelerationStream(Stream<double> stream) {
    stream.listen((acceleration) {
      _maxAccelController.add(acceleration);
    });
  }

  String? get_direction() => _direction;

  List<double> get_lon_lat() => [_longitude ?? 0.0, _latitude ?? 0.0];
}
