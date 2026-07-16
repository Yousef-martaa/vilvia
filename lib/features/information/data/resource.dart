class Resource {
  final String id;
  final String title;
  final String summary;
  final String category;
  final String stage;
  final String sourceName;
  final String sourceUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Resource({
    required this.id,
    required this.title,
    required this.summary,
    required this.category,
    required this.stage,
    required this.sourceName,
    required this.sourceUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Resource.fromJson(Map<String, dynamic> json) {
    return Resource(
      id: json['id'] as String,
      title: json['title'] as String,
      summary: json['summary'] as String,
      category: json['category'] as String,
      stage: json['stage'] as String,
      sourceName: json['source_name'] as String,
      sourceUrl: json['source_url'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
