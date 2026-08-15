import 'package:flutter/material.dart';

import 'package:vilvia/theme/vilvia_colors.dart';

/// Humanizes the raw backend enum values carried by [Resource.category] /
/// [Resource.stage] (e.g. `"child_development"`, `"0_6m"`) into the labels
/// shown in the approved design (design/home-reference.png), and maps each
/// category onto the icon/tint treatment used for its card.

const Map<String, String> _stageLabels = {
  'pregnancy': 'Pregnancy',
  'newborn': 'Newborn',
  '0_6m': '0–6 Months',
  '6_12m': '6–12 Months',
  '1_3y': '1–3 Years',
};

const Map<String, String> _categoryLabels = {
  'child_development': 'Child Development',
  'feeding': 'Feeding',
  'sleep': 'Sleep',
  'health_safety': 'Health & Safety',
  'vaccinations': 'Vaccinations',
  'everyday_guidance': 'Everyday Guidance',
};

class CategoryStyle {
  const CategoryStyle({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}

const Map<String, CategoryStyle> _categoryStyles = {
  'child_development': CategoryStyle(
    icon: Icons.pregnant_woman,
    color: VilviaColors.sageGreen,
  ),
  'sleep': CategoryStyle(
    icon: Icons.bedtime,
    color: VilviaColors.sageGreen,
  ),
  'feeding': CategoryStyle(
    icon: Icons.child_care,
    color: VilviaColors.terracotta,
  ),
  'health_safety': CategoryStyle(
    icon: Icons.health_and_safety,
    color: VilviaColors.softGold,
  ),
  'vaccinations': CategoryStyle(
    icon: Icons.vaccines,
    color: VilviaColors.terracotta,
  ),
  'everyday_guidance': CategoryStyle(
    icon: Icons.checklist,
    color: VilviaColors.softGold,
  ),
};

const _fallbackCategoryStyle = CategoryStyle(
  icon: Icons.info_outline,
  color: VilviaColors.gray,
);

String stageLabel(String stage) => _stageLabels[stage] ?? stage;

String categoryLabel(String category) => _categoryLabels[category] ?? category;

CategoryStyle categoryStyle(String category) =>
    _categoryStyles[category] ?? _fallbackCategoryStyle;

/// Stages in display order, for the filter chip row.
const List<String> orderedStages = [
  'pregnancy',
  'newborn',
  '0_6m',
  '6_12m',
  '1_3y',
];
