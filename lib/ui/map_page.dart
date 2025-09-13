import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_popup/flutter_map_marker_popup.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';

import '../rectangle_calculator.dart';

/// Dedicated map page that visualises the current position and allows the
/// user to add temporary police camera markers and perform POI lookups.
class MapPage extends StatefulWidget {
  /// Provides access to the current [_MapPageState] so non-UI code can invoke
  /// methods on the active map page.  This is primarily used by the
  /// [SpeedCamWarner] to remove obsolete markers.
  static _MapPageState? _currentState;

  /// Remove a camera marker from the map at the given [lon]/[lat]
  /// coordinates.  If no map page is currently active this call is ignored.
  static void removeCameraMarker(double lon, double lat) {
    _currentState?._removeCameraMarker(lon, lat);
  }

  final RectangleCalculatorThread calculator;
  final Stream<List<List<dynamic>>> poiStream;
  final Future<void> Function(String type) onPoiLookup;
  const MapPage({
    super.key,
    required this.calculator,
    required this.poiStream,
    required this.onPoiLookup,
  });

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late LatLng _center;
  Marker? _gpsMarker;
  final List<Marker> _cameraMarkers = [];
  final List<Marker> _poiMarkers = [];
  final Map<Marker, List<dynamic>> _poiData = {};
  final Map<Marker, SpeedCameraEvent> _markerData = {};
  final List<Marker> _constructionMarkers = [];
  final Map<Marker, GeoRect> _constructionData = {};
  final PopupController _popupController = PopupController();
  final MapController _mapController = MapController();
  StreamSubscription<SpeedCameraEvent>? _camSub;
  StreamSubscription<GeoRect?>? _rectSub;
  StreamSubscription<GeoRect?>? _constructionSub;
  StreamSubscription<List<List<dynamic>>>? _poiSub;
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
    MapPage._currentState = this;
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
    _poiSub = widget.poiStream.listen(_onPois);
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

  Widget _buildCameraMarker(SpeedCameraEvent cam) {
    final name = cam.name;
    final labels = <Widget>[];

    if (cam.maxspeed != null) {
      labels.add(
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.redAccent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${cam.maxspeed} km/h',
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        ),
      );
    }

    if (cam.predictive) {
      labels.add(
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.shade700,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'Predictive',
            style: TextStyle(fontSize: 11, color: Colors.white),
          ),
        ),
      );
    }

    if (name != null && name.isNotEmpty) {
      labels.add(
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xAA000000),
            borderRadius: BorderRadius.circular(4),
          ),
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(
            name,
            style: const TextStyle(fontSize: 11, color: Color(0xFFFFFFFF)),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      );
    }

    if (cam.direction != null && cam.direction!.isNotEmpty) {
      labels.add(
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blueAccent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${cam.direction!} °',
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Image.asset(_iconForCamera(cam), width: 32, height: 32),
        ),
        ...labels,
      ],
    );
  }

  double _markerHeightForCamera(SpeedCameraEvent cam) {
    var height = 40.0;
    if (cam.maxspeed != null) height += 28;
    if (cam.predictive) height += 28;
    if (cam.name != null && cam.name!.isNotEmpty) height += 28;
    if (cam.direction != null && cam.direction!.isNotEmpty) height += 28;
    return height;
  }

  double _markerWidthForCamera(SpeedCameraEvent cam) {
    var width = 40.0;
    if (cam.name != null && cam.name!.isNotEmpty) {
      width = 160.0;
    } else if (cam.predictive ||
        cam.maxspeed != null ||
        (cam.direction != null && cam.direction!.isNotEmpty)) {
      width = 100.0;
    }
    return width;
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(
              value,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoiPopup(List<dynamic> poi) {
    final amenity = poi[2] as String? ?? '';
    final address = poi[3] as String? ?? '';
    final postCode = poi[4] as String? ?? '';
    final street = poi[5] as String? ?? '';
    final name = poi[6] as String? ?? '';
    final phone = poi[7] as String? ?? '';
    return Card(
      child: SizedBox(
        width: 200,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (name.isNotEmpty)
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              if (amenity.isNotEmpty) _buildInfoRow('Amenity', amenity),
              if (address.isNotEmpty) _buildInfoRow('City', address),
              if (street.isNotEmpty) _buildInfoRow('Street', street),
              if (postCode.isNotEmpty) _buildInfoRow('Postcode', postCode),
              if (phone.isNotEmpty) _buildInfoRow('Phone', phone),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMarkerPopup(Marker marker) {
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
                (cam.name != null && cam.name!.isNotEmpty)
                    ? cam.name!
                    : 'Speed camera',
              ),
              if (types.isNotEmpty)
                Text(types, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
    }
    final poi = _poiData[marker];
    if (poi != null) {
      return _buildPoiPopup(poi);
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
  }

  void _onCameraEvent(SpeedCameraEvent cam) {
    MapEntry<Marker, SpeedCameraEvent>? existing;
    for (final entry in _markerData.entries) {
      if (entry.value.latitude == cam.latitude &&
          entry.value.longitude == cam.longitude) {
        existing = entry;
        break;
      }
    }
    if (existing != null) {
      final oldMarker = existing.key;
      final index = _cameraMarkers.indexOf(oldMarker);
      final newMarker = Marker(
        point: LatLng(cam.latitude, cam.longitude),
        width: _markerWidthForCamera(cam),
        height: _markerHeightForCamera(cam),
        child: _buildCameraMarker(cam),
      );
      setState(() {
        if (index != -1) {
          final updated = List<Marker>.from(_cameraMarkers);
          updated[index] = newMarker;
          _cameraMarkers = updated;
        } else {
          _cameraMarkers = [..._cameraMarkers, newMarker];
        }
        _markerData
          ..remove(oldMarker)
          ..[newMarker] = cam;
      });
      return;
    }
    final marker = Marker(
      point: LatLng(cam.latitude, cam.longitude),
      width: _markerWidthForCamera(cam),
      height: _markerHeightForCamera(cam),
      child: _buildCameraMarker(cam),
    );
    setState(() {
      _cameraMarkers = [..._cameraMarkers, marker];
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
        width: _markerWidthForCamera(cam),
        height: _markerHeightForCamera(cam),
        child: _buildCameraMarker(cam),
      );
      newMarkers.add(marker);
      _markerData[marker] = cam;
    }
    if (newMarkers.isEmpty) return;
    setState(() {
      _cameraMarkers = [..._cameraMarkers, ...newMarkers];
    });
  }

  /// Remove a camera marker matching the provided [lon] and [lat]
  /// coordinates.  If no such marker exists the method is a no-op.
  void _removeCameraMarker(double lon, double lat) {
    Marker? markerToRemove;
    for (final entry in _markerData.entries) {
      final cam = entry.value;
      if (cam.longitude == lon && cam.latitude == lat) {
        markerToRemove = entry.key;
        break;
      }
    }
    if (markerToRemove != null) {
      setState(() {
        _cameraMarkers =
            _cameraMarkers.where((m) => m != markerToRemove).toList();
        _markerData.remove(markerToRemove);
      });
    }
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
      newPolygons.add(polygon);
      newMarkers.add(marker);
      _constructionData[marker] = area;
    }
    if (newMarkers.isEmpty && newPolygons.isEmpty) return;
    setState(() {
      _constructionMarkers = [..._constructionMarkers, ...newMarkers];
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
    _poiSub?.cancel();
    MapPage._currentState = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: PopupScope(
        popupController: _popupController,
        child: FlutterMap(
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
            MarkerClusterLayerWidget(
              options: MarkerClusterLayerOptions(
                markers: _cameraMarkers,
                maxClusterRadius: 45,
                disableClusteringAtZoom: 16,
                size: const Size(40, 40),
                alignment: Alignment.center,
                builder: (context, markers) => CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Text(
                    markers.length.toString(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                popupOptions: PopupOptions(
                  popupController: _popupController,
                  popupBuilder: (context, marker) => _buildMarkerPopup(marker),
                ),
              ),
            ),
            PopupMarkerLayer(
              options: PopupMarkerLayerOptions(
                popupController: _popupController,
                markers: [
                  ..._constructionMarkers,
                  ..._poiMarkers
                ],
                popupDisplayOptions: PopupDisplayOptions(
                  builder: (context, marker) => _buildMarkerPopup(marker),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            onPressed: _addPoliceCamera,
            tooltip: 'Add police camera',
            child: const Icon(Icons.local_police),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: _selectPoiLookup,
            tooltip: 'Search POIs',
            child: const Icon(Icons.place),
          ),
        ],
      ),
    );
  }

  void _onPois(List<List<dynamic>> pois) {
    final markers = <Marker>[];
    final data = <Marker, List<dynamic>>{};
    final seen = <String>{};
    for (final poi in pois) {
      final key = '${poi[0]},${poi[1]}';
      if (seen.add(key)) {
        final marker = Marker(
          point: LatLng(poi[0], poi[1]),
          width: 40,
          height: 40,
          child: (poi[2] == 'fuel')
              ? Image.asset('images/fuel.png')
              : Image.asset('images/hospital.png'),
        );
        markers.add(marker);
        data[marker] = poi;
      }
    }
    setState(() {
      _poiMarkers = markers;
      _poiData = data;
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
      await widget.onPoiLookup(type);
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
