import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Small coloured status pill (icon + label) used across dashboards.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
    this.onDark = false,
  });

  final String label;
  final Color color;
  final IconData icon;

  /// When placed over a dark/gradient surface, render as a translucent white
  /// "glass" chip with white text for contrast.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final bg = onDark ? Colors.white.withValues(alpha: 0.20) : color.withValues(alpha: 0.12);
    final fg = onDark ? Colors.white : color;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
