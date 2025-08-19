import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workspace/rectangle_calculator.dart';
import 'package:workspace/overspeed_checker.dart';
import 'package:workspace/ui/stats_page.dart';

void main() {
  testWidgets('StatsPage counts unique cameras only once', (tester) async {
    final calc = RectangleCalculatorThread(overspeedChecker: OverspeedChecker());
    addTearDown(() async => await calc.dispose());

    await tester.pumpWidget(MaterialApp(home: StatsPage(calculator: calc)));

    final cam = SpeedCameraEvent(latitude: 1.0, longitude: 1.0, fixed: true);
    await calc.updateSpeedCams([cam]);
    await calc.updateSpeedCams([cam]);

    await tester.pumpAndSettle();

    final rowFinder = find.ancestor(
      of: find.text('Fix Cameras'),
      matching: find.byType(Row),
    );
    final countFinder = find.descendant(
      of: rowFinder,
      matching: find.text('1'),
    );
    expect(countFinder, findsOneWidget);
  });
}
