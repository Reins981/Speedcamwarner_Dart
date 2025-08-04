import 'dart:math';

class SpeedCameraLogic {
  final Random _random = Random();

  // Simulate driving data
  List<Map<String, dynamic>> simulateDrivingData(
      Map<String, dynamic> cameraData, int numSamples) {
    List<Map<String, dynamic>> samples = [];
    for (int i = 0; i < numSamples; i++) {
      var camera =
          cameraData['cameras'][_random.nextInt(cameraData['cameras'].length)];
      var coordinates = camera['coordinates'][0];
      samples.add({
        'latitude': _randomInRange(
            coordinates['latitude'] - 0.01, coordinates['latitude'] + 0.01),
        'longitude': _randomInRange(
            coordinates['longitude'] - 0.01, coordinates['longitude'] + 0.01),
        'time_of_day': _randomTimeOfDay(),
        'day_of_week': _randomDayOfWeek(),
        'camera_latitude': coordinates['latitude'],
        'camera_longitude': coordinates['longitude']
      });
    }
    return samples;
  }

  // Helper to generate a random value in a range
  double _randomInRange(double min, double max) {
    return min + _random.nextDouble() * (max - min);
  }

  // Helper to pick a random time of day
  String _randomTimeOfDay() {
    const times = ['morning', 'afternoon', 'evening', 'night'];
    return times[_random.nextInt(times.length)];
  }

  // Helper to pick a random day of the week
  String _randomDayOfWeek() {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return days[_random.nextInt(days.length)];
  }
}
