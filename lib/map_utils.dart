import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_popup/flutter_map_marker_popup.dart';
import 'package:latlong2/latlong.dart';

enum MarkerType { cam, poi, construction }

class CustomMarkerBase {
  static bool markerPressedPois = false;
  static bool markerPressedCams = false;
  static bool markerPressedConstructions = false;
  static CustomMarkerBase? markerInstance;
  static final PopupController popupController = PopupController();
  static final Map<Marker, CustomMarkerBase> _markerLookup = {};

  final List<CustomMarkerBase> markerListPois;
  final List<CustomMarkerBase> markerListCams;
  final List<CustomMarkerBase> markerListConstructions;
  final MarkerType markerType;
  final Widget popup;
  late final Marker marker;

  CustomMarkerBase({
    required this.markerType,
    required LatLng position,
    required Widget markerWidget,
    required this.popup,
    required this.markerListPois,
    required this.markerListCams,
    required this.markerListConstructions,
  }) {
    marker = Marker(
      point: position,
      width: 40,
      height: 40,
      builder: (ctx) => GestureDetector(
        onTap: onTap,
        child: markerWidget,
      ),
    );
    _markerLookup[marker] = this;
  }

  void onTap() {
    markerInstance = this;
    switch (markerType) {
      case MarkerType.cam:
        markerPressedCams = !markerPressedCams;
        break;
      case MarkerType.poi:
        markerPressedPois = !markerPressedPois;
        break;
      case MarkerType.construction:
        markerPressedConstructions = !markerPressedConstructions;
        break;
    }
    open();
  }

  void open() {
    List<CustomMarkerBase> markerList;
    bool markerPressed;
    switch (markerType) {
      case MarkerType.cam:
        markerList = markerListCams;
        markerPressed = markerPressedCams;
        break;
      case MarkerType.poi:
        markerList = markerListPois;
        markerPressed = markerPressedPois;
        break;
      case MarkerType.construction:
        markerList = markerListConstructions;
        markerPressed = markerPressedConstructions;
        break;
    }
    if (markerPressed && markerInstance != null) {
      popupController.showPopupsOnlyFor([markerInstance!.marker]);
    } else {
      popupController.showPopupsOnlyFor(
          markerList.map((m) => m.marker).toList());
    }
  }

  static Widget popupBuilder(BuildContext context, Marker marker) {
    return _markerLookup[marker]?.popup ?? const SizedBox.shrink();
  }
}

class CustomMarkerPois extends CustomMarkerBase {
  CustomMarkerPois({
    required LatLng position,
    required Widget markerWidget,
    required Widget popup,
    required List<CustomMarkerBase> markerListPois,
    required List<CustomMarkerBase> markerListCams,
    required List<CustomMarkerBase> markerListConstructions,
  }) : super(
          markerType: MarkerType.poi,
          position: position,
          markerWidget: markerWidget,
          popup: popup,
          markerListPois: markerListPois,
          markerListCams: markerListCams,
          markerListConstructions: markerListConstructions,
        );
}

class CustomMarkerCams extends CustomMarkerBase {
  CustomMarkerCams({
    required LatLng position,
    required Widget markerWidget,
    required Widget popup,
    required List<CustomMarkerBase> markerListPois,
    required List<CustomMarkerBase> markerListCams,
    required List<CustomMarkerBase> markerListConstructions,
  }) : super(
          markerType: MarkerType.cam,
          position: position,
          markerWidget: markerWidget,
          popup: popup,
          markerListPois: markerListPois,
          markerListCams: markerListCams,
          markerListConstructions: markerListConstructions,
        );
}

class CustomMarkerConstructionAreas extends CustomMarkerBase {
  CustomMarkerConstructionAreas({
    required LatLng position,
    required Widget markerWidget,
    required Widget popup,
    required List<CustomMarkerBase> markerListPois,
    required List<CustomMarkerBase> markerListCams,
    required List<CustomMarkerBase> markerListConstructions,
  }) : super(
          markerType: MarkerType.construction,
          position: position,
          markerWidget: markerWidget,
          popup: popup,
          markerListPois: markerListPois,
          markerListCams: markerListCams,
          markerListConstructions: markerListConstructions,
        );
}

class CustomAsyncImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  const CustomAsyncImage(
      {super.key, required this.url, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return Image.network(url, width: width, height: height);
  }
}

class CustomBubble extends StatelessWidget {
  final Widget child;
  const CustomBubble({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(margin: EdgeInsets.zero, child: child);
  }
}

class CustomLabel extends StatefulWidget {
  final List<String> initialText;
  const CustomLabel({super.key, this.initialText = const []});

  @override
  State<CustomLabel> createState() => _CustomLabelState();
}

class _CustomLabelState extends State<CustomLabel> {
  late String text;
  @override
  void initState() {
    super.initState();
    text = widget.initialText.join('\n');
  }

  void updateText(List<String> args) {
    setState(() {
      text = args.join('\n');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(text);
  }
}

class CustomLayout extends StatelessWidget {
  final List<Widget> children;
  final Axis direction;
  const CustomLayout({
    super.key,
    this.children = const [],
    this.direction = Axis.vertical,
  });

  @override
  Widget build(BuildContext context) {
    return direction == Axis.vertical
        ? Column(children: children)
        : Row(children: children);
  }
}

