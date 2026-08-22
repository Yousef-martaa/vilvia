import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:vilvia/features/community/data/community_api_client.dart';

class _TrackingClient extends http.BaseClient {
  bool closeCalled = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnsupportedError('not used in close tests');
  }

  @override
  void close() {
    closeCalled = true;
    super.close();
  }
}

void main() {
  const testBaseUrl = 'http://localhost';

  Map<String, dynamic> postJson() => {
    'id': '123e4567-e89b-12d3-a456-426614174000',
    'author_name': 'Alex',
    'author_avatar_url': null,
    'title': 'A community post',
    'body': 'A supportive message.',
    'category': 'experiences',
    'reaction_count': 2,
    'comment_count': 3,
    'created_at': '2026-08-22T10:00:00Z',
    'updated_at': '2026-08-22T10:00:00Z',
  };

  group('CommunityApiClient.getPosts', () {
    test('requests public posts and parses a successful response', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/posts');
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response(jsonEncode([postJson()]), 200);
      });
      final api = CommunityApiClient(client: client, baseUrl: testBaseUrl);

      final posts = await api.getPosts();

      expect(posts, hasLength(1));
      expect(posts.single.authorName, 'Alex');
      expect(posts.single.authorAvatarUrl, isNull);
      expect(posts.single.title, 'A community post');
      expect(posts.single.reactionCount, 2);
      expect(posts.single.commentCount, 3);
      expect(posts.single.createdAt, DateTime.utc(2026, 8, 22, 10));
    });

    test('returns an empty list for an empty response', () async {
      final api = CommunityApiClient(
        client: MockClient((_) async => http.Response('[]', 200)),
        baseUrl: testBaseUrl,
      );

      expect(await api.getPosts(), isEmpty);
    });

    test('throws on a non-200 response', () {
      final api = CommunityApiClient(
        client: MockClient((_) async => http.Response('error', 500)),
        baseUrl: testBaseUrl,
      );

      expect(api.getPosts(), throwsException);
    });

    test('throws when the response is not a list', () {
      final api = CommunityApiClient(
        client: MockClient(
          (_) async => http.Response(jsonEncode({'error': 'bad'}), 200),
        ),
        baseUrl: testBaseUrl,
      );

      expect(api.getPosts(), throwsException);
    });
  });

  group('CommunityApiClient.createPost', () {
    test('sends only content fields with the bearer token', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/posts');
        expect(request.headers['Authorization'], 'Bearer token');
        expect(jsonDecode(request.body), {
          'title': 'Question',
          'body': 'Post body',
          'category': 'qa',
        });
        return http.Response(jsonEncode(postJson()), 201);
      });
      final api = CommunityApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => 'token',
      );

      final post = await api.createPost(
        title: 'Question',
        body: 'Post body',
        category: 'qa',
      );

      expect(post.title, 'A community post');
    });

    test('requires an active session before sending', () {
      final api = CommunityApiClient(
        client: MockClient((_) async => throw StateError('should not send')),
        baseUrl: testBaseUrl,
      );

      expect(
        api.createPost(title: 'Title', body: 'Body', category: 'qa'),
        throwsStateError,
      );
    });

    test('throws on a failed submission', () {
      final api = CommunityApiClient(
        client: MockClient((_) async => http.Response('conflict', 409)),
        baseUrl: testBaseUrl,
        accessToken: () => 'token',
      );

      expect(
        api.createPost(title: 'Title', body: 'Body', category: 'qa'),
        throwsException,
      );
    });
  });

  group('CommunityApiClient.close', () {
    test('does not close an injected client', () {
      final client = _TrackingClient();
      CommunityApiClient(client: client, baseUrl: testBaseUrl).close();
      expect(client.closeCalled, isFalse);
    });

    test('does not throw for an internally owned client', () {
      final api = CommunityApiClient(baseUrl: testBaseUrl);
      expect(api.close, returnsNormally);
    });
  });
}
