import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:vilvia/core/constants/api_constants.dart';
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
    final response = await _client.get(Uri.parse('$_baseUrl/posts'));

    if (response.statusCode != 200) {
      throw Exception('Failed to load posts: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Invalid response: expected a JSON list');
    }

    return decoded.cast<Map<String, dynamic>>().map(Post.fromJson).toList();
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
}
