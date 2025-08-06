import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workspace/main.dart';

void main() {
  testWidgets('renders dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(SpeedCamWarnerApp());
    // Verify that the main title is shown.
    expect(find.text('SpeedCamWarner'), findsOneWidget);
    // Verify that the speed display starts at zero.
    expect(find.text('0 km/h'), findsOneWidget);
  });
}
