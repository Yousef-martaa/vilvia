import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vilvia/features/community/data/community_api_client.dart';
import 'package:vilvia/features/community/data/post.dart';
import 'package:vilvia/features/community/presentation/screens/create_post_screen.dart';

class _SpyClient extends CommunityApiClient {
  _SpyClient({this.error}) : super(baseUrl: 'http://test');

  final Object? error;
  int calls = 0;
  String? title;
  String? body;
  String? category;

  @override
  Future<Post> createPost({
    required String title,
    required String body,
    required String category,
  }) async {
    calls++;
    this.title = title;
    this.body = body;
    this.category = category;
    if (error != null) throw error!;
    return Post(
      id: '1',
      authorName: 'Rowan',
      authorAvatarUrl: null,
      title: title,
      body: body,
      category: category,
      reactionCount: 0,
      hasReacted: false,
      commentCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }
}

void main() {
  Widget wrap(_SpyClient client) =>
      MaterialApp(home: CreatePostScreen(apiClient: client));

  testWidgets('valid content is submitted and reports creation', (
    tester,
  ) async {
    final client = _SpyClient();
    await tester.pumpWidget(wrap(client));
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      ' Question ',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Post'), ' Body ');

    await tester.tap(find.text('Publish Post'));
    await tester.pumpAndSettle();

    expect(client.calls, 1);
    expect(client.title, 'Question');
    expect(client.body, 'Body');
    expect(client.category, 'experiences');
  });

  testWidgets('submission error preserves all form content', (tester) async {
    final client = _SpyClient(error: Exception('409'));
    await tester.pumpWidget(wrap(client));
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'My title');
    await tester.tap(find.text('Experiences'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Family life').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Post'), 'My body');

    await tester.tap(find.text('Publish Post'));
    await tester.pumpAndSettle();

    expect(find.text('My title'), findsOneWidget);
    expect(find.text('My body'), findsOneWidget);
    expect(find.text('Family life'), findsOneWidget);
    expect(find.textContaining('409'), findsOneWidget);
  });

  testWidgets('empty content is rejected without a request', (tester) async {
    final client = _SpyClient();
    await tester.pumpWidget(wrap(client));

    await tester.tap(find.text('Publish Post'));
    await tester.pump();

    expect(client.calls, 0);
    expect(find.textContaining('Please enter a title'), findsOneWidget);
  });
}
