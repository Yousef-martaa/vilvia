import 'package:flutter/material.dart';

import 'package:vilvia/theme/vilvia_colors.dart';
import 'package:vilvia/theme/vilvia_text_theme.dart';

/// The Vilvia design foundation: a single [ThemeData] built from the brand
/// colors and type scale in the approved design system reference
/// (design/design-system.png). Kept intentionally small — only the
/// component themes actually used by the app today are configured here.
abstract final class VilviaTheme {
  static ThemeData light() {
    final colorScheme = const ColorScheme.light().copyWith(
      primary: VilviaColors.sageGreen,
      onPrimary: VilviaColors.surface,
      secondary: VilviaColors.terracotta,
      onSecondary: VilviaColors.surface,
      tertiary: VilviaColors.softGold,
      onTertiary: VilviaColors.charcoal,
      surface: VilviaColors.surface,
      onSurface: VilviaColors.charcoal,
      error: VilviaColors.error,
      onError: VilviaColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: VilviaColors.warmIvory,
      textTheme: buildVilviaTextTheme(),
      extensions: const [VilviaColorsExtension.light],
      cardTheme: CardThemeData(
        color: VilviaColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}
