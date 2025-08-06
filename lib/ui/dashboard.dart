import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../rectangle_calculator.dart';

/// A simple dashboard showing the map, current speed and overspeed status.
///
/// The widget listens to [RectangleCalculatorThread] notifiers so that real
/// GPS and speed‑camera updates from the background logic are reflected on the
/// screen.
class DashboardPage extends StatefulWidget {
  final RectangleCalculatorThread? calculator;
  final ValueNotifier<String>? arStatus;
  const DashboardPage({super.key, this.calculator, this.arStatus});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // UI state mirrored from the calculator notifiers.
  double _speed = 0.0;
  String _roadName = 'Unknown road';
  int? _overspeedDiff;
  String? _speedCamWarning;
  double? _speedCamDistance;
  String? _cameraRoad;
  int? _maxSpeed;
  final List<double> _speedHistory = [];
  LatLng _position = const LatLng(0, 0);
  List<Marker> _cameraMarkers = [];
  StreamSubscription<SpeedCameraEvent>? _cameraSub;
  RectangleCalculatorThread? _calculator;
  String _arStatus = '';
  ValueNotifier<String>? _arNotifier;

  @override
  void initState() {
    super.initState();
    _calculator = widget.calculator;
    if (_calculator != null) {
      _speed = _calculator!.currentSpeedNotifier.value;
      _roadName = _calculator!.roadNameNotifier.value;
      _overspeedDiff = _calculator!.overspeedChecker.difference.value;
      _speedCamWarning = _calculator!.speedCamNotifier.value;
      _speedCamDistance = _calculator!.speedCamDistanceNotifier.value;
      _cameraRoad = _calculator!.cameraRoadNotifier.value;
      _maxSpeed = _calculator!.maxspeedNotifier.value;
      _position = _calculator!.positionNotifier.value;
      _calculator!.currentSpeedNotifier.addListener(_updateFromCalculator);
      _calculator!.roadNameNotifier.addListener(_updateFromCalculator);
      _calculator!.overspeedChecker.difference.addListener(_updateFromCalculator);
      _calculator!.speedCamNotifier.addListener(_updateFromCalculator);
      _calculator!.speedCamDistanceNotifier.addListener(_updateFromCalculator);
      _calculator!.cameraRoadNotifier.addListener(_updateFromCalculator);
      _calculator!.maxspeedNotifier.addListener(_updateFromCalculator);
      _calculator!.positionNotifier.addListener(_updateFromCalculator);
      _cameraSub = _calculator!.cameras.listen(_onCamera);
    }

    _arNotifier = widget.arStatus;
    if (_arNotifier != null) {
      _arStatus = _arNotifier!.value;
      _arNotifier!.addListener(_updateArStatus);
    }
  }

  void _updateFromCalculator() {
    setState(() {
      _speed = _calculator!.currentSpeedNotifier.value;
      _roadName = _calculator!.roadNameNotifier.value;
      _overspeedDiff = _calculator!.overspeedChecker.difference.value;
      _speedCamWarning = _calculator!.speedCamNotifier.value;
      _speedCamDistance = _calculator!.speedCamDistanceNotifier.value;
      _cameraRoad = _calculator!.cameraRoadNotifier.value;
      _maxSpeed = _calculator!.maxspeedNotifier.value;
      _position = _calculator!.positionNotifier.value;
      _speedHistory.add(_speed);
      if (_speedHistory.length > 30) _speedHistory.removeAt(0);
    });
  }

  void _onCamera(SpeedCameraEvent cam) {
    setState(() {
      _cameraMarkers = [
        ..._cameraMarkers,
        Marker(
          point: LatLng(cam.latitude, cam.longitude),
          width: 40,
          height: 40,
          builder: (context) =>
              const Icon(Icons.camera_alt, color: Colors.red),
        ),
      ];
    });
  }

  void _updateArStatus() {
    setState(() {
      _arStatus = _arNotifier!.value;
    });
  }

  @override
  void dispose() {
    if (_calculator != null) {
      _calculator!.currentSpeedNotifier.removeListener(_updateFromCalculator);
      _calculator!.roadNameNotifier.removeListener(_updateFromCalculator);
      _calculator!.overspeedChecker.difference
          .removeListener(_updateFromCalculator);
      _calculator!.speedCamNotifier.removeListener(_updateFromCalculator);
      _calculator!.speedCamDistanceNotifier
          .removeListener(_updateFromCalculator);
      _calculator!.cameraRoadNotifier.removeListener(_updateFromCalculator);
      _calculator!.maxspeedNotifier.removeListener(_updateFromCalculator);
      _calculator!.positionNotifier.removeListener(_updateFromCalculator);
      _cameraSub?.cancel();
    }
    _arNotifier?.removeListener(_updateArStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SpeedCamWarner'),
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                center: _position,
                zoom: 15,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.speedcamwarner',
                ),
                MarkerLayer(markers: _cameraMarkers),
              ],
            ),
          ),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 80,
                  child: CustomPaint(
                    painter: _SpeedChartPainter(_speedHistory),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_speed.toStringAsFixed(0)} km/h',
                      style: TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.bold,
                        color:
                            _overspeedDiff != null ? Colors.red : Colors.green,
                      ),
                    ),
                    if (_maxSpeed != null)
                      Text(
                        'max ${_maxSpeed!} km/h',
                        style: const TextStyle(
                            fontSize: 32, color: Colors.white70),
                      ),
                  ],
                ),
                Text(
                  _roadName,
                  style: const TextStyle(color: Colors.white70, fontSize: 20),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value:
                      (_speed / (_maxSpeed ?? 120)).clamp(0.0, 1.0),
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _overspeedDiff != null ? Colors.red : Colors.green,
                  ),
                ),
                if (_speedCamWarning != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _speedCamDistance != null
                        ? '${_speedCamWarning!} in ${_speedCamDistance!.toStringAsFixed(0)} m'
                        : _speedCamWarning!,
                    style: const TextStyle(color: Colors.orange, fontSize: 18),
                  ),
                  if (_cameraRoad != null)
                    Text(
                      _cameraRoad!,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildDistanceBar(100),
                      _buildDistanceBar(300),
                      _buildDistanceBar(500),
                      _buildDistanceBar(1000),
                    ],
                  ),
                ],
                if (_arStatus.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('AR: $_arStatus',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 16)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistanceBar(double threshold) {
    final active =
        _speedCamDistance != null && _speedCamDistance! <= threshold;
    return Expanded(
      child: Container(
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        color: active ? Colors.red : Colors.white24,
      ),
    );
  }
}

class _SpeedChartPainter extends CustomPainter {
  final List<double> history;
  _SpeedChartPainter(this.history);

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;
    final paint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < history.length; i++) {
      final x = i / (history.length - 1) * size.width;
      final y = size.height -
          (history[i] / 120).clamp(0.0, 1.0) * size.height; // assume 120 km/h max
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SpeedChartPainter oldDelegate) =>
      oldDelegate.history != history;
}
