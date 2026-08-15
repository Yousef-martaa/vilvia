import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:vilvia/theme/vilvia_colors.dart';

/// Builds the Vilvia [TextTheme]: Lora for headings, Inter for UI/body
/// text, matching the type scale in the approved design system reference
/// (design/design-system.png).
TextTheme buildVilviaTextTheme() {
  final base = TextTheme(
    headlineLarge: const TextStyle(fontSize: 32, height: 40 / 32),
    headlineMedium: const TextStyle(fontSize: 24, height: 32 / 24),
    titleLarge: const TextStyle(fontSize: 20, height: 28 / 20),
    bodyLarge: const TextStyle(fontSize: 16, height: 24 / 16),
    bodyMedium: const TextStyle(fontSize: 14, height: 20 / 14),
    labelSmall: const TextStyle(fontSize: 12, height: 16 / 12),
  );

  return GoogleFonts.interTextTheme(base)
      .copyWith(
        headlineLarge: GoogleFonts.lora(
          textStyle: base.headlineLarge,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: GoogleFonts.lora(
          textStyle: base.headlineMedium,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: GoogleFonts.lora(
          textStyle: base.titleLarge,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: GoogleFonts.inter(
          textStyle: base.bodyLarge,
          fontWeight: FontWeight.w500,
        ),
      )
      .apply(
        bodyColor: VilviaColors.charcoal,
        displayColor: VilviaColors.charcoal,
      );
}
