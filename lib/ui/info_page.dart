import 'package:flutter/material.dart';

import '../rectangle_calculator.dart';

/// Simple page displaying application information and credits.
class InfoPage extends StatelessWidget {
  final RectangleCalculatorThread calculator;
  const InfoPage({super.key, required this.calculator});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: SingleChildScrollView(
                child: Text(
                  'Welcome to SpeedCamWarner\n\n'
                  'SpeedCamWarner is dedicated to helping drivers stay informed, safe, and compliant on the road.\n\n'
                  'Our system delivers timely, precise warnings about speed cameras and speed limits—enabling confident, responsible driving.\n\n'
                  'What We Offer\n'
                  'Accurate Alerts: Real-time notifications for fixed, mobile, and average-speed cameras, plus updated speed limits.\n'
                  'Intuitive Interface: A user-friendly dashboard designed for both quick glances and in-depth configuration.\n'
                  'Comprehensive Coverage: Supported across major regions with frequent updates to maintain database accuracy.\n'
                  'Offline Capability: Continue receiving alerts without an internet connection, ensuring consistent coverage wherever you drive.\n'
                  'Why Choose Us\n'
                  'Safety First: Our priority is helping drivers avoid sudden braking and speed-related incidents.\n'
                  'Privacy Protection: Your location data stays on your device—no tracking, no sharing.\n'
                  'Active Community: Users contribute and verify camera locations, keeping information current.\n'
                  'Dedicated Support: Responsive assistance to handle any questions or technical needs.\n'
                  'Get Started\n'
                  'Experience smarter driving with SpeedCamWarner. For demos, licensing, or additional support, contact us at support@speedcamwarner.com. Your journey toward safer, more informed driving begins here.',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
