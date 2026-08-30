import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vilvia/features/community/data/comment.dart';
import 'package:vilvia/features/community/data/community_api_client.dart';
import 'package:vilvia/features/community/data/post.dart';
import 'package:vilvia/features/community/presentation/widgets/comments_sheet.dart';

Post _post() => Post(
  id: 'post-1',
  authorName: 'Alex',
  authorAvatarUrl: null,
  title: 'A post',
  body: 'Post body',
  category: 'qa',
  reactionCount: 0,
  hasReacted: false,
  commentCount: 2,
  createdAt: DateTime.utc(2026, 8, 22),
  updatedAt: DateTime.utc(2026, 8, 22),
);

Comment _comment({String body = 'Existing comment'}) => Comment(
  id: body,
  authorName: 'Rowan',
  authorAvatarUrl: null,
  body: body,
  createdAt: DateTime.utc(2026, 8, 22),
  updatedAt: DateTime.utc(2026, 8, 22),
);

class _StubClient extends CommunityApiClient {
  _StubClient({required this.load, this.createError, this.createdCount = 3})
    : super(baseUrl: 'http://test');

  final Future<List<Comment>> Function() load;
  final Object? createError;
  final int createdCount;
  int loadCalls = 0;
  int createCalls = 0;
  String? submittedBody;

  @override
  Future<List<Comment>> getComments(String postId) {
    loadCalls++;
    return load();
  }

  @override
  Future<CreatedComment> createComment({
    required String postId,
    required String body,
  }) async {
    createCalls++;
    submittedBody = body;
    if (createError != null) throw createError!;
    return CreatedComment(
      comment: _comment(body: body),
      commentCount: createdCount,
    );
  }
}

void main() {
  Widget wrap(
    _StubClient client, {
    bool signedIn = false,
    ValueChanged<int>? onCount,
  }) => MaterialApp(
    home: Scaffold(
      body: CommentsSheet(
        post: _post(),
        apiClient: client,
        isSignedIn: signedIn,
        onCommentCountChanged: onCount ?? (_) {},
      ),
    ),
  );

  testWidgets('shows loading, comments, and signed-out guidance', (
    tester,
  ) async {
    final completer = Completer<List<Comment>>();
    final client = _StubClient(load: () => completer.future);
    await tester.pumpWidget(wrap(client));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete([_comment()]);
    await tester.pumpAndSettle();

    expect(find.text('Existing comment'), findsOneWidget);
    expect(find.text('Sign in to add a comment.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('shows empty state', (tester) async {
    await tester.pumpWidget(wrap(_StubClient(load: () async => [])));
    await tester.pumpAndSettle();
    expect(find.text('No comments yet.'), findsOneWidget);
  });

  testWidgets('load failure can be retried', (tester) async {
    var calls = 0;
    final client = _StubClient(
      load: () {
        calls++;
        if (calls == 1) return Future.error(Exception('network'));
        return Future.value([_comment()]);
      },
    );
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    expect(find.text('Failed to load comments.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Existing comment'), findsOneWidget);
  });

  testWidgets('success appends comment, clears text, and publishes count', (
    tester,
  ) async {
    int? count;
    final client = _StubClient(load: () async => [_comment()], createdCount: 7);
    await tester.pumpWidget(
      wrap(client, signedIn: true, onCount: (value) => count = value),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Add a comment'),
      '  New comment  ',
    );
    await tester.tap(find.text('Post Comment'));
    await tester.pumpAndSettle();

    expect(client.submittedBody, 'New comment');
    expect(find.text('New comment'), findsOneWidget);
    expect(find.text('Comments (7)'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Add a comment'), findsOneWidget);
    expect(count, 7);
  });

  testWidgets('submission failure preserves text', (tester) async {
    final client = _StubClient(
      load: () async => [],
      createError: Exception('409'),
    );
    await tester.pumpWidget(wrap(client, signedIn: true));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Add a comment'),
      'Keep this text',
    );
    await tester.tap(find.text('Post Comment'));
    await tester.pumpAndSettle();

    expect(find.text('Keep this text'), findsOneWidget);
    expect(find.textContaining('409'), findsOneWidget);
  });

  testWidgets('invalid content does not submit', (tester) async {
    final client = _StubClient(load: () async => []);
    await tester.pumpWidget(wrap(client, signedIn: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Post Comment'));
    await tester.pump();

    expect(client.createCalls, 0);
    expect(find.textContaining('Please enter a comment'), findsOneWidget);
  });
}
