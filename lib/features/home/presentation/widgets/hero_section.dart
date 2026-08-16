import 'package:flutter/material.dart';

import 'package:vilvia/theme/vilvia_colors.dart';

/// Welcome/hero block: headline, subtitle, and the approved hero
/// illustration, per the approved reference (design/home-reference.png).
class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'As the saying goes,',
          style: textTheme.bodyMedium?.copyWith(color: VilviaColors.gray),
        ),
        const SizedBox(height: 4),
        Text(
          '“It takes a village to raise a child.”',
          style: textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Vilvia helps you find yours.',
          style: textTheme.headlineMedium
              ?.copyWith(color: VilviaColors.sageGreen),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: const AspectRatio(
            aspectRatio: 3 / 2,
            child: Image(
              image: AssetImage('assets/brand/home_hero.png'),
              fit: BoxFit.cover,
            ),
          ),
        ),
      ],
    );
  }
}
