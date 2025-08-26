#!/usr/bin/env dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  if (args.length != 4) {
    stdout.writeln('[]');
    exit(1);
  }
  final latitude = double.parse(args[0]);
  final longitude = double.parse(args[1]);
  final timeOfDay = args[2];
  final dayOfWeek = args[3];
  final model = PredictiveModel();
  final result = predictSpeedCamera(
    model: model,
    latitude: latitude,
    longitude: longitude,
    timeOfDay: timeOfDay,
    dayOfWeek: dayOfWeek,
  );
  if (result == null) {
    stdout.writeln('[]');
    exit(1);
  } else {
    stdout.writeln(jsonEncode([result[0], result[1]]));
  }
}

class PredictiveModel {
  final List<Point<double>> cameras;
  PredictiveModel() : cameras = _load();

  static List<Point<double>> _load() {
    final scriptDir = p.dirname(Platform.script.toFilePath());
    final trainingPath = p.join(scriptDir, 'training.json');
    final data = jsonDecode(File(trainingPath).readAsStringSync())
        as Map<String, dynamic>;
    final cams = <Point<double>>[];
    for (final cam in data['cameras'] as List<dynamic>) {
      final coords = cam['coordinates'] as List<dynamic>;
      for (final coord in coords) {
        cams.add(Point<double>(
          (coord['latitude'] as num).toDouble(),
          (coord['longitude'] as num).toDouble(),
        ));
      }
    }
    return cams;
  }
}

List<double>? predictSpeedCamera({
  required PredictiveModel model,
  required double latitude,
  required double longitude,
  required String timeOfDay,
  required String dayOfWeek,
}) {
  if (model.cameras.isEmpty) return null;
  final current = Point<double>(latitude, longitude);
  Point<double>? best;
  var bestDist = double.infinity;
  for (final cam in model.cameras) {
    final dx = current.x - cam.x;
    final dy = current.y - cam.y;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < bestDist) {
      bestDist = dist;
      best = cam;
    }
  }
  if (best == null) return null;
  return [best.x, best.y];
}
