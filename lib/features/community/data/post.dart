class Post {
  final String id;
  final String authorName;
  final String? authorAvatarUrl;
  final String title;
  final String body;
  final String category;
  final int reactionCount;
  final bool hasReacted;
  final int commentCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Post({
    required this.id,
    required this.authorName,
    required this.authorAvatarUrl,
    required this.title,
    required this.body,
    required this.category,
    required this.reactionCount,
    required this.hasReacted,
    required this.commentCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as String,
      authorName: json['author_name'] as String,
      authorAvatarUrl: json['author_avatar_url'] as String?,
      title: json['title'] as String,
      body: json['body'] as String,
      category: json['category'] as String,
      reactionCount: json['reaction_count'] as int,
      hasReacted: json['has_reacted'] as bool,
      commentCount: json['comment_count'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Post copyWith({int? reactionCount, bool? hasReacted, int? commentCount}) =>
      Post(
        id: id,
        authorName: authorName,
        authorAvatarUrl: authorAvatarUrl,
        title: title,
        body: body,
        category: category,
        reactionCount: reactionCount ?? this.reactionCount,
        hasReacted: hasReacted ?? this.hasReacted,
        commentCount: commentCount ?? this.commentCount,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
