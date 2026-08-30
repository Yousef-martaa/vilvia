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
    'has_reacted': false,
    'comment_count': 3,
    'created_at': '2026-08-22T10:00:00Z',
    'updated_at': '2026-08-22T10:00:00Z',
  };

  Map<String, dynamic> commentJson() => {
    'id': '223e4567-e89b-12d3-a456-426614174000',
    'author_name': 'Rowan',
    'author_avatar_url': null,
    'body': 'A comment.',
    'created_at': '2026-08-22T11:00:00Z',
    'updated_at': '2026-08-22T11:00:00Z',
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
      expect(posts.single.hasReacted, isFalse);
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

    test('supplies authentication when a session exists', () async {
      final api = CommunityApiClient(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response('[]', 200);
        }),
        baseUrl: testBaseUrl,
        accessToken: () => 'token',
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

  group('CommunityApiClient reactions', () {
    test('sends authenticated PUT and parses authoritative state', () async {
      final api = CommunityApiClient(
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/posts/post-1/reaction');
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response(
            jsonEncode({'reacted': true, 'reaction_count': 3}),
            200,
          );
        }),
        baseUrl: testBaseUrl,
        accessToken: () => 'token',
      );

      final result = await api.setPostReaction(postId: 'post-1', reacted: true);

      expect(result.reacted, isTrue);
      expect(result.reactionCount, 3);
    });

    test('sends authenticated DELETE', () async {
      final api = CommunityApiClient(
        client: MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/posts/post-1/reaction');
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response(
            jsonEncode({'reacted': false, 'reaction_count': 1}),
            200,
          );
        }),
        baseUrl: testBaseUrl,
        accessToken: () => 'token',
      );

      final result = await api.setPostReaction(
        postId: 'post-1',
        reacted: false,
      );

      expect(result.reacted, isFalse);
      expect(result.reactionCount, 1);
    });

    test('requires a session and preserves server failures', () {
      final signedOut = CommunityApiClient(baseUrl: testBaseUrl);
      final failing = CommunityApiClient(
        client: MockClient((_) async => http.Response('error', 409)),
        baseUrl: testBaseUrl,
        accessToken: () => 'token',
      );

      expect(
        signedOut.setPostReaction(postId: 'post-1', reacted: true),
        throwsStateError,
      );
      expect(
        failing.setPostReaction(postId: 'post-1', reacted: true),
        throwsException,
      );
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

  group('CommunityApiClient comments', () {
    test('reads comments publicly', () async {
      final api = CommunityApiClient(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/posts/post-1/comments');
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response(jsonEncode([commentJson()]), 200);
        }),
        baseUrl: testBaseUrl,
      );

      final comments = await api.getComments('post-1');

      expect(comments.single.authorName, 'Rowan');
      expect(comments.single.body, 'A comment.');
    });

    test('rejects a non-list comments response', () {
      final api = CommunityApiClient(
        client: MockClient((_) async => http.Response('{}', 200)),
        baseUrl: testBaseUrl,
      );

      expect(api.getComments('post-1'), throwsException);
    });

    test(
      'creates a body-only comment and parses authoritative count',
      () async {
        final api = CommunityApiClient(
          client: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/posts/post-1/comments');
            expect(request.headers['Authorization'], 'Bearer token');
            expect(jsonDecode(request.body), {'body': 'Hello'});
            return http.Response(
              jsonEncode({'comment': commentJson(), 'comment_count': 4}),
              201,
            );
          }),
          baseUrl: testBaseUrl,
          accessToken: () => 'token',
        );

        final created = await api.createComment(
          postId: 'post-1',
          body: 'Hello',
        );

        expect(created.comment.body, 'A comment.');
        expect(created.commentCount, 4);
      },
    );

    test('comment creation requires a session', () {
      final api = CommunityApiClient(baseUrl: testBaseUrl);

      expect(
        api.createComment(postId: 'post-1', body: 'Hello'),
        throwsStateError,
      );
    });

    test('comment requests throw on unsuccessful responses', () {
      final api = CommunityApiClient(
        client: MockClient((request) async => http.Response('error', 404)),
        baseUrl: testBaseUrl,
        accessToken: () => 'token',
      );

      expect(api.getComments('post-1'), throwsException);
      expect(
        api.createComment(postId: 'post-1', body: 'Hello'),
        throwsException,
      );
    });
  });

  group('CommunityApiClient reports', () {
    test('reports posts with authenticated PUT and parses count', () async {
      final api = CommunityApiClient(
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/posts/post-1/report');
          expect(request.headers['Authorization'], 'Bearer token');
          expect(jsonDecode(request.body), {'reason': 'Unsafe advice'});
          return http.Response(
            jsonEncode({'reported': true, 'report_count': 2}),
            200,
          );
        }),
        baseUrl: testBaseUrl,
        accessToken: () => 'token',
      );

      final result = await api.reportPost(
        postId: 'post-1',
        reason: 'Unsafe advice',
      );

      expect(result.reported, isTrue);
      expect(result.reportCount, 2);
    });

    test('reports comments through the nested authenticated path', () async {
      final api = CommunityApiClient(
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/posts/post-1/comments/comment-1/report');
          expect(request.headers['Authorization'], 'Bearer token');
          expect(jsonDecode(request.body), {'reason': 'Harassment'});
          return http.Response(
            jsonEncode({'reported': true, 'report_count': 1}),
            200,
          );
        }),
        baseUrl: testBaseUrl,
        accessToken: () => 'token',
      );

      final result = await api.reportComment(
        postId: 'post-1',
        commentId: 'comment-1',
        reason: 'Harassment',
      );

      expect(result.reportCount, 1);
    });

    test('requires a session without sending a request', () {
      var sent = false;
      final api = CommunityApiClient(
        client: MockClient((_) async {
          sent = true;
          return http.Response('{}', 200);
        }),
        baseUrl: testBaseUrl,
      );

      expect(
        api.reportPost(postId: 'post-1', reason: 'Reason'),
        throwsStateError,
      );
      expect(sent, isFalse);
    });

    test('throws on an unsuccessful report response', () {
      final api = CommunityApiClient(
        client: MockClient((_) async => http.Response('error', 404)),
        baseUrl: testBaseUrl,
        accessToken: () => 'token',
      );

      expect(
        api.reportComment(
          postId: 'post-1',
          commentId: 'comment-1',
          reason: 'Reason',
        ),
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
