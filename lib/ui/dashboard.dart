import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dart:ui' as ui;
import 'dart:math' as math;

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
      // Smooth the acceleration bar by easing toward the new acceleration
      // value instead of jumping directly based on the full speed change.
      final targetAcceleration = (_speed - (_lastSpeed ?? _speed)) / 3.6;
      _acceleration = ui.lerpDouble(_acceleration, targetAcceleration, 0.2)!;
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
            Expanded(
              child: Row(
                children: [
                  Expanded(flex: 2, child: _buildSpeedWidget()),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: _buildAccelerationWidget()),
                        const SizedBox(height: 16),
                        Expanded(child: _buildSpeedHistoryWidget()),
                      ],
                    ),
                  ),
                ],
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Color(0xFFD32F2F), Color(0xFFFFA000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_speedCamIcon != null)
            Image.asset(_speedCamIcon!, width: 56, height: 56),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_cameraRoad != null)
                  Text(
                    _cameraRoad!,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600),
                  ),
                if (_speedCamWarning != null)
                  Text(
                    _speedCamWarning!,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                const SizedBox(height: 8),
                _buildDistanceProgress(),
                if (_activeCamera != null)
                  Text(
                    'Lat: ${_activeCamera!.latitude.toStringAsFixed(5)}, '
                    'Lon: ${_activeCamera!.longitude.toStringAsFixed(5)}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccelerationWidget() {
    final ratio = ((_acceleration + 5) / 10).clamp(0.0, 1.0);
    // Use a full hue spectrum so braking (blue) and acceleration (red)
    // produce more fine-grained color changes around the neutral (green)
    // point.
    final hue = 240 - (ratio * 240);
    final color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Acceleration',
              style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 8),
          Text('${_acceleration.toStringAsFixed(1)} m/s²',
              style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildSpeedWidget() {
    final speedRatio = (_speed / 200).clamp(0.0, 1.0);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: speedRatio),
            duration: const Duration(milliseconds: 500),
            builder: (context, value, child) => SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 12,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(
                    _overspeedDiff != null ? Colors.red : Colors.green),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${_speed.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 64,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
              const Text('km/h',
                  style: TextStyle(color: Colors.white70, fontSize: 20)),
              const SizedBox(height: 8),
              Text(_roadName,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 16)),
              if (_maxSpeed != null)
                Text('limit ${_maxSpeed!} km/h',
                    style: const TextStyle(color: Colors.white54)),
              if (_overspeedDiff != null)
                Text('Slow down by ${_overspeedDiff!} km/h',
                    style: const TextStyle(color: Colors.redAccent)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedHistoryWidget() {
    final maxSpeed =
        _speedHistory.isEmpty ? 0.0 : _speedHistory.reduce(math.max);
    final avgSpeed = _speedHistory.isEmpty
        ? 0.0
        : _speedHistory.reduce((a, b) => a + b) / _speedHistory.length;
    return GestureDetector(
      onDoubleTap: () {
        setState(() => _speedHistory.clear());
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Speed history',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            Expanded(
              child: CustomPaint(
                painter: _SpeedChartPainter(_speedHistory),
              ),
            ),
            const SizedBox(height: 8),
            Text('max: ${maxSpeed.toStringAsFixed(0)} km/h · '
                'avg: ${avgSpeed.toStringAsFixed(0)} km/h',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 4),
            const Text('Double tap to clear',
                style: TextStyle(color: Colors.white30, fontSize: 10)),
          ],
        ),
      ),
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
  final double lowThreshold;
  final double highThreshold;

  _SpeedChartPainter(this.history,
      {this.lowThreshold = 2.0, this.highThreshold = 5.0});

  @override
  void paint(Canvas canvas, Size size) {
    if (history.length < 2) return;

    for (var i = 1; i < history.length; i++) {
      final x1 = (i - 1) / (history.length - 1) * size.width;
      final y1 = size.height -
          (history[i - 1] / 120).clamp(0.0, 1.0) * size.height;
      final x2 = i / (history.length - 1) * size.width;
      final y2 = size.height -
          (history[i] / 120).clamp(0.0, 1.0) * size.height;

      final diff = (history[i] - history[i - 1]).abs();
      Color color;
      if (diff < lowThreshold) {
        color = Colors.green;
      } else if (diff < highThreshold) {
        color = Colors.yellow;
      } else {
        color = Colors.red;
      }

      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedChartPainter oldDelegate) =>
      oldDelegate.history != history ||
      oldDelegate.lowThreshold != lowThreshold ||
      oldDelegate.highThreshold != highThreshold;
}
