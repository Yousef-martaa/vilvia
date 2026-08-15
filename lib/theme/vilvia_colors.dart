import 'package:flutter/material.dart';

/// Raw Vilvia brand colors, per the approved design system reference
/// (design/design-system.png).
abstract final class VilviaColors {
  static const sageGreen = Color(0xFF7FA68B);
  static const terracotta = Color(0xFFC97C5D);
  static const softGold = Color(0xFFE6BE6A);
  static const warmIvory = Color(0xFFFAF8F3);
  static const surface = Color(0xFFFFFFFF);
  static const charcoal = Color(0xFF2F3437);
  static const gray = Color(0xFF6B7280);
  static const success = Color(0xFF4F8A5B);
  static const warning = Color(0xFFD9A441);
  static const error = Color(0xFFC85C5C);
}

/// Colors that don't map onto Flutter's [ColorScheme] roles (e.g. success /
/// warning have no built-in slot). Exposed as a [ThemeExtension] so they're
/// reachable via `Theme.of(context).extension<VilviaColorsExtension>()`,
/// the same way the rest of the theme is consumed.
@immutable
class VilviaColorsExtension extends ThemeExtension<VilviaColorsExtension> {
  const VilviaColorsExtension({
    required this.success,
    required this.warning,
  });

  final Color success;
  final Color warning;

  static const light = VilviaColorsExtension(
    success: VilviaColors.success,
    warning: VilviaColors.warning,
  );

  @override
  VilviaColorsExtension copyWith({Color? success, Color? warning}) {
    return VilviaColorsExtension(
      success: success ?? this.success,
      warning: warning ?? this.warning,
    );
  }

  @override
  VilviaColorsExtension lerp(
    ThemeExtension<VilviaColorsExtension>? other,
    double t,
  ) {
    if (other is! VilviaColorsExtension) return this;
    return VilviaColorsExtension(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}
