import 'package:flutter/material.dart';

/// A circular, tinted icon badge: a soft-colored background circle with a
/// matching-colored icon centered in it. Shared visual primitive used
/// wherever the Vilvia design shows a category/topic icon this way (e.g.
/// Resources category icons, Home's circle cards).
class TintedIconBadge extends StatelessWidget {
  const TintedIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 48,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color),
    );
  }
}
