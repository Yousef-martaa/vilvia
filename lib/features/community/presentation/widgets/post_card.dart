import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:vilvia/features/community/data/post.dart';
import 'package:vilvia/theme/vilvia_colors.dart';
import 'package:vilvia/widgets/tag_chip.dart';

class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.isSignedIn,
    required this.isReactionPending,
    this.onReportTap,
    this.onReactionTap,
    this.onCommentsTap,
  });

  final Post post;
  final bool isSignedIn;
  final bool isReactionPending;
  final VoidCallback? onReportTap;
  final VoidCallback? onReactionTap;
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
              if (isSignedIn)
                IconButton(
                  onPressed: onReportTap,
                  icon: const Icon(Icons.flag_outlined),
                  tooltip: 'Report post',
                  visualDensity: VisualDensity.compact,
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
          Row(
            children: [
              Expanded(
                child: isSignedIn
                    ? TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        onPressed: isReactionPending ? null : onReactionTap,
                        icon: isReactionPending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                post.hasReacted
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                              ),
                        label: Text(_reactionLabel(post.reactionCount)),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.favorite_border, size: 18),
                            const SizedBox(width: 6),
                            Text(_reactionLabel(post.reactionCount)),
                          ],
                        ),
                      ),
              ),
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  onPressed: onCommentsTap,
                  icon: const Icon(Icons.comment_outlined),
                  label: Text('${post.commentCount} comments'),
                ),
              ),
            ],
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

String _reactionLabel(int count) => '$count reaction${count == 1 ? '' : 's'}';

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
