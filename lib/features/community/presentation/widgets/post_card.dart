import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:vilvia/features/community/data/post.dart';
import 'package:vilvia/theme/vilvia_colors.dart';
import 'package:vilvia/widgets/tag_chip.dart';

class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post, this.onCommentsTap});

  final Post post;
  final VoidCallback? onCommentsTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: VilviaColors.surface,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: VilviaColors.sageGreen.withValues(alpha: 0.15),
                child: Text(
                  _authorInitial(post.authorName),
                  style: textTheme.labelLarge?.copyWith(
                    color: VilviaColors.sageGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.authorName, style: textTheme.titleMedium),
                    Text(
                      DateFormat('MMM d, y').format(post.createdAt.toLocal()),
                      style: textTheme.bodySmall?.copyWith(
                        color: VilviaColors.gray,
                      ),
                    ),
                  ],
                ),
              ),
              TagChip(
                label: _categoryLabel(post.category),
                color: VilviaColors.terracotta,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(post.title, style: textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            post.body,
            style: textTheme.bodyMedium?.copyWith(color: VilviaColors.gray),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: onCommentsTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${post.reactionCount} reactions · ${post.commentCount} comments',
                style: textTheme.bodySmall?.copyWith(color: VilviaColors.gray),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _authorInitial(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
}

String _categoryLabel(String category) {
  if (category == 'qa') return 'Q&A';
  return category
      .split('_')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}
