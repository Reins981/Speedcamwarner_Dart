import 'package:flutter/material.dart';

import '../ar_layout.dart';
import '../app_controller.dart';

/// Page that exposes the augmented reality camera view.  The heavy lifting is
/// performed by [EdgeDetect]; this widget merely offers start/stop controls.
class ArPage extends StatefulWidget {
  final AppController controller;
  final VoidCallback onReturn;
  const ArPage({super.key, required this.controller, required this.onReturn});

  @override
  State<ArPage> createState() => _ArPageState();
}

class _ArPageState extends State<ArPage> {
  final GlobalKey<EdgeDetectState> _arKey = GlobalKey<EdgeDetectState>();
  bool _running = false;

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
      appBar: AppBar(
        title: const Text('AR View'),
        leading: _running
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onReturn,
              )
            : null,
      ),
      body: Stack(
        children: [
          Positioned.fill(
              child: EdgeDetect(
            key: _arKey,
            statusNotifier: widget.controller.arStatusNotifier,
          )),
          if (!_running)
            const Center(child: Text('Camera stopped')),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleAr,
        tooltip: _running ? 'Stop AR' : 'Start AR',
        child: Icon(_running ? Icons.stop : Icons.play_arrow),
      ),
    );
  }
}
