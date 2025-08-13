import 'package:flutter/material.dart';

import '../ar_layout.dart';
import '../app_controller.dart';

/// Page that displays the augmented reality layout.
///
/// The heavy lifting is handled by [ARLayout]; this widget simply wires the
/// [AppController] into it so the AR view can manage background threads.
class ArPage extends StatelessWidget {
  final AppController controller;
  const ArPage({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ARLayout(mainApp: controller),
    );
  }
}

