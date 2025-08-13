import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../rectangle_calculator.dart';

/// Dedicated map page that visualises the current position and allows the
/// user to add temporary police camera markers.
class MapPage extends StatefulWidget {
  final RectangleCalculatorThread calculator;
  const MapPage({super.key, required this.calculator});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late LatLng _center;
  final List<Marker> _markers = [];
  final MapController _mapController = MapController();
  StreamSubscription<SpeedCameraEvent>? _camSub;

  @override
  void initState() {
    super.initState();
    _center = widget.calculator.positionNotifier.value;
    widget.calculator.positionNotifier.addListener(_updatePosition);
    _camSub = widget.calculator.cameras.listen(_onCameraEvent);
  }

  void _updatePosition() {
    final newCenter = widget.calculator.positionNotifier.value;
    setState(() {
      _center = newCenter;
    });
    // Recenter the map whenever the GPS position updates
    _mapController.move(_center, 15);
  }

  void _onCameraEvent(SpeedCameraEvent cam) {
    setState(() {
      _markers.add(
        Marker(
          point: LatLng(cam.latitude, cam.longitude),
          width: 40,
          height: 40,
          child: const Icon(Icons.camera_alt, color: Colors.red),
        ),
      );
    });
  }

  void _addPoliceCamera() {
    final cam = SpeedCameraEvent(
      latitude: _center.latitude,
      longitude: _center.longitude,
      mobile: true,
      name: 'User camera',
    );
    widget.calculator.updateSpeedCams([cam]);
  }

  @override
  void dispose() {
    widget.calculator.positionNotifier.removeListener(_updatePosition);
    _camSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(initialCenter: _center, initialZoom: 15),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.speedcamwarner',
          ),
          MarkerLayer(markers: _markers),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPoliceCamera,
        tooltip: 'Add police camera',
        child: const Icon(Icons.local_police),
      ),
    );
  }
}
