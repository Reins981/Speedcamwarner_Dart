import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dart:ui' as ui;

import '../rectangle_calculator.dart';

/// A simple dashboard showing current speed, road name and speed camera
/// information.
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
  String? _speedCamIcon;
  double? _speedCamDistance;
  String? _cameraRoad;
  int? _maxSpeed;
  final List<double> _speedHistory = [];
  SpeedCameraEvent? _activeCamera;
  StreamSubscription<SpeedCameraEvent>? _cameraSub;
  RectangleCalculatorThread? _calculator;
  String _arStatus = '';
  ValueNotifier<String>? _arNotifier;
  double _acceleration = 0.0;
  double? _lastSpeed;

  @override
  void initState() {
    super.initState();
    _calculator = widget.calculator;
    if (_calculator != null) {
      _speed = _calculator!.currentSpeedNotifier.value;
      _roadName = _calculator!.roadNameNotifier.value;
      _overspeedDiff = _calculator!.overspeedChecker.difference.value;
      _speedCamWarning = _calculator!.speedCamNotifier.value;
      _speedCamIcon = _iconForWarning(_speedCamWarning);
      _speedCamDistance = _calculator!.speedCamDistanceNotifier.value;
      _cameraRoad = _calculator!.cameraRoadNotifier.value;
      _maxSpeed = _calculator!.maxspeedNotifier.value;
      _calculator!.currentSpeedNotifier.addListener(_updateFromCalculator);
      _calculator!.roadNameNotifier.addListener(_updateFromCalculator);
      _calculator!.overspeedChecker.difference.addListener(_updateFromCalculator);
      _calculator!.speedCamNotifier.addListener(_updateFromCalculator);
      _calculator!.speedCamDistanceNotifier.addListener(_updateFromCalculator);
      _calculator!.cameraRoadNotifier.addListener(_updateFromCalculator);
      _calculator!.maxspeedNotifier.addListener(_updateFromCalculator);
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
      _speedCamIcon = _iconForWarning(_speedCamWarning);
      _speedCamDistance = _calculator!.speedCamDistanceNotifier.value;
      _cameraRoad = _calculator!.cameraRoadNotifier.value;
      _maxSpeed = _calculator!.maxspeedNotifier.value;
      _speedHistory.add(_speed);
      if (_speedHistory.length > 30) _speedHistory.removeAt(0);
      _acceleration = ((_speed - (_lastSpeed ?? _speed)) / 3.6);
      _lastSpeed = _speed;
    });
  }

  void _onCamera(SpeedCameraEvent cam) {
    setState(() {
      _activeCamera = cam;
      _speedCamIcon = _iconForCamera(cam);
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E1E1E), Color(0xFF121212)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCameraInfo(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_speed.toStringAsFixed(0)} km/h',
                  style: TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
                    color: _overspeedDiff != null ? Colors.red : Colors.green,
                  ),
                ),
                if (_maxSpeed != null)
                  Text(
                    'max ${_maxSpeed!} km/h',
                    style:
                        const TextStyle(fontSize: 32, color: Colors.white70),
                  ),
              ],
            ),
            Text(
              _roadName,
              style: const TextStyle(color: Colors.white70, fontSize: 20),
            ),
            if (_overspeedDiff != null)
              Text(
                'Slow down by ${_overspeedDiff!} km/h',
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 24),
              ),
            const SizedBox(height: 12),
            _buildAccelerationBar(),
            const SizedBox(height: 16),
            SizedBox(
              height: 80,
              child: CustomPaint(
                painter: _SpeedChartPainter(_speedHistory),
              ),
            ),
            if (_arStatus.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('AR: $_arStatus',
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 16)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCameraInfo() {
    if (_speedCamWarning == null && _activeCamera == null) {
      return const SizedBox.shrink();
    }
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_speedCamIcon != null)
                  Image.asset(_speedCamIcon!, width: 48, height: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_cameraRoad != null)
                        Text(
                          _cameraRoad!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18),
                        ),
                      if (_activeCamera != null)
                        Text(
                          'Lat: ' +
                              _activeCamera!.latitude.toStringAsFixed(5) +
                              ', Lon: ' +
                              _activeCamera!.longitude.toStringAsFixed(5),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 14),
                        ),
                    ],
                  ),
                ),
                if (_speedCamDistance != null && _speedCamDistance! > 1000)
                  const Icon(Icons.warning, color: Colors.orange),
              ],
            ),
            const SizedBox(height: 8),
            _buildDistanceProgress(),
          ],
        ),
      ),
    );
  }

  Widget _buildAccelerationBar() {
    final ratio = ((_acceleration + 5) / 10).clamp(0.0, 1.0);
    // Use a full hue spectrum so braking (blue) and acceleration (red)
    // produce more fine-grained color changes around the neutral (green)
    // point.
    final hue = 240 - (ratio * 240);
    final color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Acceleration',
            style: TextStyle(color: Colors.white70, fontSize: 16)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor: Colors.white24,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildDistanceProgress() {
    if (_speedCamDistance == null) return const SizedBox.shrink();
    final capped = _speedCamDistance!.clamp(0, 1000);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: (1000 - capped) / 1000,
          backgroundColor: Colors.white24,
          valueColor:
              const AlwaysStoppedAnimation<Color>(Colors.orange),
        ),
        const SizedBox(height: 4),
        Text(
          '${_speedCamDistance!.toStringAsFixed(0)} m',
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  String? _iconForWarning(String? warning) {
    switch (warning) {
      case 'fix':
        return 'images/fixcamera.png';
      case 'traffic':
        return 'images/trafficlightcamera.png';
      case 'mobile':
        return 'images/mobilcamera.png';
      case 'distance':
        return 'images/distancecamera.png';
      case 'CAMERA_AHEAD':
        return 'images/camera_ahead.png';
      case 'FREEFLOW':
        return 'images/freeflow.png';
      default:
        return null;
    }
  }

  String _iconForCamera(SpeedCameraEvent cam) {
    if (cam.fixed) return 'images/fixcamera_map.png';
    if (cam.traffic) return 'images/trafficlightcamera_map.jpg';
    if (cam.distance) return 'images/distancecamera_map.jpg';
    if (cam.mobile) return 'images/mobilecamera_map.jpg';
    if (cam.predictive) return 'images/camera_ahead.png';
    return 'images/distancecamera_map.jpg';
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
    final path = ui.Path();
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
