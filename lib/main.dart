import 'package:flutter/material.dart';
import 'dart:async';
import 'deviation_checker.dart';
import 'ai_predictive_analytics.dart';
import 'gps_test_data_generator.dart';
import 'overspeed_checker.dart';
import 'rectangle_calculator.dart';
import 'linked_list_generator.dart';

void main() {
  // Example usage of DeviationChecker
  DeviationChecker deviationChecker = DeviationChecker();
  deviationChecker.process([10.0, 15.0, 20.0]);
  deviationChecker.dispose();

  // Example usage of MostProbableWay
  MostProbableWay mostProbableWay = MostProbableWay();
  mostProbableWay.setMostProbableRoadName("Highway 101");
  print("Most Probable Road: ${mostProbableWay.getMostProbableRoad()}");

  // Example usage of DoubleLinkedListNodes
  DoubleLinkedListNodes linkedList = DoubleLinkedListNodes();
  linkedList.appendNode(Node(
    id: 1,
    latitudeStart: 37.7749,
    longitudeStart: -122.4194,
    latitudeEnd: 37.8044,
    longitudeEnd: -122.2711,
  ));
  linkedList.appendNode(Node(
    id: 2,
    latitudeStart: 37.8044,
    longitudeStart: -122.2711,
    latitudeEnd: 37.7749,
    longitudeEnd: -122.4194,
  ));

  Node? closestNode = linkedList.matchNode(37.7749, -122.4194);
  if (closestNode != null) {
    print('Closest Node ID: ${closestNode.id}');
  } else {
    print('No matching node found.');
  }

  runApp(SpeedCameraApp());
}

class SpeedCameraApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speed Camera Warner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DeviationChecker _deviationChecker = DeviationChecker();
  final AIPredictiveAnalytics _aiAnalytics = AIPredictiveAnalytics();
  final GpsTestDataGenerator _gpsGenerator = GpsTestDataGenerator(maxNum: 1000);
  final OverspeedChecker _overspeedChecker = OverspeedChecker();
  StreamSubscription<String>? _interruptSubscription;

  @override
  void initState() {
    super.initState();
    _interruptSubscription =
        _deviationChecker.interruptQueueStream.listen((status) {
      print('DeviationChecker Status: $status');
    });
    _deviationChecker.run();
  }

  @override
  void dispose() {
    _interruptSubscription?.cancel();
    _deviationChecker.terminate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Speed Camera Warner'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _simulateDrivingData,
              child: Text('Simulate Driving Data'),
            ),
            ElevatedButton(
              onPressed: _addSimulatedCameras,
              child: Text('Add Simulated Cameras'),
            ),
            ElevatedButton(
              onPressed: _generateGpsData,
              child: Text('Generate GPS Data'),
            ),
            ElevatedButton(
              onPressed: _checkOverspeed,
              child: Text('Check Overspeed'),
            ),
          ],
        ),
      ),
    );
  }

  void _simulateDrivingData() {
    // Example JSON data
    String jsonData =
        '{"cameras": [{"coordinates": [{"latitude": 40.7128, "longitude": -74.0060}]}]}';
    var cameraData = _aiAnalytics.loadCameraData(jsonData);
    var samples = _aiAnalytics.simulateDrivingData(cameraData, 10);
    print(samples);
  }

  void _addSimulatedCameras() async {
    try {
      await _aiAnalytics.addSimulatedCameraEntries(
          'assets/training.json', 11, 1000);
      print('Simulated cameras added successfully.');
    } catch (e) {
      print('Error adding simulated cameras: $e');
    }
  }

  void _generateGpsData() {
    var gpsData = _gpsGenerator.getEvents();
    print('Generated GPS Data: ${gpsData.length} events.');
  }

  void _checkOverspeed() {
    var currentSpeed = 80; // Example current speed
    var overspeedEntry = {'condition': 60}; // Example max speed
    _overspeedChecker.process(currentSpeed, overspeedEntry);
  }
}
