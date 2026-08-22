class Comment {
  const Comment({
    required this.id,
    required this.authorName,
    required this.authorAvatarUrl,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String authorName;
  final String? authorAvatarUrl;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id: json['id'] as String,
    authorName: json['author_name'] as String,
    authorAvatarUrl: json['author_avatar_url'] as String?,
    body: json['body'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );
}

class CreatedComment {
  const CreatedComment({required this.comment, required this.commentCount});

  final Comment comment;
  final int commentCount;

  factory CreatedComment.fromJson(Map<String, dynamic> json) => CreatedComment(
    comment: Comment.fromJson(json['comment'] as Map<String, dynamic>),
    commentCount: json['comment_count'] as int,
  );
}
