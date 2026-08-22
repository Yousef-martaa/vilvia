class Post {
  final String id;
  final String authorName;
  final String? authorAvatarUrl;
  final String title;
  final String body;
  final String category;
  final int reactionCount;
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
      commentCount: json['comment_count'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
