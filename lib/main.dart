import 'package:flutter/material.dart';
import 'dart:async';
import 'deviation_checker.dart';
import '../libs/ai/ai_predictive_analytics.dart';
import 'gps_test_data_generator.dart';
import 'overspeed_checker.dart';
import 'rectangle_calculator.dart';
import 'linked_list_generator.dart';
import 'app_controller.dart';
import 'ui/home.dart';

/// Entry point of the SpeedCamWarner application.
///
/// The original Python project bundled all screens inside a single Kivy file.
/// In this Flutter port we provide a [HomePage] with a bottom navigation bar
/// and multiple dedicated screens while background modules are coordinated by
/// [AppController].
void main() {
  runApp(SpeedCamWarnerApp());
}

class SpeedCamWarnerApp extends StatelessWidget {
  SpeedCamWarnerApp({super.key}) : controller = AppController();

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpeedCamWarner',
      theme: ThemeData.dark(),
      home: HomePage(controller: controller),
    );
  }
}
