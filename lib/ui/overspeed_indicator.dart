import 'package:flutter/material.dart';

/// Displays the current overspeed difference inside a red circular badge.
class OverspeedIndicator extends StatelessWidget {
  final int diff;
  const OverspeedIndicator({super.key, required this.diff});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Colors.redAccent,
        shape: BoxShape.circle,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+$diff',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold),
          ),
          const Text(
            'km/h',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
