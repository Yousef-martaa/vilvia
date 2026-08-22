import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:vilvia/features/community/data/comment.dart';
import 'package:vilvia/features/community/data/community_api_client.dart';
import 'package:vilvia/features/community/data/post.dart';
import 'package:vilvia/theme/vilvia_colors.dart';

Future<void> showCommentsSheet({
  required BuildContext context,
  required Post post,
  required CommunityApiClient apiClient,
  required bool isSignedIn,
  required ValueChanged<int> onCommentCountChanged,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => CommentsSheet(
    post: post,
    apiClient: apiClient,
    isSignedIn: isSignedIn,
    onCommentCountChanged: onCommentCountChanged,
  ),
);

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({
    super.key,
    required this.post,
    required this.apiClient,
    required this.isSignedIn,
    required this.onCommentCountChanged,
  });

  final Post post;
  final CommunityApiClient apiClient;
  final bool isSignedIn;
  final ValueChanged<int> onCommentCountChanged;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _bodyController = TextEditingController();
  List<Comment>? _comments;
  late int _commentCount;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _commentCount = widget.post.commentCount;
    _loadComments();
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final comments = await widget.apiClient.getComments(widget.post.id);
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty || body.length > 2000) {
      setState(() {
        _submitError = 'Please enter a comment (1-2000 characters).';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      final created = await widget.apiClient.createComment(
        postId: widget.post.id,
        body: body,
      );
      if (!mounted) return;
      setState(() {
        _comments = [...?_comments, created.comment];
        _commentCount = created.commentCount;
        _isSubmitting = false;
        _bodyController.clear();
      });
      widget.onCommentCountChanged(created.commentCount);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return FractionallySizedBox(
      heightFactor: 0.8,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Comments ($_commentCount)',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close comments',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildComments()),
            const SizedBox(height: 12),
            if (widget.isSignedIn) _buildComposer() else _buildSignedOut(),
          ],
        ),
      ),
    );
  }

  Widget _buildComments() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Failed to load comments.'),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _loadComments,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    final comments = _comments ?? [];
    if (comments.isEmpty) return const Center(child: Text('No comments yet.'));
    return ListView.separated(
      itemCount: comments.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (_, index) => _CommentTile(comment: comments[index]),
    );
  }

  Widget _buildSignedOut() => const Text(
    'Sign in to add a comment.',
    style: TextStyle(color: VilviaColors.gray),
  );

  Widget _buildComposer() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: _bodyController,
        decoration: const InputDecoration(labelText: 'Add a comment'),
        minLines: 2,
        maxLines: 4,
        maxLength: 2000,
      ),
      if (_submitError != null)
        Text(_submitError!, style: const TextStyle(color: VilviaColors.error)),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Post Comment'),
        ),
      ),
    ],
  );
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final Comment comment;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      child: Text(
        comment.authorName.trim().isEmpty
            ? '?'
            : comment.authorName.trim().characters.first.toUpperCase(),
      ),
    ),
    title: Text(comment.authorName),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(comment.body),
        const SizedBox(height: 4),
        Text(DateFormat('MMM d, y').format(comment.createdAt.toLocal())),
      ],
    ),
  );
}
