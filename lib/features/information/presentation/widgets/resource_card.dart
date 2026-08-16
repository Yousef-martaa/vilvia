import 'package:flutter/material.dart';

import 'package:vilvia/features/information/data/resource.dart';
import 'package:vilvia/features/information/presentation/resource_labels.dart';
import 'package:vilvia/theme/vilvia_colors.dart';
import 'package:vilvia/widgets/tag_chip.dart';
import 'package:vilvia/widgets/tinted_icon_badge.dart';

/// A single resource row, styled per the approved Resources mockup
/// (design/home-reference.png): a tinted category icon, colored
/// category/stage tag chips, title, summary, and a trailing chevron.
/// Tapping it invokes [onTap] (wired by [ResourcesScreen] to open the
/// Resource Details screen).
class ResourceCard extends StatelessWidget {
  const ResourceCard({super.key, required this.resource, required this.onTap});

  final Resource resource;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = categoryStyle(resource.category);

    return Material(
      color: VilviaColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: VilviaColors.charcoal.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TintedIconBadge(icon: style.icon, color: style.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TagChip(
                          label: categoryLabel(resource.category),
                          color: style.color,
                        ),
                        TagChip(
                          label: stageLabel(resource.stage),
                          color: VilviaColors.gray,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(resource.title, style: textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      resource.summary,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: VilviaColors.gray),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: VilviaColors.gray),
            ],
          ),
        ),
      ),
    );
  }
}
