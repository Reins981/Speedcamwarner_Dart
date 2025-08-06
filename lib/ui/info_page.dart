import 'package:flutter/material.dart';

/// Simple page displaying application information and credits.
class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: const Padding(
        padding: EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Text(
            'SpeedCamWarner\n\n'
            'This Flutter port replaces the original Kivy frontend. '
            'All navigation and visualisation now rely on native widgets. '
            'Additional modules continue to update the UI through ValueNotifiers.'
            '\n\nDeveloped as part of the open source transition.',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}
