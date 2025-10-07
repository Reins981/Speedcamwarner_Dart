import "dart:async";
import "rectangle_calculator.dart";

class GpsProducer {
  String? _direction;
  double? _longitude;
  double? _latitude;
  double? _bearing;

  final StreamController<double> _maxAccelController =
      StreamController<double>.broadcast();

  Stream<double> get maxAccelStream => _maxAccelController.stream;

  final StreamController<List<double>> _currentCCPController =
      StreamController<List<double>>.broadcast();

  Stream<List<double>> get currentCCPStream => _currentCCPController.stream;

  void update(VectorData vector) {
    _direction = vector.direction;
    _longitude = vector.longitude;
    _latitude = vector.latitude;
    _bearing = vector.bearing.toDouble();
    _currentCCPController.add([_longitude ?? 0.0, _latitude ?? 0.0]);
  }

  void setMaxAccelerationStream(Stream<double> stream) {
    stream.listen((acceleration) {
      _maxAccelController.add(acceleration);
    });
  }

  String? get_direction() => _direction;

  double? get_bearing() => _bearing?.toDouble();

  List<double> get_lon_lat() => [_longitude ?? 0.0, _latitude ?? 0.0];
}
