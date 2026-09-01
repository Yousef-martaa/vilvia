enum ReportStatus {
  pending,
  reviewed,
  dismissed;

  static ReportStatus fromJson(String value) =>
      ReportStatus.values.byName(value);
}

enum ReportTargetKind {
  post,
  comment;

  static ReportTargetKind fromJson(String value) =>
      ReportTargetKind.values.byName(value);
}

class ReportPostContext {
  const ReportPostContext({
    required this.id,
    required this.title,
    required this.body,
  });

  final String id;
  final String title;
  final String body;

  factory ReportPostContext.fromJson(Map<String, dynamic> json) =>
      ReportPostContext(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
      );
}

class ReportCommentContext {
  const ReportCommentContext({
    required this.id,
    required this.body,
    required this.postId,
    required this.postTitle,
  });

  final String id;
  final String body;
  final String postId;
  final String postTitle;

  factory ReportCommentContext.fromJson(Map<String, dynamic> json) =>
      ReportCommentContext(
        id: json['id'] as String,
        body: json['body'] as String,
        postId: json['post_id'] as String,
        postTitle: json['post_title'] as String,
      );
}

class AdminReport {
  const AdminReport({
    required this.id,
    required this.reason,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.targetKind,
    required this.targetId,
    required this.targetIsHidden,
    this.post,
    this.comment,
  });

  final String id;
  final String reason;
  final ReportStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ReportTargetKind targetKind;
  final String targetId;
  final bool targetIsHidden;
  final ReportPostContext? post;
  final ReportCommentContext? comment;

  AdminReport withTargetVisibility(bool targetIsHidden) => AdminReport(
    id: id,
    reason: reason,
    status: status,
    createdAt: createdAt,
    updatedAt: updatedAt,
    targetKind: targetKind,
    targetId: targetId,
    targetIsHidden: targetIsHidden,
    post: post,
    comment: comment,
  );

  factory AdminReport.fromJson(Map<String, dynamic> json) {
    try {
      final targetKind = ReportTargetKind.fromJson(
        json['target_kind'] as String,
      );
      final targetId = json['target_id'] as String;
      final post = json['post'] == null
          ? null
          : ReportPostContext.fromJson(json['post'] as Map<String, dynamic>);
      final comment = json['comment'] == null
          ? null
          : ReportCommentContext.fromJson(
              json['comment'] as Map<String, dynamic>,
            );

      final hasValidPost =
          targetKind == ReportTargetKind.post &&
          post != null &&
          comment == null &&
          post.id == targetId;
      final hasValidComment =
          targetKind == ReportTargetKind.comment &&
          comment != null &&
          post == null &&
          comment.id == targetId;
      if (!hasValidPost && !hasValidComment) {
        throw const FormatException('Invalid report target context.');
      }

      return AdminReport(
        id: json['id'] as String,
        reason: json['reason'] as String,
        status: ReportStatus.fromJson(json['status'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        targetKind: targetKind,
        targetId: targetId,
        targetIsHidden: json['target_is_hidden'] as bool,
        post: post,
        comment: comment,
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid admin report response: $error');
    }
  }
}
