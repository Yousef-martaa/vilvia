import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:vilvia/core/constants/api_constants.dart';
import 'package:vilvia/features/community/data/post.dart';

class CommunityApiClient {
  final http.Client _client;
  final String _baseUrl;
  final bool _ownsClient;

  CommunityApiClient({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
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
}
