import 'dart:async';

import 'package:flutter/material.dart';

import '../rectangle_calculator.dart';

/// Displays counters for different camera and POI categories.
///
/// Mirrors the "MainView" statistics page from the legacy ``main.py``
/// implementation where numbers of fixed, mobile, red light and predictive
/// cameras were shown alongside POIs.  The counters update as the
/// [RectangleCalculatorThread] emits [SpeedCameraEvent]s.
class StatsPage extends StatefulWidget {
  final RectangleCalculatorThread calculator;
  const StatsPage({super.key, required this.calculator});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late final StreamSubscription<SpeedCameraEvent> _sub;
  int _fixed = 0;
  int _traffic = 0;
  int _distance = 0;
  int _mobile = 0;
  int _predictive = 0;
  int _construction = 0;
    int _poi = 0;
  final Set<String> _seenCameras = {};

    void _onConstructionCount() {
      setState(() {
        _construction = widget.calculator.constructionAreaCountNotifier.value;
      });
    }

    void _onPoiCount() {
      setState(() {
        _poi = widget.calculator.poiCountNotifier.value;
      });
    }

  @override
  void initState() {
    super.initState();
      _construction = widget.calculator.constructionAreaCountNotifier.value;
      _poi = widget.calculator.poiCountNotifier.value;
      widget.calculator.constructionAreaCountNotifier
          .addListener(_onConstructionCount);
      widget.calculator.poiCountNotifier.addListener(_onPoiCount);
      _sub = widget.calculator.cameras.listen((cam) {
      final key = '${cam.latitude},${cam.longitude}';
      if (_seenCameras.add(key)) {
        setState(() {
          if (cam.fixed) _fixed++;
          if (cam.traffic) _traffic++;
          if (cam.distance) _distance++;
          if (cam.mobile) _mobile++;
          if (cam.predictive) _predictive++;
        });
      }
    });
  }

  @override
  void dispose() {
      _sub.cancel();
      widget.calculator.constructionAreaCountNotifier
          .removeListener(_onConstructionCount);
      widget.calculator.poiCountNotifier.removeListener(_onPoiCount);
      super.dispose();
    }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildRow('Fix Cameras', _fixed),
          _buildRow('Red Light Cameras', _traffic),
          _buildRow('Distance Cameras', _distance),
          _buildRow('Mobile Cameras', _mobile),
          _buildRow('Predictive Cameras', _predictive),
          _buildRow('Construction Areas', _construction),
          _buildRow('POIs', _poi),
        ],
      ),
    );
  }

  Widget _buildRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 24)),
          Text('$count',
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
