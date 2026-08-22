import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vilvia/features/community/data/community_api_client.dart';
import 'package:vilvia/features/community/data/post.dart';
import 'package:vilvia/features/community/presentation/screens/community_screen.dart';

Post _fakePost({String title = 'First weeks with a newborn'}) => Post(
  id: '1',
  authorName: 'Alex',
  authorAvatarUrl: 'https://example.com/avatar.png',
  title: title,
  body: 'A supportive community message.',
  category: 'experiences',
  reactionCount: 2,
  commentCount: 3,
  createdAt: DateTime.utc(2026, 8, 22),
  updatedAt: DateTime.utc(2026, 8, 22),
);

class _StubApiClient extends CommunityApiClient {
  _StubApiClient(this.getPostsResult) : super(baseUrl: 'http://test');

  final Future<List<Post>> Function() getPostsResult;

  @override
  Future<List<Post>> getPosts() => getPostsResult();
}

class _SpyApiClient extends CommunityApiClient {
  _SpyApiClient() : super(baseUrl: 'http://test');

  bool closeCalled = false;

  @override
  Future<List<Post>> getPosts() async => [];

  @override
  void close() => closeCalled = true;
}

class _CreateAndRefreshApiClient extends CommunityApiClient {
  _CreateAndRefreshApiClient() : super(baseUrl: 'http://test');

  int getCalls = 0;

  @override
  Future<List<Post>> getPosts() async {
    getCalls++;
    return getCalls == 1 ? [] : [_fakePost(title: 'Newly published post')];
  }

  @override
  Future<Post> createPost({
    required String title,
    required String body,
    required String category,
  }) async => _fakePost(title: title);
}

void main() {
  Widget wrap(CommunityApiClient client) =>
      MaterialApp(home: CommunityScreen(apiClient: client));

  testWidgets('shows loading while the request is pending', (tester) async {
    final completer = Completer<List<Post>>();
    await tester.pumpWidget(wrap(_StubApiClient(() => completer.future)));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows posts on success without loading a remote avatar', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(_StubApiClient(() async => [_fakePost()])));
    await tester.pumpAndSettle();

    expect(find.text('First weeks with a newborn'), findsOneWidget);
    expect(find.text('A supportive community message.'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('2 reactions · 3 comments'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shows the empty state', (tester) async {
    await tester.pumpWidget(wrap(_StubApiClient(() async => [])));
    await tester.pumpAndSettle();

    expect(find.text('No community posts yet.'), findsOneWidget);
  });

  testWidgets('shows an error and retry button', (tester) async {
    await tester.pumpWidget(
      wrap(_StubApiClient(() async => throw Exception('network'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Failed to load community posts.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('retry reloads the feed', (tester) async {
    var calls = 0;
    final client = _StubApiClient(() {
      calls++;
      if (calls == 1) return Future.error(Exception('first request failed'));
      return Future.value([_fakePost(title: 'Loaded post')]);
    });
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Loaded post'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('does not update state after disposal', (tester) async {
    final completer = Completer<List<Post>>();
    await tester.pumpWidget(wrap(_StubApiClient(() => completer.future)));
    await tester.pumpWidget(const SizedBox());

    completer.complete([_fakePost()]);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('does not close an injected client', (tester) async {
    final client = _SpyApiClient();
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());

    expect(client.closeCalled, isFalse);
  });

  testWidgets('successful creation refreshes the community feed', (
    tester,
  ) async {
    final client = _CreateAndRefreshApiClient();
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Post'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'New post');
    await tester.enterText(find.widgetWithText(TextField, 'Post'), 'Post body');
    await tester.tap(find.text('Publish Post'));
    await tester.pumpAndSettle();

    expect(client.getCalls, 2);
    expect(find.text('Newly published post'), findsOneWidget);
  });
}
