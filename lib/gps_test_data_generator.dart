import 'dart:io';
import 'dart:math';

import 'package:gpx/gpx.dart';

/// Generates mock GPS events for testing.
///
/// The generator can either create a list of synthetic GPS events or read
/// events from a provided GPX file. Instances of this class are iterable so the
/// generated events can be consumed with standard iteration constructs.
class GpsTestDataGenerator extends Iterable<Map<String, dynamic>> {
  /// Collected GPS events.
  final List<Map<String, dynamic>> events = [];

  final Random _random = Random();

  /// Index used when iterating with [next].
  int _eventIndex = -1;

  /// Flag kept for parity with the original Python implementation.
  bool startup = true;

  /// Creates a [GpsTestDataGenerator].
  ///
  /// If [gpxFile] is provided, events will be created from the GPX file.
  /// Otherwise [maxNum] synthetic events are generated.
  GpsTestDataGenerator({int maxNum = 50000, String? gpxFile}) {
    if (gpxFile != null) {
      _fillEventsFromGpx(gpxFile);
    } else {
      _fillEvents(maxNum);
    }
  }

  /// Populates [events] from entries of the GPX file at [gpxFile].
  void _fillEventsFromGpx(String gpxFile) {
    print(' Generating Test GPS Data from $gpxFile....');

    final gpxString = File(gpxFile).readAsStringSync();
    final gpx = GpxReader().fromString(gpxString);

    for (final track in gpx.trks) {
      for (final segment in track.trksegs) {
        for (final point in segment.trkpts) {
          print('Point at (${point.lat},${point.lon}) -> ${point.ele}');
          events.add({
            'data': {
              'gps': {
                'accuracy': _random.nextInt(24) + 2,
                'latitude': point.lat,
                'longitude': point.lon,
                'speed': point.speed ?? (_random.nextInt(26) + 10),
                'bearing': _random.nextInt(51) + 200,
              },
            },
            'name': 'location',
          });
        }
      }
    }
  }

  /// Generates [maxNum] synthetic GPS events.
  void _fillEvents(int maxNum) {
    print('Generating $maxNum Test GPS Data....');

    double startLat = 51.509865; // Starting location (e.g., London)
    double startLong = -0.118092;
    const double i = 0.0000110;
    const double j = 0.0000110;
    int counter = 0;
    int bearing = 15;

    for (int _ = 0; _ < maxNum; _++) {
      events.add({
        'data': {
          'gps': {
            'accuracy': _random.nextInt(9),
            'latitude': startLat,
            'longitude': startLong,
            'speed': _random.nextInt(26) + 10,
            'bearing': bearing,
          },
        },
        'name': 'location',
      });

      counter += 1;
      if (counter > 1000) {
        startLat -= i;
        startLong -= j;
        bearing = 180;
      } else {
        startLat += i;
        startLong += j;
      }
    }
  }

  /// Returns the next event in [events].
  ///
  /// Throws a [StateError] when no more events are available.
  Map<String, dynamic> next() {
    _eventIndex += 1;
    if (_eventIndex < events.length) {
      return events[_eventIndex];
    }
    throw StateError('No more events');
  }

  /// Provides iteration over the generated events.
  @override
  Iterator<Map<String, dynamic>> get iterator => events.iterator;

  @override
  String toString() => events.toString();
}

