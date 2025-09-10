import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

class SpeedCamPredictor {
  late OrtSession _session;
  late List<String> _featureNames;

  Future<void> init() async {
    // Load ONNX
    final modelBytes = await rootBundle.load('assets/model.onnx');
    final options = OrtSessionOptions();
    options.setIntraOpNumThreads(1);
    _session = OrtSession.fromBuffer(modelBytes.buffer.asUint8List(),
        options); // Add 'CUDAExecutionProvider' if you have GPU support

    // Load feature names (exact order expected by the model)
    final featJson = await rootBundle.loadString('assets/feature_names.json');
    _featureNames = List<String>.from(jsonDecode(featJson));
  }

  /// timeOfDay can be "morning"/"evening" or "HH:mm" (we’ll map >18 to evening)
  Future<List<double>> predict({
    required double latitude,
    required double longitude,
    required String timeOfDay,
    required String dayOfWeek, // e.g. "Mon","Tue","Wed",...
  }) async {
    // Normalize timeOfDay like your Python code
    final t = timeOfDay.contains(':')
        ? (int.tryParse(timeOfDay.split(':').first) ?? 0) > 18
            ? 'evening'
            : 'morning'
        : timeOfDay;

    // Build feature vector with the **same dummy columns** as training
    // Start with all zeros, then set the active ones
    final Map<String, double> row = {
      for (final f in _featureNames) f: 0.0,
    };

    // Numeric features
    if (row.containsKey('latitude')) row['latitude'] = latitude;
    if (row.containsKey('longitude')) row['longitude'] = longitude;

    // One-hot categorical features (same names pandas.get_dummies created)
    // Examples: time_of_day_evening, time_of_day_morning, day_of_week_Mon, ...
    final todKey = 'time_of_day_$t';
    if (row.containsKey(todKey)) row[todKey] = 1.0;

    final dowKey = 'day_of_week_$dayOfWeek';
    if (row.containsKey(dowKey)) row[dowKey] = 1.0;

    final inputVectorDouble =
        _featureNames.map((f) => (row[f] ?? 0).toDouble()).toList();

    // Shape: [1, N]
    final input = OrtValueTensor.createTensorWithDataList(
        Float32List.fromList(inputVectorDouble), [1, _featureNames.length]);

    final outputs = _session.run(OrtRunOptions(),
        {'input': input}); // 'input' matches the initial_types name

    // Assume model outputs a single 1x2 (lat, lon) or similar
    final out = outputs.first as OrtValueTensor;
    final value = out.value;

    if (value is List && value.isNotEmpty && value.first is List) {
      // [[lat, lon]] → take first row
      final inner = value.first as List;
      final result = inner.map((e) => (e as num).toDouble()).toList();
      // result is [lat, lon]
      return result;
    }
    return [];
  }
}
