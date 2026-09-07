import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The small pill tag used everywhere a risk_level ("Green"/"Yellow"/
/// "Orange"/"Red") needs to show up as a label — Result, Timeline, Home.
class RiskBadge extends StatelessWidget {
  const RiskBadge({super.key, required this.level});

  final String? level;

  @override
  Widget build(BuildContext context) {
    final color = RnColors.forRiskLevel(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        level ?? 'Unknown',
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The small filled dot used next to "Today's status" on Home.
class RiskDot extends StatelessWidget {
  const RiskDot({super.key, required this.level, this.size = 11});

  final String? level;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: RnColors.forRiskLevel(level),
        shape: BoxShape.circle,
      ),
    );
  }
}
