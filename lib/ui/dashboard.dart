import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dart:ui' as ui;
import 'dart:math' as math;

import '../app_controller.dart';
import '../rectangle_calculator.dart';
import '../config.dart';
import 'overspeed_indicator.dart';

/// A simple dashboard showing current speed, road name and speed camera
/// information.
///
/// The widget listens to [RectangleCalculatorThread] notifiers so that real
/// GPS and speed‑camera updates from the background logic are reflected on the
/// screen.
class DashboardPage extends StatefulWidget {
  final AppController? controller;
  final RectangleCalculatorThread? calculator;
  final ValueNotifier<String>? arStatus;
  final ValueNotifier<String>? direction;
  final ValueNotifier<String>? averageBearing;
  const DashboardPage({
    super.key,
    this.controller,
    this.calculator,
    this.arStatus,
    this.direction,
    this.averageBearing,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // UI state mirrored from the calculator notifiers.
  double _speed = 0.0;
  double _previousSpeed = 0.0;
  int? _overspeedDiff;
  String? _speedCamWarning;
  String? _speedCamIcon;
  double? _speedCamDistance;
  String? _cameraRoad;
  String? _nextCamRoad;
  int? _nextCamDistance;
  bool _processNextCam = false;
  int? _maxSpeed;
  bool _gpsOn = false;
  bool _online = false;
  final List<double> _speedHistory = [];
  SpeedCameraEvent? _activeCamera;
  StreamSubscription<SpeedCameraEvent>? _cameraSub;
  RectangleCalculatorThread? _calculator;
  AppController? _controller;
  String _arStatus = '';
  ValueNotifier<String>? _arNotifier;
  double _acceleration = 0.0;
  String _direction = '-';
  String _averageBearing = '---.-°';
  ValueNotifier<String>? _directionNotifier;
  ValueNotifier<String>? _averageBearingNotifier;

  static final ValueNotifier<String> _emptyRoadName = ValueNotifier<String>('');

  @override
  void initState() {
    super.initState();
    _calculator = widget.calculator;
    _controller = widget.controller;
    if (_calculator != null) {
      _speed = _calculator!.currentSpeedNotifier.value;
      _previousSpeed = _speed;
      _speedCamWarning = _calculator!.speedCamNotifier.value;
      if (_speedCamWarning == 'FREEFLOW') {
        _clearCameraInfo();
      } else {
        _speedCamIcon = _iconForWarning(_speedCamWarning);
        _speedCamDistance = _calculator!.speedCamDistanceNotifier.value;
        _cameraRoad = _calculator!.cameraRoadNotifier.value;
      }
      _nextCamRoad = _calculator!.nextCamRoadNotifier.value;
      _nextCamDistance = _calculator!.nextCamDistanceNotifier.value;
      _processNextCam = _calculator!.processNextCamNotifier.value;
      _maxSpeed = _calculator!.maxspeedNotifier.value;
      _overspeedDiff = (_maxSpeed != null && _speed > _maxSpeed!)
          ? (_speed - _maxSpeed!).round()
          : null;
      _gpsOn = _calculator!.gpsStatusNotifier.value;
      _online = _calculator!.onlineStatusNotifier.value;
      _calculator!.currentSpeedNotifier.addListener(_updateFromCalculator);
      _calculator!.speedCamNotifier.addListener(_updateFromCalculator);
      _calculator!.speedCamDistanceNotifier.addListener(_updateFromCalculator);
      _calculator!.cameraRoadNotifier.addListener(_updateFromCalculator);
      _calculator!.nextCamRoadNotifier.addListener(_updateFromCalculator);
      _calculator!.nextCamDistanceNotifier.addListener(_updateFromCalculator);
      _calculator!.processNextCamNotifier.addListener(_updateFromCalculator);
      _calculator!.maxspeedNotifier.addListener(_updateFromCalculator);
      _calculator!.gpsStatusNotifier.addListener(_updateFromCalculator);
      _calculator!.onlineStatusNotifier.addListener(_updateFromCalculator);
      _cameraSub = _calculator!.cameras.listen(_onCamera);
    }

    _arNotifier = widget.arStatus;
    if (_arNotifier != null) {
      _arStatus = _arNotifier!.value;
      _arNotifier!.addListener(_updateArStatus);
    }

    _directionNotifier = widget.direction;
    if (_directionNotifier != null) {
      _direction = _directionNotifier!.value;
      _directionNotifier!.addListener(_updateDirectionBearing);
    }
    _averageBearingNotifier = widget.averageBearing;
    if (_averageBearingNotifier != null) {
      _averageBearing = _averageBearingNotifier!.value;
      _averageBearingNotifier!.addListener(_updateDirectionBearing);
    }
  }

  void _updateFromCalculator() {
    setState(() {
      _previousSpeed = _speed;
      _speed = _calculator!.currentSpeedNotifier.value;
      _maxSpeed = _calculator!.maxspeedNotifier.value;
      _overspeedDiff = (_maxSpeed != null && _speed > _maxSpeed!)
          ? (_speed - _maxSpeed!).round()
          : null;
      _speedCamWarning = _calculator!.speedCamNotifier.value;
      if (_speedCamWarning == 'FREEFLOW') {
        _clearCameraInfo();
      } else {
        _speedCamDistance = _calculator!.speedCamDistanceNotifier.value;
        _cameraRoad = _calculator!.cameraRoadNotifier.value;
        _speedCamIcon = _iconForWarning(_speedCamWarning);
      }
      _nextCamRoad = _calculator!.nextCamRoadNotifier.value;
      _nextCamDistance = _calculator!.nextCamDistanceNotifier.value;
      _processNextCam = _calculator!.processNextCamNotifier.value;
      _gpsOn = _calculator!.gpsStatusNotifier.value;
      _online = _calculator!.onlineStatusNotifier.value;
      _speedHistory.add(_speed);
      if (_speedHistory.length > 30) _speedHistory.removeAt(0);
      // Smooth the acceleration bar by easing toward the new acceleration
      // value instead of jumping directly based on the full speed change.
      final targetAcceleration = (_speed - _previousSpeed) / 3.6;
      _acceleration = ui.lerpDouble(_acceleration, targetAcceleration, 0.2)!;
    });
  }

  List<Color> _cameraGradientColors() {
    final d = _speedCamDistance ?? double.infinity;
    List<Color> colors;
    if (d > 1000 && d <= 1500) {
      colors = [Colors.orangeAccent, Colors.orange];
    } else if (d > 500 && d <= 1000) {
      colors = [Colors.orange, Colors.deepOrange];
    } else if (d > 300 && d <= 500) {
      colors = [Colors.deepOrange, Colors.redAccent];
    } else {
      colors = [Colors.red, Colors.red.shade900];
    }
    return colors.map((c) => c.withOpacity(0.4)).toList();
  }

  void _clearCameraInfo() {
    _speedCamWarning = null;
    _speedCamIcon = null;
    _speedCamDistance = null;
    _cameraRoad = null;
    _activeCamera = null;
  }

  double _degToRad(double deg) => deg * (math.pi / 180.0);

  double _distanceBetween(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0; // metres
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  bool _withinDisplayDistance(SpeedCameraEvent cam) {
    if (_calculator == null) return false;
    final pos = _calculator!.positionNotifier.value;
    final distance = _distanceBetween(
      pos.latitude,
      pos.longitude,
      cam.latitude,
      cam.longitude,
    );
    final maxDistance =
        (AppConfig.get<num>('speedCamWarner.max_display_distance_camera') ??
                5000)
            .toDouble();
    return distance <= maxDistance;
  }

  void _onCamera(SpeedCameraEvent cam) {
    if (!_withinDisplayDistance(cam)) return;
    setState(() {
      _activeCamera = cam;
      _speedCamWarning = _cameraTypeString(cam);
      _speedCamIcon = _iconForWarning(_speedCamWarning);
    });
  }

  void _updateArStatus() {
    setState(() {
      _arStatus = _arNotifier!.value;
    });
  }

  Future<void> _addCamera() async {
    if (_calculator == null) return;
    final pos = _calculator!.positionNotifier.value;
    final road = _calculator!.roadNameNotifier.value;
    var (success, status) = await _calculator!.uploadCameraToDriveMethod(
      road,
      pos.latitude,
      pos.longitude,
    );
    if (!mounted) return;
    final msg = success
        ? 'Camera added'
        : 'Camera not added: ${status ?? 'unknown error'}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _startRecording() {
    _controller?.startRecording();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Recording started')));
  }

  Future<void> _stopRecording() async {
    await _controller?.stopRecording();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Recording stopped')));
  }

  Future<void> _loadRoute() async {
    await _controller?.loadRoute();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Route loaded')));
  }

  void _updateDirectionBearing() {
    setState(() {
      _direction = _directionNotifier?.value ?? _direction;
      _averageBearing = _averageBearingNotifier?.value ?? _averageBearing;
    });
  }

  Future<void> _selectPoiLookup() async {
    String selected = 'hospital';
    final type = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('POI lookup'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    title: const Text('Hospitals'),
                    value: 'hospital',
                    groupValue: selected,
                    onChanged: (v) => setState(() => selected = v!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Gas stations'),
                    value: 'fuel',
                    groupValue: selected,
                    onChanged: (v) => setState(() => selected = v!),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
    if (type != null) {
      await _controller?.lookupPois(type);
    }
  }

  @override
  void dispose() {
    if (_calculator != null) {
      _calculator!.currentSpeedNotifier.removeListener(_updateFromCalculator);
      _calculator!.speedCamNotifier.removeListener(_updateFromCalculator);
      _calculator!.speedCamDistanceNotifier.removeListener(
        _updateFromCalculator,
      );
      _calculator!.cameraRoadNotifier.removeListener(_updateFromCalculator);
      _calculator!.nextCamRoadNotifier.removeListener(_updateFromCalculator);
      _calculator!.nextCamDistanceNotifier
          .removeListener(_updateFromCalculator);
      _calculator!.processNextCamNotifier.removeListener(_updateFromCalculator);
      _calculator!.maxspeedNotifier.removeListener(_updateFromCalculator);
      _calculator!.gpsStatusNotifier.removeListener(_updateFromCalculator);
      _calculator!.onlineStatusNotifier.removeListener(_updateFromCalculator);
      _cameraSub?.cancel();
    }
    _arNotifier?.removeListener(_updateArStatus);
    _directionNotifier?.removeListener(_updateDirectionBearing);
    _averageBearingNotifier?.removeListener(_updateDirectionBearing);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasCameraInfo = _speedCamWarning != null || _activeCamera != null;
    return Scaffold(
      appBar: AppBar(title: const Text('SpeedCamWarner')),
      body: Stack(
        children: [
          Container(
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
                Expanded(flex: 2, child: _buildSpeedWidget()),
                const SizedBox(height: 16),
                Center(child: _buildRoadNameWidget()),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _buildAccelerationWidget()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildSpeedHistoryWidget()),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildStatusRow(),
                const SizedBox(height: 16),
                _buildDirectionBearingRow(),
              ],
            ),
          ),
          if (hasCameraInfo || _processNextCam)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasCameraInfo) _buildCameraInfo(),
                    if (hasCameraInfo && _processNextCam)
                      const SizedBox(height: 8),
                    if (_processNextCam) _buildNextCameraInfo(),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: _selectPoiLookup,
            tooltip: 'Find POIs',
            backgroundColor: Colors.deepPurple.withOpacity(0.4),
            child: const Icon(Icons.location_searching),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            onPressed: _addCamera,
            tooltip: 'Add police camera',
            backgroundColor: Colors.deepPurple.withOpacity(0.4),
            child: const Icon(Icons.local_police),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            onPressed: _startRecording,
            tooltip: 'Start recording',
            backgroundColor: Colors.deepPurple.withOpacity(0.4),
            child: const Icon(Icons.fiber_manual_record),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            onPressed: _stopRecording,
            tooltip: 'Stop recording',
            backgroundColor: Colors.deepPurple.withOpacity(0.4),
            child: const Icon(Icons.stop),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            onPressed: _loadRoute,
            tooltip: 'Load route',
            backgroundColor: Colors.blue.withOpacity(0.6),
            child: const Icon(Icons.play_arrow),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraInfo() {
    if (_speedCamWarning == null && _activeCamera == null) {
      return const SizedBox.shrink();
    }
    final colors = _cameraGradientColors();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (_speedCamWarning != null)
                  Text(
                    _speedCamWarning!,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                const SizedBox(height: 8),
                _buildDistanceProgress(),
                if (_activeCamera != null)
                  Text(
                    'Lat: ${_activeCamera!.latitude.toStringAsFixed(5)}, '
                    'Lon: ${_activeCamera!.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextCameraInfo() {
    if (!_processNextCam || _nextCamRoad == null || _nextCamDistance == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.camera_alt, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Next: $_nextCamRoad (${_nextCamDistance!} m)',
              style: const TextStyle(color: Colors.white, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    final children = <Widget>[
      Expanded(child: _buildGpsWidget()),
      const SizedBox(width: 16),
      Expanded(child: _buildInternetWidget()),
    ];
    if (_arStatus.isNotEmpty) {
      children.add(const SizedBox(width: 16));
      children.add(Expanded(child: _buildAiWidget()));
    }
    return Row(children: children);
  }

  Widget _buildAiWidget() {
    final Color color = _arStatus == 'HUMAN' ? Colors.red : Colors.blueGrey;
    return _statusTile(
      icon: Icons.smart_toy,
      text: 'AI: $_arStatus',
      color: color,
    );
  }

  Widget _buildDirectionBearingRow() {
    return Row(
      children: [
        Expanded(
          child: _statusTile(
            icon: Icons.explore,
            text: _direction,
            color: Colors.blueGrey,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _statusTile(
            icon: Icons.navigation,
            text: _averageBearing,
            color: Colors.blueGrey,
          ),
        ),
      ],
    );
  }

  Widget _buildGpsWidget() {
    return _statusTile(
      icon: _gpsOn ? Icons.gps_fixed : Icons.gps_off,
      text: _gpsOn ? 'GPS On' : 'GPS Off',
      color: _gpsOn ? Colors.green : Colors.red,
    );
  }

  Widget _buildInternetWidget() {
    return _statusTile(
      icon: _online ? Icons.wifi : Icons.wifi_off,
      text: _online ? 'Online' : 'Offline',
      color: _online ? Colors.green : Colors.red,
    );
  }

  Widget _statusTile({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
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
          const Text(
            'Acceleration',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
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
          Text(
            '${_acceleration.toStringAsFixed(1)} m/s²',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedWidget() {
    final max = _maxSpeed ?? 200;
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: _previousSpeed, end: _speed),
                duration: const Duration(milliseconds: 500),
                builder: (context, value, child) {
                  final progress = (value / max).clamp(0.0, 1.0);
                  final colorRatio = (value / 200).clamp(0.0, 1.0);
                  final hue = (1 - colorRatio) * 120;
                  final ringColor = HSVColor.fromAHSV(
                    1.0,
                    hue,
                    1.0,
                    1.0,
                  ).toColor();
                  return SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 12,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                    ),
                  );
                },
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_speed.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 72,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'km/h',
                      style: TextStyle(color: Colors.white70, fontSize: 24),
                    ),
                    if (_maxSpeed != null) ...[
                      const SizedBox(height: 8),
                      _buildMaxSpeedWidget(),
                    ],
                  ],
                ),
              ),
              if (_overspeedDiff != null && _overspeedDiff! > 0)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: OverspeedIndicator(diff: _overspeedDiff!),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoadNameWidget() {
    final notifier = _calculator?.roadNameNotifier ?? _emptyRoadName;
    return ValueListenableBuilder<String>(
      valueListenable: notifier,
      builder: (context, value, child) {
        final name = value.isEmpty ? 'Unknown road' : value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }

  Widget _buildMaxSpeedWidget() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.red, width: 5),
      ),
      alignment: Alignment.center,
      child: Text(
        '${_maxSpeed!}',
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
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
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Speed history',
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _SpeedChartPainter(_speedHistory),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'max: ${maxSpeed.toStringAsFixed(0)} km/h · '
              'avg: ${avgSpeed.toStringAsFixed(0)} km/h',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Double tap to clear',
              style: TextStyle(color: Colors.white30, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistanceProgress() {
    if (_speedCamDistance == null) return const SizedBox.shrink();
    final capped = _speedCamDistance!.clamp(0, 1000);
    final colors = _cameraGradientColors();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: LinearProgressIndicator(
            value: (1000 - capped) / 1000,
            backgroundColor: Colors.white24,
            valueColor: AlwaysStoppedAnimation<Color>(colors.last),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${_speedCamDistance!.toStringAsFixed(0)} m',
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  String _cameraTypeString(SpeedCameraEvent cam) {
    if (cam.fixed) return 'fix';
    if (cam.traffic) return 'traffic';
    if (cam.distance) return 'distance';
    if (cam.mobile) return 'mobile';
    if (cam.predictive) return 'mobile';
    return '';
  }

  String? _iconForWarning(String? warning) {
    switch (warning) {
      case 'fix':
        return 'images/fixcamera_map.png';
      case 'traffic':
        return 'images/trafficlightcamera_map.png';
      case 'mobile':
        return 'images/mobilecamera_map.png';
      case 'distance':
        return 'images/distancecamera_map.png';
      case 'CAMERA_AHEAD':
        return 'images/camera_ahead.png';
      default:
        return null;
    }
  }

  String _iconForCamera(SpeedCameraEvent cam) {
    if (cam.fixed) return 'images/fixcamera_map.png';
    if (cam.traffic) return 'images/trafficlightcamera_map.png';
    if (cam.distance) return 'images/distancecamera_map.png';
    if (cam.mobile) return 'images/mobilecamera_map.png';
    if (cam.predictive) return 'images/mobilecamera_map.png';
    return 'images/distancecamera_map.png';
  }
}

class _SpeedChartPainter extends CustomPainter {
  final List<double> history;
  final double lowThreshold;
  final double highThreshold;

  _SpeedChartPainter(
    this.history, {
    this.lowThreshold = 2.0,
    this.highThreshold = 5.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.length < 2) return;

    for (var i = 1; i < history.length; i++) {
      final x1 = (i - 1) / (history.length - 1) * size.width;
      final y1 =
          size.height - (history[i - 1] / 120).clamp(0.0, 1.0) * size.height;
      final x2 = i / (history.length - 1) * size.width;
      final y2 = size.height - (history[i] / 120).clamp(0.0, 1.0) * size.height;

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
      !listEquals(oldDelegate.history, history) ||
      oldDelegate.lowThreshold != lowThreshold ||
      oldDelegate.highThreshold != highThreshold;
}
