import 'package:flutter/material.dart';
import 'dart:async';
import 'app_controller.dart';
import 'config.dart';
import 'ui/home.dart';
import 'background_service.dart';
import 'notification_service.dart';

/// Entry point of the SpeedCamWarner application.
///
/// The original Python project bundled all screens inside a single Kivy file.
/// In this Flutter port we provide a [HomePage] with a bottom navigation bar
/// and multiple dedicated screens while background modules are coordinated by
/// [AppController].
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundService.initialize();
  await NotificationService.initialize();
  await AppConfig.load();
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
