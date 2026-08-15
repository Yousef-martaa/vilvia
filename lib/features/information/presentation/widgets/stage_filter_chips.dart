import 'package:flutter/material.dart';

import 'package:vilvia/features/information/presentation/resource_labels.dart';
import 'package:vilvia/theme/vilvia_colors.dart';

/// Horizontal, scrollable stage filter row ("All" + one chip per stage),
/// matching the filter row in the approved Resources mockup
/// (design/home-reference.png).
class StageFilterChips extends StatelessWidget {
  const StageFilterChips({
    super.key,
    required this.selectedStage,
    required this.onStageSelected,
  });

  /// `null` means "All".
  final String? selectedStage;
  final ValueChanged<String?> onStageSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: orderedStages.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _FilterChip(
              label: 'All',
              selected: selectedStage == null,
              onTap: () => onStageSelected(null),
            );
          }
          final stage = orderedStages[index - 1];
          return _FilterChip(
            label: stageLabel(stage),
            selected: selectedStage == stage,
            onTap: () => onStageSelected(stage),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: selected ? VilviaColors.sageGreen : VilviaColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: selected
            ? BorderSide.none
            : const BorderSide(color: Color(0xFFE2E0DA)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: selected ? VilviaColors.surface : VilviaColors.charcoal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
