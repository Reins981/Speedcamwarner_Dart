import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../app_controller.dart';

/// Simple page providing Start, Stop and Exit controls.
///
/// Mirrors the action layout from the legacy ``main.py`` where the buttons
/// were stacked vertically.
class ActionsPage extends StatelessWidget {
  final AppController controller;
  final VoidCallback onFinished;

  const ActionsPage({
    super.key,
    required this.controller,
    required this.onFinished,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Actions')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildButton('Start', () async {
              await controller.start();
              onFinished();
            }),
            const SizedBox(height: 16),
            _buildButton('Stop', () async {
              await controller.stop();
              onFinished();
            }),
            const SizedBox(height: 16),
            _buildButton('Exit', () async {
              await controller.dispose();
              SystemNavigator.pop();
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(
      BuildContext context, String label, Future<void> Function() onPressed) {
    return SizedBox(
      height: 80,
      child: ElevatedButton(
        onPressed: () async {
          try {
            await onPressed();
          } catch (e) {
            if (e.toString().contains('Location services are disabled')) {
              await _showLocationDisabledDialog(context);
            }
          }
        },
        child: Text(label, style: const TextStyle(fontSize: 32)),
      ),
    );
  }

  Future<void> _showLocationDisabledDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location services disabled'),
        content: const Text(
            'Please enable location services on your device to continue.'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await Geolocator.openLocationSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
