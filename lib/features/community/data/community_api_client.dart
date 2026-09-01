import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:vilvia/core/constants/api_constants.dart';
import 'package:vilvia/features/community/data/comment.dart';
import 'package:vilvia/features/community/data/admin_report.dart';
import 'package:vilvia/features/community/data/post.dart';

class CommunityApiClient {
  final http.Client _client;
  final String _baseUrl;
  final bool _ownsClient;
  final String? Function()? _accessToken;

  CommunityApiClient({http.Client? client, String? baseUrl, this._accessToken})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl = baseUrl ?? apiBaseUrl;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<List<Post>> getPosts() async {
    final token = _accessToken?.call();
    final response = await _client.get(
      Uri.parse('$_baseUrl/posts'),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load posts: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Invalid response: expected a JSON list');
    }

    return decoded.cast<Map<String, dynamic>>().map(Post.fromJson).toList();
  }

  Future<PostReactionResult> setPostReaction({
    required String postId,
    required bool reacted,
  }) async {
    final token = _accessToken?.call();
    if (token == null) {
      throw StateError(
        'No active session; cannot call an authenticated endpoint.',
      );
    }

    final request = http.Request(
      reacted ? 'PUT' : 'DELETE',
      Uri.parse('$_baseUrl/posts/$postId/reaction'),
    )..headers['Authorization'] = 'Bearer $token';
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200) {
      throw Exception('Failed to update reaction: ${response.statusCode}');
    }
    return PostReactionResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<Post> createPost({
    required String title,
    required String body,
    required String category,
  }) async {
    final token = _accessToken?.call();
    if (token == null) {
      throw StateError(
        'No active session; cannot call an authenticated endpoint.',
      );
    }

    final response = await _client.post(
      Uri.parse('$_baseUrl/posts'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'title': title, 'body': body, 'category': category}),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to create post: ${response.statusCode}');
    }
    return Post.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<Comment>> getComments(String postId) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/posts/$postId/comments'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load comments: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Invalid response: expected a JSON list');
    }
    return decoded.cast<Map<String, dynamic>>().map(Comment.fromJson).toList();
  }

  Future<CreatedComment> createComment({
    required String postId,
    required String body,
  }) async {
    final token = _accessToken?.call();
    if (token == null) {
      throw StateError(
        'No active session; cannot call an authenticated endpoint.',
      );
    }

    final response = await _client.post(
      Uri.parse('$_baseUrl/posts/$postId/comments'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'body': body}),
    );
    if (response.statusCode != 201) {
      throw Exception('Failed to create comment: ${response.statusCode}');
    }
    return CreatedComment.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ReportResult> reportPost({
    required String postId,
    required String reason,
  }) => _submitReport(path: '/posts/$postId/report', reason: reason);

  Future<ReportResult> reportComment({
    required String postId,
    required String commentId,
    required String reason,
  }) => _submitReport(
    path: '/posts/$postId/comments/$commentId/report',
    reason: reason,
  );

  Future<ReportResult> _submitReport({
    required String path,
    required String reason,
  }) async {
    final token = _accessToken?.call();
    if (token == null) {
      throw StateError(
        'No active session; cannot call an authenticated endpoint.',
      );
    }

    final response = await _client.put(
      Uri.parse('$_baseUrl$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'reason': reason}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to submit report: ${response.statusCode}');
    }
    return ReportResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<AdminReport>> getAdminReports({
    ReportStatus status = ReportStatus.pending,
    int limit = 50,
    int offset = 0,
  }) async {
    final token = _requireAccessToken();
    final uri = Uri.parse('$_baseUrl/reports').replace(
      queryParameters: {
        'status': status.name,
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final response = await _client.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load reports: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Invalid response: expected a JSON list');
    }
    return decoded
        .cast<Map<String, dynamic>>()
        .map(AdminReport.fromJson)
        .toList();
  }

  Future<AdminReport> updateAdminReportStatus({
    required String reportId,
    required ReportStatus status,
  }) async {
    final token = _requireAccessToken();
    final response = await _client.put(
      Uri.parse('$_baseUrl/reports/$reportId/status'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'status': status.name}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update report: ${response.statusCode}');
    }
    return AdminReport.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AdminReport> updateAdminReportTargetVisibility({
    required String reportId,
    required bool isHidden,
  }) async {
    final token = _requireAccessToken();
    final response = await _client.put(
      Uri.parse('$_baseUrl/reports/$reportId/target-visibility'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'is_hidden': isHidden}),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to update report target visibility: ${response.statusCode}',
      );
    }
    return AdminReport.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  String _requireAccessToken() {
    final token = _accessToken?.call();
    if (token == null) {
      throw StateError(
        'No active session; cannot call an authenticated endpoint.',
      );
    }
    return token;
  }
}

class PostReactionResult {
  const PostReactionResult({
    required this.reacted,
    required this.reactionCount,
  });

  final bool reacted;
  final int reactionCount;

  factory PostReactionResult.fromJson(Map<String, dynamic> json) =>
      PostReactionResult(
        reacted: json['reacted'] as bool,
        reactionCount: json['reaction_count'] as int,
      );
}

class ReportResult {
  const ReportResult({required this.reported, required this.reportCount});

  final bool reported;
  final int reportCount;

  factory ReportResult.fromJson(Map<String, dynamic> json) => ReportResult(
    reported: json['reported'] as bool,
    reportCount: json['report_count'] as int,
  );
}
