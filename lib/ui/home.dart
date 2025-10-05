import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'actions_page.dart';
import 'dashboard.dart';
import 'drive_insights_page.dart';
import 'info_page.dart';
import 'map_page.dart';
import 'stats_page.dart';

/// Root widget with a bottom navigation bar that switches between the main
/// screens of the application.  It also manages the [AppController]
/// lifecycle so backend threads are started and stopped with the UI.
class HomePage extends StatefulWidget {
  final AppController controller;
  const HomePage({super.key, required this.controller});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  late final List<Widget> _pages;

  void _showMain() => setState(() => _index = 1);

  @override
  void initState() {
    super.initState();
    _pages = [
      ActionsPage(
        controller: widget.controller,
        onFinished: _showMain,
      ),
      DashboardPage(
        controller: widget.controller,
        calculator: widget.controller.calculator,
        direction: widget.controller.directionNotifier,
        averageBearing: widget.controller.averageBearingValue,
        checker: widget.controller.overspeedChecker,
      ),
      MapPage(
        calculator: widget.controller.calculator,
        poiStream: widget.controller.poiStream,
        onPoiLookup: widget.controller.lookupPois,
      ),
      DriveInsightsPage(controller: widget.controller),
      InfoPage(calculator: widget.controller.calculator),
      StatsPage(calculator: widget.controller.calculator),
    ];
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black54,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.power_settings_new), label: 'Actions'),
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(
              icon: Icon(Icons.insights), label: 'Insights'),
          BottomNavigationBarItem(
              icon: Icon(Icons.info_outline), label: 'Info'),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Stats'),
        ],
      ),
    );
  }
}
