import 'package:flutter/material.dart';

import '../ar_layout.dart';
import '../app_controller.dart';

/// Page that displays the augmented reality layout.
///
/// The heavy lifting is handled by [ARLayout]; this widget simply wires the
/// [AppController] into it so the AR view can manage background threads.
class ArPage extends StatelessWidget {
  final AppController controller;
  final VoidCallback onReturn;
  const ArPage({super.key, required this.controller, required this.onReturn});

  @override
  State<ArPage> createState() => _ArPageState();
}

class _ArPageState extends State<ArPage> {
  final GlobalKey<EdgeDetectState> _arKey = GlobalKey<EdgeDetectState>();
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _arKey.currentState?.init(
        widget.controller.gps,
        widget.controller,
        widget.controller.voicePromptQueue,
        null,
      );
    });
  }

  Future<void> _toggleAr() async {
    if (_running) {
      await _arKey.currentState?.disconnectCamera();
      widget.controller.arStatusNotifier.value = 'Idle';
    } else {
      await _arKey.currentState?.initArDetection();
      await _arKey.currentState?.connectCamera();
      widget.controller.arStatusNotifier.value = 'Scanning';
    }
    setState(() {
      _running = !_running;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ARLayout(mainApp: controller),
    );
  }
}

