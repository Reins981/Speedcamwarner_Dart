import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_popup/flutter_map_marker_popup.dart';
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
  Marker? _gpsMarker;
  final List<Marker> _cameraMarkers = [];
  final Map<Marker, SpeedCameraEvent> _markerData = {};
  final List<Marker> _constructionMarkers = [];
  final Map<Marker, GeoRect> _constructionData = {};
  final PopupController _popupController = PopupController();
  final MapController _mapController = MapController();
  StreamSubscription<SpeedCameraEvent>? _camSub;
  StreamSubscription<GeoRect>? _rectSub;
  StreamSubscription<GeoRect>? _constructionSub;
  final List<Polygon> _rectPolygons = [];

  @override
  void initState() {
    super.initState();
    _center = widget.calculator.positionNotifier.value;
    _gpsMarker = Marker(
      point: _center,
      width: 40,
      height: 40,
      child: Image.asset('images/car.png'),
    );
    widget.calculator.positionNotifier.addListener(_updatePosition);
    _camSub = widget.calculator.cameras.listen(_onCameraEvent);
    _rectSub = widget.calculator.rectangles.listen(_onRect);
    _constructionSub = widget.calculator.constructions.listen(
      _onConstructionArea,
    );
  }

  void _updatePosition() {
    final newCenter = widget.calculator.positionNotifier.value;
    setState(() {
      _center = newCenter;
      _gpsMarker = Marker(
        point: _center,
        width: 40,
        height: 40,
        child: Image.asset('images/car.png'),
      );
    });
    // Recenter the map whenever the GPS position updates
    _mapController.move(_center, 15);
  }

  void _onCameraEvent(SpeedCameraEvent cam) {
    final marker = Marker(
      point: LatLng(cam.latitude, cam.longitude),
      width: 40,
      height: 40,
      child: Image.asset(_iconForCamera(cam)),
    );
    setState(() {
      _cameraMarkers.add(marker);
      _markerData[marker] = cam;
    });
  }

  void _onConstructionArea(GeoRect area) {
    final marker = Marker(
      point: LatLng(area.minLat, area.minLon),
      width: 40,
      height: 40,
      child: Image.asset('images/construction_marker.png'),
    );
    setState(() {
      _constructionMarkers.add(marker);
      _constructionData[marker] = area;
    });
  }

  void _onRect(GeoRect rect) {
    final points = [
      LatLng(rect.minLat, rect.minLon),
      LatLng(rect.minLat, rect.maxLon),
      LatLng(rect.maxLat, rect.maxLon),
      LatLng(rect.maxLat, rect.minLon),
    ];
    final polygon = Polygon(
      points: points,
      color: Colors.blue.withOpacity(0.1),
      borderColor: Colors.blue,
      borderStrokeWidth: 2,
    );
    setState(() {
      _rectPolygons
        ..clear()
        ..add(polygon);
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
    _rectSub?.cancel();
    _constructionSub?.cancel();
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
          if (_rectPolygons.isNotEmpty) PolygonLayer(polygons: _rectPolygons),
          if (_gpsMarker != null) MarkerLayer(markers: [_gpsMarker!]),
          PopupMarkerLayer(
            options: PopupMarkerLayerOptions(
              popupController: _popupController,
              markers: [..._cameraMarkers, ..._constructionMarkers],
              popupDisplayOptions: PopupDisplayOptions(
                builder: (context, marker) {
                  final cam = _markerData[marker];
                  if (cam != null) {
                    final types = <String>[
                      if (cam.fixed) 'fixed',
                      if (cam.traffic) 'traffic',
                      if (cam.distance) 'distance',
                      if (cam.mobile) 'mobile',
                      if (cam.predictive) 'predictive',
                    ].join(', ');
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cam.name.isNotEmpty ? cam.name : 'Speed camera',
                            ),
                            if (types.isNotEmpty)
                              Text(types, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  }
                  if (_constructionData.containsKey(marker)) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('Construction area'),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPoliceCamera,
        tooltip: 'Add police camera',
        child: const Icon(Icons.local_police),
      ),
    );
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
