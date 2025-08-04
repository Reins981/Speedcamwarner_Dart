import 'dart:math';

class GpsTestDataGenerator {
  final List<Map<String, dynamic>> events = [];
  final Random _random = Random();

  GpsTestDataGenerator({int maxNum = 50000}) {
    _fillEvents(maxNum);
  }

  void _fillEvents(int maxNum) {
    print("Generating $maxNum Test GPS Data....");

    // Start location (e.g., London)
    double startLat = 51.509865;
    double startLong = -0.118092;
    double i = 0.0000110;
    double j = 0.0000110;

    for (int counter = 0; counter < maxNum; counter++) {
      events.add({
        'data': {
          'gps': {
            'accuracy': _random.nextInt(9),
            'latitude': startLat,
            'longitude': startLong,
            'speed': _random.nextInt(26) + 10,
            'bearing': _random.nextInt(36) + 200,
          }
        },
        'name': 'location'
      });

      // Increment latitude and longitude for simulation
      startLat += i;
      startLong += j;
    }
  }

  List<Map<String, dynamic>> getEvents() {
    return events;
  }
}
