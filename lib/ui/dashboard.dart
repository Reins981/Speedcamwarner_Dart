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

  static const double _accelerationDisplayClamp = 5.0;
  static const double _accelerationHighlightThreshold = 2.5;
  static const double _accelerationBarMaxSpeedKmh = 300.0;
  static const double _accelerationBarHighSpeedMarkerKmh = 250.0;
  static const double _accelerationMinorTickIntervalKmh = 5.0;
  static const double _accelerationMajorTickIntervalKmh = 50.0;
  static const List<Color> _speedRingColors = <Color>[
    Color(0xFF053300),
    Color(0xFF0A5500),
    Color(0xFF0F8800),
    Color(0xFF14C400),
    Color(0xFF45FF00),
    Color(0xFF8CFF00),
    Color(0xFFFFF000),
    Color(0xFFFFD000),
    Color(0xFFFFA200),
    Color(0xFFFF7200),
    Color(0xFFFF3C00),
    Color(0xFFFF0000),
    Color(0xFFFF0050),
    Color(0xFFFF33A8),
  ];
  static const List<double> _speedRingStops = <double>[
    0.0,
    0.035,
    0.08,
    0.125,
    0.18,
    0.26,
    0.36,
    0.48,
    0.6,
    0.72,
    0.82,
    0.9,
    0.955,
    1.0,
  ];

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
      final double accelerationDelta =
          (targetAcceleration - _acceleration).abs();
      final double lerpStrength = accelerationDelta >= 2.0
          ? 0.85
          : accelerationDelta >= 1.0
              ? 0.65
              : 0.45;
      _acceleration =
          ui.lerpDouble(_acceleration, targetAcceleration, lerpStrength)!;
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
            backgroundColor: Colors.deepPurple.withOpacity(0.2),
            child: const Icon(Icons.location_searching),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            onPressed: _addCamera,
            tooltip: 'Add police camera',
            backgroundColor: Colors.deepPurple.withOpacity(0.2),
            child: const Icon(Icons.local_police),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            onPressed: _startRecording,
            tooltip: 'Start recording',
            backgroundColor: Colors.deepPurple.withOpacity(0.2),
            child: const Icon(Icons.fiber_manual_record),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            onPressed: _stopRecording,
            tooltip: 'Stop recording',
            backgroundColor: Colors.deepPurple.withOpacity(0.2),
            child: const Icon(Icons.stop),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            onPressed: _loadRoute,
            tooltip: 'Load route',
            backgroundColor: Colors.blue.withOpacity(0.4),
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
    final clampedAcceleration = _acceleration
        .clamp(-_accelerationDisplayClamp, _accelerationDisplayClamp)
        .toDouble();
    final bool isHighAcceleration =
        clampedAcceleration >= _accelerationHighlightThreshold;
    final bool isHeavyBraking =
        clampedAcceleration <= -_accelerationHighlightThreshold;
    final double cappedSpeed =
        _speed.clamp(0.0, _accelerationBarMaxSpeedKmh).toDouble();
    final double speedRatio = cappedSpeed / _accelerationBarMaxSpeedKmh;
    const gradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Color(0xFF003300),
        Color(0xFF005A00),
        Color(0xFF007500),
        Color(0xFF009A00),
        Color(0xFF00C853),
        Color(0xFF64DD17),
        Color(0xFFAEEA00),
        Color(0xFFFFF176),
        Color(0xFFFFEB3B),
        Color(0xFFFFC107),
        Color(0xFFFF9800),
        Color(0xFFFF5722),
        Color(0xFFD32F2F),
      ],
      stops: [
        0.0,
        0.06,
        0.12,
        0.18,
        0.26,
        0.34,
        0.44,
        0.54,
        0.64,
        0.74,
        0.84,
        0.92,
        1.0,
      ],
    );
    final Color glowColor = isHighAcceleration
        ? Colors.redAccent.withOpacity(0.6)
        : isHeavyBraking
            ? Colors.deepOrangeAccent.withOpacity(0.5)
            : Colors.white.withOpacity(0.25);
    final Color textColor = isHighAcceleration
        ? Colors.redAccent
        : isHeavyBraking
            ? Colors.deepOrangeAccent
            : Colors.white70;
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
          LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              final fillWidth = speedRatio * barWidth;
              final highSpeedMarkerRatio = (_accelerationBarHighSpeedMarkerKmh /
                      _accelerationBarMaxSpeedKmh)
                  .clamp(0.0, 1.0);
              final markerLeft = barWidth * highSpeedMarkerRatio;
              return SizedBox(
                height: 18,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: const _AccelerationTicksPainter(
                          maxValue: _accelerationBarMaxSpeedKmh,
                          minorTickInterval: _accelerationMinorTickIntervalKmh,
                          majorTickInterval: _accelerationMajorTickIntervalKmh,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutExpo,
                        height: 18,
                        width: fillWidth,
                        decoration: BoxDecoration(
                          gradient: gradient,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            if (fillWidth > 0)
                              BoxShadow(
                                color: glowColor,
                                blurRadius: isHighAcceleration ? 16 : 10,
                                spreadRadius: isHighAcceleration ? 1 : 0,
                              ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: math.max(0.0, markerLeft - 1),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 2,
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final value in const [0, 50, 100, 150, 200, 250, 300])
                Expanded(
                  child: Align(
                    alignment: value == 0
                        ? Alignment.centerLeft
                        : value == 300
                            ? Alignment.centerRight
                            : Alignment.center,
                    child: Text(
                      '$value',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double maxWidth = constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : 0.0;
                    final double fontSize = (maxWidth / 4.5).clamp(18.0, 40.0);
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${cappedSpeed.toStringAsFixed(0)} km/h',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                          fontSize: fontSize,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double maxWidth = constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : 0.0;
                    final double fontSize = (maxWidth / 5.5).clamp(18.0, 36.0);
                    return AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        color: textColor,
                        fontWeight: isHighAcceleration
                            ? FontWeight.bold
                            : FontWeight.w500,
                        fontSize: fontSize,
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${clampedAcceleration.toStringAsFixed(2)} m/s²',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedWidget() {
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
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  final normalizedSpeed =
                      value.clamp(0.0, _accelerationBarMaxSpeedKmh);
                  final progress =
                      (normalizedSpeed / _accelerationBarMaxSpeedKmh)
                          .clamp(0.0, 1.0);
                  return SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    child: CustomPaint(
                      painter: _SpeedRingPainter(
                        progress: progress,
                        colors: _speedRingColors,
                        stops: _speedRingStops,
                      ),
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

class _SpeedRingPainter extends CustomPainter {
  _SpeedRingPainter({
    required this.progress,
    required this.colors,
    required this.stops,
  }) : assert(colors.length == stops.length,
            'colors and stops must have the same length');

  final double progress;
  final List<Color> colors;
  final List<double> stops;

  static const double _strokeWidth = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final double clampedProgress = progress.clamp(0.0, 1.0);
    final Offset center = size.center(Offset.zero);
    final double radius =
        math.min(size.width, size.height) / 2 - _strokeWidth / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    const double startAngle = -math.pi / 2;
    final double sweepAngle = clampedProgress * 2 * math.pi;

    final Paint trackPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    canvas.drawArc(rect, startAngle, 2 * math.pi, false, trackPaint);

    if (clampedProgress <= 0) {
      return;
    }

    final SweepGradient gradient = SweepGradient(
      startAngle: startAngle,
      endAngle: startAngle + 2 * math.pi,
      colors: colors,
      stops: stops,
      tileMode: TileMode.clamp,
    );
    final Paint ringPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round;

    final Color tipColor = _colorAtProgress(clampedProgress);
    final double glowOpacity =
        ui.lerpDouble(0.25, 0.55, clampedProgress) ?? 0.4;
    final Paint glowPaint = Paint()
      ..color = tipColor.withOpacity(glowOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 6);

    canvas.drawArc(rect, startAngle, sweepAngle, false, glowPaint);
    canvas.drawArc(rect, startAngle, sweepAngle, false, ringPaint);

    final double indicatorAngle = startAngle + sweepAngle;
    final Offset indicatorPosition = Offset(
      center.dx + radius * math.cos(indicatorAngle),
      center.dy + radius * math.sin(indicatorAngle),
    );

    final Paint indicatorPaint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          tipColor.withOpacity(0.95),
          tipColor.withOpacity(0.2),
        ],
      ).createShader(Rect.fromCircle(center: indicatorPosition, radius: 12));

    canvas.drawCircle(indicatorPosition, 6, indicatorPaint);
  }

  Color _colorAtProgress(double value) {
    if (colors.isEmpty) {
      return Colors.white;
    }
    if (colors.length == 1 || stops.length != colors.length) {
      return colors.last;
    }
    for (int i = 0; i < stops.length - 1; i++) {
      final double lower = stops[i];
      final double upper = stops[i + 1];
      if (value <= lower) {
        return colors[i];
      }
      if (value < upper) {
        final double t = ((value - lower) / (upper - lower)).clamp(0.0, 1.0);
        return Color.lerp(colors[i], colors[i + 1], t) ?? colors[i + 1];
      }
    }
    return colors.last;
  }

  @override
  bool shouldRepaint(covariant _SpeedRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        !listEquals(oldDelegate.colors, colors) ||
        !listEquals(oldDelegate.stops, stops);
  }
}

class _AccelerationTicksPainter extends CustomPainter {
  const _AccelerationTicksPainter({
    required this.maxValue,
    required this.minorTickInterval,
    required this.majorTickInterval,
  });

  final double maxValue;
  final double minorTickInterval;
  final double majorTickInterval;

  @override
  void paint(Canvas canvas, Size size) {
    if (maxValue <= 0 || minorTickInterval <= 0) {
      return;
    }
    final int minorTickCount = (maxValue / minorTickInterval).round();
    if (minorTickCount <= 0) {
      return;
    }
    final int majorTickEvery =
        math.max(1, (majorTickInterval / minorTickInterval).round());
    final double height = size.height;
    for (int i = 0; i <= minorTickCount; i++) {
      final double dx = size.width * (i / minorTickCount);
      final bool isMajorTick = i % majorTickEvery == 0;
      final Paint paint = Paint()
        ..color = isMajorTick ? Colors.white38 : Colors.white24
        ..strokeWidth = isMajorTick ? 2 : 1;
      final double top = isMajorTick ? 0 : height * 0.55;
      final double bottom = isMajorTick ? height : height * 0.45;
      canvas.drawLine(Offset(dx, top), Offset(dx, bottom), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AccelerationTicksPainter oldDelegate) {
    return oldDelegate.maxValue != maxValue ||
        oldDelegate.minorTickInterval != minorTickInterval ||
        oldDelegate.majorTickInterval != majorTickInterval;
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
