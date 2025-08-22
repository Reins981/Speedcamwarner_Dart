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
  StreamSubscription<GeoRect?>? _rectSub;
  StreamSubscription<GeoRect?>? _constructionSub;
  List<Polygon> _rectPolygons = [];
  List<Polygon> _constructionPolygons = [];
  GeoRect? _lastRect;

  bool _sameRect(GeoRect a, GeoRect b, [double tol = 1e-6]) {
    return (a.minLat - b.minLat).abs() < tol &&
        (a.minLon - b.minLon).abs() < tol &&
        (a.maxLat - b.maxLat).abs() < tol &&
        (a.maxLon - b.maxLon).abs() < tol;
  }

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
    // Populate map with already known cameras and construction areas so that
    // opening the map after lookups have finished still shows them.  The
    // streams only emit new items, so we need to manually add existing ones in
    // a single setState call to avoid jank on startup.
    _addExistingCameras(widget.calculator.speedCameras);
    _addConstructionAreas(widget.calculator.constructionAreas);
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
    // Recenter the map whenever the GPS position updates while keeping the
    // current zoom level so the user can zoom out if desired.
    _mapController.move(_center, _mapController.camera.zoom);
  }

  void _onCameraEvent(SpeedCameraEvent cam) {
    final exists = _markerData.values.any(
      (c) => c.latitude == cam.latitude && c.longitude == cam.longitude,
    );
    if (exists) return;
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

  void _addExistingCameras(Iterable<SpeedCameraEvent> cams) {
    final newMarkers = <Marker>[];
    for (final cam in cams) {
      final exists = _markerData.values.any(
        (c) => c.latitude == cam.latitude && c.longitude == cam.longitude,
      );
      if (exists) continue;
      final marker = Marker(
        point: LatLng(cam.latitude, cam.longitude),
        width: 40,
        height: 40,
        child: Image.asset(_iconForCamera(cam)),
      );
      newMarkers.add(marker);
      _markerData[marker] = cam;
    }
    if (newMarkers.isEmpty) return;
    setState(() {
      _cameraMarkers.addAll(newMarkers);
    });
  }

  void _onConstructionArea(GeoRect? area) {
    if (area != null) {
      _addConstructionAreas([area]);
    }
  }

  void _addConstructionAreas(Iterable<GeoRect> areas) {
    final newMarkers = <Marker>[];
    final newPolygons = <Polygon>[];
    for (final area in areas) {
      final exists = _constructionData.values.any((r) => _sameRect(r, area));
      if (exists) continue;
      // Place the marker at the centre of the construction rectangle so it is
      // always visible even for large bounding boxes.
      final marker = Marker(
        point: LatLng(
          (area.minLat + area.maxLat) / 2,
          (area.minLon + area.maxLon) / 2,
        ),
        width: 40,
        height: 40,
        child: Image.asset('images/construction_marker.png'),
      );
      final points = [
        LatLng(area.minLat, area.minLon),
        LatLng(area.minLat, area.maxLon),
        LatLng(area.maxLat, area.maxLon),
        LatLng(area.maxLat, area.minLon),
      ];
      final polygon = Polygon(
        points: points,
        color: Colors.orange.withOpacity(0.1),
        borderColor: Colors.orange,
        borderStrokeWidth: 2,
      );
      newMarkers.add(marker);
      newPolygons.add(polygon);
      _constructionData[marker] = area;
    }
    if (newMarkers.isEmpty && newPolygons.isEmpty) return;
    setState(() {
      _constructionMarkers.addAll(newMarkers);
      _constructionPolygons = [..._constructionPolygons, ...newPolygons];
    });
  }

  void _onRect(GeoRect? rect) {
    if (rect == null) {
      setState(() {
        _rectPolygons = [];
        _lastRect = null;
      });
      return;
    }
    if (_lastRect != null && _sameRect(_lastRect!, rect)) return;
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
    _lastRect = rect;
    setState(() {
      _rectPolygons = [polygon];
    });
  }

  void _addPoliceCamera() {
    final cam = SpeedCameraEvent(
      latitude: _center.latitude,
      longitude: _center.longitude,
      mobile: true,
      name: 'User camera',
    );
    unawaited(widget.calculator.updateSpeedCams([cam]));
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
          if (_rectPolygons.isNotEmpty || _constructionPolygons.isNotEmpty)
            PolygonLayer(
              polygons: [
                ..._rectPolygons,
                ..._constructionPolygons,
              ],
            ),
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
