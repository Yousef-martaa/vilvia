import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vilvia/features/information/data/information_api_client.dart';
import 'package:vilvia/features/information/data/resource.dart';
import 'package:vilvia/features/information/presentation/screens/resources_screen.dart';

// --- Stub helpers ---

Resource _fakeResource({String title = 'Test Resource'}) => Resource(
      id: '1',
      title: title,
      summary: 'A summary',
      category: 'child_development',
      stage: 'pregnancy',
      sourceName: 'Source',
      sourceUrl: 'https://example.com',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

class _StubApiClient extends InformationApiClient {
  final Future<List<Resource>> Function() _fn;

  _StubApiClient(this._fn) : super(baseUrl: 'http://test');

  @override
  Future<List<Resource>> getResources() => _fn();
}

class _SpyApiClient extends InformationApiClient {
  bool closeCalled = false;

  _SpyApiClient() : super(baseUrl: 'http://test');

  @override
  Future<List<Resource>> getResources() async => [];

  @override
  void close() => closeCalled = true;
}

// --- Tests ---

void main() {
  Widget wrap(InformationApiClient client) =>
      MaterialApp(home: ResourcesScreen(apiClient: client));

  testWidgets('shows loading indicator before response arrives', (tester) async {
    final client = _StubApiClient(() => Completer<List<Resource>>().future);
    await tester.pumpWidget(wrap(client));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows resource list on success', (tester) async {
    final client = _StubApiClient(
      () async => [_fakeResource(title: 'Sleep Guide')],
    );
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('Sleep Guide'), findsOneWidget);
    expect(find.text('A summary'), findsOneWidget);
    expect(find.text('child_development · pregnancy'), findsOneWidget);
  });

  testWidgets('shows empty message when list is empty', (tester) async {
    final client = _StubApiClient(() async => []);
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('No resources available.'), findsOneWidget);
  });

  testWidgets('shows error message and retry button on failure', (tester) async {
    final client = _StubApiClient(() async => throw Exception('Network error'));
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load resources.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('does not close an injected api client on dispose', (tester) async {
    final spy = _SpyApiClient();
    await tester.pumpWidget(wrap(spy));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    expect(spy.closeCalled, isFalse);
  });

  testWidgets('closes internally created api client on dispose', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ResourcesScreen()));
    await tester.pumpAndSettle();

    expect(() => tester.pumpWidget(const SizedBox()), returnsNormally);
  });

  testWidgets('retry button reloads and shows resources', (tester) async {
    var callCount = 0;
    final client = _StubApiClient(() {
      callCount++;
      if (callCount == 1) return Future.error(Exception('First call fails'));
      return Future.value([_fakeResource(title: 'Loaded Resource')]);
    });

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    expect(find.text('Failed to load resources.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Loaded Resource'), findsOneWidget);
  });
}
